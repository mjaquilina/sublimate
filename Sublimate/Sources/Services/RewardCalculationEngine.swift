import Foundation
import GRDB

/// Preview of rewards that will be earned from a transaction
struct TransactionRewardPreview {
    let transaction: Transaction
    let earningRuleReward: EarningRuleReward?
    let spendOfferRewards: [SpendOfferReward]
    let rebateRewards: [RebateReward]

    var totalPointsValue: Decimal {
        (earningRuleReward?.cashValue ?? 0)
    }

    var totalSpendOfferValue: Decimal {
        spendOfferRewards.reduce(0) { $0 + $1.cashValue }
    }

    var totalRebateValue: Decimal {
        rebateRewards.reduce(0) { $0 + $1.cashValue }
    }

    var totalRewardValue: Decimal {
        totalPointsValue + totalSpendOfferValue + totalRebateValue
    }

    var pointBalanceChanges: [UUID: Decimal] {
        var changes: [UUID: Decimal] = [:]

        // Add earning rule points
        if let earning = earningRuleReward, let pointTypeId = earning.pointTypeId {
            changes[pointTypeId, default: 0] += earning.pointsEarned ?? 0
        }

        // Add spend offer points
        for offer in spendOfferRewards {
            if let pointTypeId = offer.pointTypeId, let points = offer.pointsEarned {
                changes[pointTypeId, default: 0] += points
            }
        }

        return changes
    }
}

struct EarningRuleReward {
    let rule: EarningRule
    let pointsEarned: Decimal?
    let cashValue: Decimal
    let pointTypeId: UUID?
}

struct SpendOfferReward {
    let offer: SpendOffer
    let cashValue: Decimal
    let pointsEarned: Decimal?
    let pointTypeId: UUID?
    let progressUpdate: String
}

struct RebateReward {
    let rebate: Rebate
    let cashValue: Decimal
    let usesRemainingAfter: Int?
}

/// Core engine for calculating rewards from transactions
class RewardCalculationEngine {
    private let db: DatabaseQueue

    init(database: DatabaseQueue) {
        self.db = database
    }

    // MARK: - Main Calculation Flow

    /// Calculate all rewards for a transaction (preview only, doesn't save)
    func calculateTransactionRewards(_ transaction: Transaction) throws -> TransactionRewardPreview {
        return try db.read { db in
            // Step 0: Filter eligibility
            guard transaction.isEligibleForRewards else {
                return TransactionRewardPreview(
                    transaction: transaction,
                    earningRuleReward: nil,
                    spendOfferRewards: [],
                    rebateRewards: []
                )
            }

            // Step 1: Earning rule selection
            let earningReward = try calculateEarningRuleReward(db, transaction: transaction)

            // Step 2: Spend offer evaluation
            let spendOfferRewards = try calculateSpendOfferRewards(db, transaction: transaction)

            // Step 3: Rebate evaluation
            let rebateRewards = try calculateRebateRewards(db, transaction: transaction)

            return TransactionRewardPreview(
                transaction: transaction,
                earningRuleReward: earningReward,
                spendOfferRewards: spendOfferRewards,
                rebateRewards: rebateRewards
            )
        }
    }

    /// Reverses the recorded effects of a transaction on caps, balances, and offer progress.
    /// Only touches items that have a corresponding TransactionReward record — callers must
    /// ensure records exist for every offer the transaction contributed to (see applyRewardRecords).
    func reverseTransactionCaches(_ transaction: Transaction) throws {
        try db.write { db in
            let rewards = try TransactionReward.forTransaction(db, transactionId: transaction.id)

            for reward in rewards {
                if reward.rewardSourceType == "earning_rule" {
                    let caps = try EarningRuleCap.capsForRule(db, ruleId: reward.rewardSourceId)
                    for cap in caps where transaction.date >= cap.startDate && transaction.date <= cap.endDate {
                        var mutableCap = cap
                        mutableCap.currentSpend -= transaction.amount
                        mutableCap.currentSpend = max(0, mutableCap.currentSpend)
                        try mutableCap.update(db)
                    }
                    if let pointTypeId = reward.pointTypeId, let points = reward.pointsEarned {
                        try updatePointBalance(db, pointTypeId: pointTypeId, amount: -points)
                    }
                }

                if reward.rewardSourceType == "spend_offer",
                   var offer = try SpendOffer.filter(SpendOffer.Columns.id == reward.rewardSourceId).fetchOne(db) {
                    offer.currentSpend -= transaction.amount
                    offer.currentCount -= 1
                    offer.currentSpend = max(0, offer.currentSpend)
                    offer.currentCount = max(0, offer.currentCount)
                    try offer.update(db)
                    if let pointTypeId = reward.pointTypeId, let points = reward.pointsEarned {
                        try updatePointBalance(db, pointTypeId: pointTypeId, amount: -points)
                    }
                }

                if reward.rewardSourceType == "rebate",
                   var rebate = try Rebate.filter(Rebate.Columns.id == reward.rewardSourceId).fetchOne(db) {
                    if let maxUses = rebate.maxUses {
                        rebate.usesRemaining = min((rebate.usesRemaining ?? 0) + 1, maxUses)
                        try rebate.update(db)
                    }
                }
            }
        }
    }

    /// Delete transaction and reverse all cache updates
    func deleteTransactionWithRewards(_ transaction: Transaction) throws {
        try reverseTransactionCaches(transaction)

        try db.write { db in
            // Delete rewards (will cascade or be handled separately)
            let rewards = try TransactionReward.forTransaction(db, transactionId: transaction.id)
            for reward in rewards {
                try reward.delete(db)
            }

            // Delete transaction
            try transaction.delete(db)
        }
    }

    /// Update transaction with new data and recalculate rewards
    func updateTransactionWithRewards(_ oldTransaction: Transaction, newTransaction: Transaction) throws {
        try reverseTransactionCaches(oldTransaction)
        try db.write { db in
            let oldRewards = try TransactionReward.forTransaction(db, transactionId: oldTransaction.id)
            for reward in oldRewards { try reward.delete(db) }
            try oldTransaction.delete(db)
        }
        let preview = try calculateTransactionRewards(newTransaction)
        try db.write { db in
            var mutableTransaction = newTransaction
            try mutableTransaction.insert(db)
            try applyRewardRecords(db, transaction: newTransaction, preview: preview)
        }
    }

    /// Save transaction with rewards to database
    func saveTransactionWithRewards(_ transaction: Transaction, preview: TransactionRewardPreview) throws {
        try db.write { db in
            var mutableTransaction = transaction
            try mutableTransaction.insert(db)
            try applyRewardRecords(db, transaction: transaction, preview: preview)
        }
    }

    /// Idempotently recalculates rewards for an already-persisted transaction.
    /// Reverses existing reward effects via records, deletes those records, then
    /// recalculates and re-applies. Safe to call on any transaction at any time,
    /// including as a retroactive backfill when new offers or rules are added.
    func syncTransactionRewards(_ transaction: Transaction) throws {
        try reverseTransactionCaches(transaction)
        try db.write { db in
            let existing = try TransactionReward.forTransaction(db, transactionId: transaction.id)
            for reward in existing { try reward.delete(db) }
        }
        guard transaction.isEligibleForRewards else { return }
        let preview = try calculateTransactionRewards(transaction)
        try db.write { db in
            try applyRewardRecords(db, transaction: transaction, preview: preview)
        }
    }

    /// Writes reward records and updates all derived state (balances, offer progress, caps).
    /// Assumes the transaction is already persisted. Always creates a TransactionReward record
    /// for every matching spend offer — even when cashValue is 0 — so that reverseTransactionCaches
    /// can undo progress contributions purely from records without guessing what matched.
    private func applyRewardRecords(_ db: Database, transaction: Transaction, preview: TransactionRewardPreview) throws {
        if let earning = preview.earningRuleReward {
            let reward = TransactionReward(
                transactionId: transaction.id,
                rewardSourceType: "earning_rule",
                rewardSourceId: earning.rule.id,
                pointTypeId: earning.pointTypeId,
                pointsEarned: earning.pointsEarned,
                cashValue: earning.cashValue,
                description: earning.rule.name
            )
            try reward.insert(db)

            if let pointTypeId = earning.pointTypeId, let points = earning.pointsEarned {
                try updatePointBalance(db, pointTypeId: pointTypeId, amount: points)
            }

            let caps = try EarningRuleCap.capsForRule(db, ruleId: earning.rule.id)
            for cap in caps where transaction.date >= cap.startDate && transaction.date <= cap.endDate {
                var mutableCap = cap
                mutableCap.currentSpend += transaction.amount
                try mutableCap.update(db)
            }
        }

        let isRefund = transaction.amount < 0
        for offerReward in preview.spendOfferRewards {
            // Always create a record — even for $0 — so reversal is record-driven.
            let reward = TransactionReward(
                transactionId: transaction.id,
                rewardSourceType: "spend_offer",
                rewardSourceId: offerReward.offer.id,
                pointTypeId: offerReward.pointTypeId,
                pointsEarned: offerReward.pointsEarned,
                cashValue: offerReward.cashValue,
                description: offerReward.offer.name
            )
            try reward.insert(db)

            if offerReward.cashValue != 0,
               let pointTypeId = offerReward.pointTypeId,
               let points = offerReward.pointsEarned {
                try updatePointBalance(db, pointTypeId: pointTypeId, amount: points)
            }

            var mutableOffer = offerReward.offer
            mutableOffer.currentSpend += transaction.amount
            mutableOffer.currentCount += isRefund ? -1 : 1
            mutableOffer.currentSpend = max(0, mutableOffer.currentSpend)
            mutableOffer.currentCount = max(0, mutableOffer.currentCount)
            try mutableOffer.update(db)
        }

        for rebateReward in preview.rebateRewards {
            let reward = TransactionReward(
                transactionId: transaction.id,
                rewardSourceType: "rebate",
                rewardSourceId: rebateReward.rebate.id,
                pointTypeId: nil,
                pointsEarned: nil,
                cashValue: rebateReward.cashValue,
                description: "Rebate: \(rebateReward.rebate.vendor)"
            )
            try reward.insert(db)

            var mutableRebate = rebateReward.rebate
            try mutableRebate.decrementUse(db)
        }
    }

    // MARK: - Step 1: Earning Rule Selection

    private func calculateEarningRuleReward(_ db: Database, transaction: Transaction) throws -> EarningRuleReward? {
        let rules = try EarningRule.activeRulesForCard(db, cardId: transaction.cardId)

        // Filter rules that match the transaction
        let matchingRules = rules.filter { rule in
            rule.matches(vendor: transaction.vendor, category: transaction.merchantCategory, onlineTransaction: transaction.onlineTransaction)
        }

        guard !matchingRules.isEmpty else { return nil }

        let isRefund = transaction.amount < 0

        // Calculate cash value for each matching rule, considering caps
        let rulesWithValues = try matchingRules.compactMap { rule -> (EarningRule, Decimal, Decimal, Decimal)? in
            guard let pointType = try PointType.findByID(db, id: rule.pointTypeId) else { return nil }

            // Check if rule has earning caps
            let caps = try EarningRuleCap.capsForRule(db, ruleId: rule.id)

            // Filter caps that are active for this transaction date
            let activeCaps = caps.filter { cap in
                transaction.date >= cap.startDate && transaction.date <= cap.endDate
            }

            // If rule has active caps, check if they're not full (skip cap check for refunds)
            var effectiveAmount = transaction.amount
            if !activeCaps.isEmpty && !isRefund {
                // Find the most restrictive cap (least remaining spend)
                guard let mostRestrictiveCap = activeCaps.min(by: { $0.remainingSpend < $1.remainingSpend }),
                      !mostRestrictiveCap.isFull else {
                    // All caps are full, skip this rule
                    return nil
                }

                // Limit earning to remaining cap amount
                effectiveAmount = min(transaction.amount, mostRestrictiveCap.remainingSpend)
            }

            let pointsEarned = effectiveAmount * rule.pointsPerDollar
            let cashValue = pointsEarned * pointType.cashValuePerPoint

            return (rule, pointsEarned, cashValue, effectiveAmount)
        }

        // Select rule: highest value for purchases, lowest (most negative) for refunds
        guard let best = rulesWithValues.max(by: { $0.2 < $1.2 }) else { return nil }

        return EarningRuleReward(
            rule: best.0,
            pointsEarned: best.1,
            cashValue: best.2,
            pointTypeId: best.0.pointTypeId
        )
    }

    // MARK: - Step 2: Spend Offer Evaluation

    private func calculateSpendOfferRewards(_ db: Database, transaction: Transaction) throws -> [SpendOfferReward] {
        let offers = try SpendOffer.activeOffersForCard(db, cardId: transaction.cardId, date: transaction.date)

        // Filter offers that match the transaction
        let matchingOffers = offers.filter { offer in
            offer.matches(vendor: transaction.vendor, category: transaction.merchantCategory, onlineTransaction: transaction.onlineTransaction)
        }

        return try matchingOffers.compactMap { offer in
            try calculateSpendOfferReward(db, offer: offer, transaction: transaction)
        }
    }

    private func calculateSpendOfferReward(_ db: Database, offer: SpendOffer, transaction: Transaction) throws -> SpendOfferReward? {
        let isRefund = transaction.amount < 0

        switch offer.offerType {
        case .percentageBack:
            guard let percentage = offer.rewardPercentage else { return nil }

            var reward = transaction.amount * (percentage / 100)

            // Apply max cap if present (skip for refunds — always allow reversal)
            if let max = offer.maxRewardAmount, !isRefund {
                let totalEarned = offer.currentSpend * (percentage / 100)
                let remainingCap = max - totalEarned
                if remainingCap <= 0 { return nil }
                reward = min(reward, remainingCap)
            }

            let pointTypeId = offer.pointTypeId
            var pointsEarned: Decimal?
            var cashValue = reward

            if let pointTypeId = pointTypeId,
               let pointType = try PointType.findByID(db, id: pointTypeId) {
                pointsEarned = reward
                cashValue = reward * pointType.cashValuePerPoint
            }

            let progress = offer.maxRewardAmount != nil
                ? "Progress: \(offer.currentSpend + transaction.amount) / \((offer.maxRewardAmount! / percentage) * 100)"
                : "Total spend: \(offer.currentSpend + transaction.amount)"

            return SpendOfferReward(
                offer: offer,
                cashValue: cashValue,
                pointsEarned: pointsEarned,
                pointTypeId: pointTypeId,
                progressUpdate: progress
            )

        case .flatBonusSpendThreshold:
            guard let threshold = offer.spendThreshold,
                  let bonus = offer.flatBonusAmount else { return nil }

            let newSpend = offer.currentSpend + transaction.amount

            // Refunds always track progress (reduce spend)
            if isRefund {
                return SpendOfferReward(
                    offer: offer,
                    cashValue: 0,
                    pointsEarned: nil,
                    pointTypeId: nil,
                    progressUpdate: "Progress: \(max(0, newSpend)) / \(threshold)"
                )
            }

            // Already triggered before — no more progress to track
            guard offer.currentSpend < threshold else { return nil }

            // Threshold just crossed — return actual reward
            if newSpend >= threshold {
                let pointTypeId = offer.pointTypeId
                var pointsEarned: Decimal?
                var cashValue = bonus

                if let pointTypeId = pointTypeId,
                   let pointType = try PointType.findByID(db, id: pointTypeId) {
                    pointsEarned = bonus
                    cashValue = bonus * pointType.cashValuePerPoint
                }

                return SpendOfferReward(
                    offer: offer,
                    cashValue: cashValue,
                    pointsEarned: pointsEarned,
                    pointTypeId: pointTypeId,
                    progressUpdate: "Threshold reached! \(newSpend) / \(threshold)"
                )
            }

            // Not yet met — return $0 reward for progress tracking
            return SpendOfferReward(
                offer: offer,
                cashValue: 0,
                pointsEarned: nil,
                pointTypeId: nil,
                progressUpdate: "Progress: \(newSpend) / \(threshold)"
            )

        case .flatBonusTransactionCount:
            guard let required = offer.countRequired,
                  let bonus = offer.flatBonusAmount else { return nil }

            // Check minimum transaction amount if specified (use abs for refunds)
            if let minAmount = offer.transactionMinAmount,
               abs(transaction.amount) < minAmount {
                return nil
            }

            let countDelta = isRefund ? -1 : 1
            let newCount = offer.currentCount + countDelta

            // Refunds always track progress (reduce count)
            if isRefund {
                return SpendOfferReward(
                    offer: offer,
                    cashValue: 0,
                    pointsEarned: nil,
                    pointTypeId: nil,
                    progressUpdate: "Progress: \(max(0, newCount)) / \(required)"
                )
            }

            // Already triggered before — no more progress to track
            guard offer.currentCount < required else { return nil }

            // Count just reached — return actual reward
            if newCount >= required {
                let pointTypeId = offer.pointTypeId
                var pointsEarned: Decimal?
                var cashValue = bonus

                if let pointTypeId = pointTypeId,
                   let pointType = try PointType.findByID(db, id: pointTypeId) {
                    pointsEarned = bonus
                    cashValue = bonus * pointType.cashValuePerPoint
                }

                return SpendOfferReward(
                    offer: offer,
                    cashValue: cashValue,
                    pointsEarned: pointsEarned,
                    pointTypeId: pointTypeId,
                    progressUpdate: "Count reached! \(newCount) / \(required)"
                )
            }

            // Not yet met — return $0 reward for progress tracking
            return SpendOfferReward(
                offer: offer,
                cashValue: 0,
                pointsEarned: nil,
                pointTypeId: nil,
                progressUpdate: "Progress: \(newCount) / \(required)"
            )
        }
    }

    // MARK: - Step 3: Rebate Evaluation

    private func calculateRebateRewards(_ db: Database, transaction: Transaction) throws -> [RebateReward] {
        let rebates = try Rebate.activeRebatesForCard(
            db,
            cardId: transaction.cardId,
            vendor: transaction.vendor,
            date: transaction.date
        )

        return rebates.compactMap { rebate in
            calculateRebateReward(rebate: rebate, transaction: transaction)
        }
    }

    private func calculateRebateReward(rebate: Rebate, transaction: Transaction) -> RebateReward? {
        var credit: Decimal

        switch rebate.rebateType {
        case .percentage:
            credit = transaction.amount * (rebate.rebateValue / 100)
        case .fixed:
            credit = rebate.rebateValue
        }

        // Apply max cap if present
        if let max = rebate.maxAmount {
            credit = min(credit, max)
        }

        let usesAfter: Int?
        if let remaining = rebate.usesRemaining {
            usesAfter = max(0, remaining - 1)
        } else {
            usesAfter = nil
        }

        return RebateReward(
            rebate: rebate,
            cashValue: credit,
            usesRemainingAfter: usesAfter
        )
    }

    // MARK: - Helper Methods

    private func updatePointBalance(_ db: Database, pointTypeId: UUID, amount: Decimal) throws {
        if var balance = try PointBalance.findByPointType(db, pointTypeId: pointTypeId) {
            try balance.adjustBalance(db, by: amount)
        } else {
            // Create new balance if it doesn't exist
            var newBalance = PointBalance(pointTypeId: pointTypeId, balance: amount)
            try newBalance.insert(db)
        }
    }

    // MARK: - Batch Processing (for YNAB import)

    func calculateBatchRewards(_ transactions: [Transaction]) throws -> [TransactionRewardPreview] {
        return try transactions.map { transaction in
            try calculateTransactionRewards(transaction)
        }
    }

    func saveBatchTransactionsWithRewards(_ previews: [TransactionRewardPreview]) throws {
        for preview in previews {
            try saveTransactionWithRewards(preview.transaction, preview: preview)
        }
    }

    // MARK: - Backfill

    /// Backfills progress and rewards for a newly created spend offer by re-running
    /// syncTransactionRewards on each eligible transaction in the offer's date range.
    func backfillNewOffer(_ offer: SpendOffer) throws {
        let transactions = try db.read { db in
            try Transaction
                .filter(Transaction.Columns.cardId == offer.cardId
                    && Transaction.Columns.date >= offer.startDate
                    && Transaction.Columns.date <= offer.endDate)
                .order(Transaction.Columns.date.asc)
                .fetchAll(db)
        }
        for transaction in transactions {
            guard transaction.isEligibleForRewards else { continue }
            try syncTransactionRewards(transaction)
        }
    }

    // MARK: - Repair

    /// Recalculates all spend offer progress from existing transactions.
    /// Resets currentSpend/currentCount on every offer, then replays all eligible transactions.
    func repairOfferProgress() throws -> (offersUpdated: Int, transactionsScanned: Int) {
        try db.write { db in
            // 1. Reset all offer progress to zero
            let allOffers = try SpendOffer.fetchAll(db)
            for var offer in allOffers {
                offer.currentSpend = 0
                offer.currentCount = 0
                try offer.update(db)
            }

            // 2. Fetch all transactions ordered by date
            let transactions = try Transaction
                .order(Transaction.Columns.date.asc)
                .fetchAll(db)

            var scanned = 0

            // 3. Replay each eligible transaction against offers
            for transaction in transactions {
                guard transaction.isEligibleForRewards else { continue }
                scanned += 1

                let isRefund = transaction.amount < 0

                // Find offers that were active at the time of this transaction
                let activeOffers = try SpendOffer
                    .filter(SpendOffer.Columns.cardId == transaction.cardId
                        && SpendOffer.Columns.startDate <= transaction.date
                        && SpendOffer.Columns.endDate >= transaction.date)
                    .fetchAll(db)

                let matchingOffers = activeOffers.filter {
                    $0.matches(vendor: transaction.vendor, category: transaction.merchantCategory, onlineTransaction: transaction.onlineTransaction)
                }

                for var offer in matchingOffers {
                    // For transaction count offers, check min amount
                    if offer.offerType == .flatBonusTransactionCount,
                       let minAmount = offer.transactionMinAmount,
                       abs(transaction.amount) < minAmount {
                        continue
                    }

                    offer.currentSpend += transaction.amount
                    offer.currentCount += isRefund ? -1 : 1
                    offer.currentSpend = max(0, offer.currentSpend)
                    offer.currentCount = max(0, offer.currentCount)
                    try offer.update(db)
                }
            }

            let updated = try SpendOffer.filter(SpendOffer.Columns.currentSpend > 0 || SpendOffer.Columns.currentCount > 0).fetchCount(db)
            return (updated, scanned)
        }
    }
}
