import Foundation
import SwiftUI
import GRDB
import Combine

struct CreditLinkSourceInfo: Identifiable {
    let id: UUID
    let type: String  // "spend_offer", "rebate", "point_redemption"
    let name: String
    let amount: Decimal?
}

@MainActor
class TransactionsViewModel: ObservableObject {
    @Published var transactions: [Transaction] = []
    @Published var creditLinks: [UUID: StatementCreditLink] = [:]  // transactionId -> link
    @Published var rewardsByTransaction: [UUID: Decimal] = [:]  // transactionId -> total cashValue

    // Filter options
    @Published var cards: [Card] = []
    @Published var cardMap: [UUID: String] = [:]  // cardId -> card name
    @Published var vendorNames: [String] = []
    @Published var categoryNames: [String] = []

    // Active filters
    @Published var filterCardId: UUID?
    @Published var filterVendor: String?
    @Published var filterCategory: String?
    @Published var filterType: TransactionType?

    var filteredTransactions: [Transaction] {
        transactions.filter { tx in
            if let cardId = filterCardId, tx.cardId != cardId { return false }
            if let vendor = filterVendor, tx.vendor != vendor { return false }
            if let category = filterCategory {
                guard tx.merchantCategory == category else { return false }
            }
            if let type = filterType, tx.transactionType != type { return false }
            return true
        }
    }

    var hasActiveFilters: Bool {
        filterCardId != nil || filterVendor != nil || filterCategory != nil || filterType != nil
    }

    func clearFilters() {
        filterCardId = nil
        filterVendor = nil
        filterCategory = nil
        filterType = nil
    }

    func rewardPercentage(for tx: Transaction) -> String {
        guard tx.isEligibleForRewards,
              tx.amount != 0,
              let totalReward = rewardsByTransaction[tx.id],
              totalReward != 0 else {
            return "—"
        }
        let pct = (totalReward.absolute / tx.amount.absolute) * 100
        print("💰 % Earned: \(tx.vendor) — reward=\(totalReward) amount=\(tx.amount) pct=\(pct)")
        return pct.toPercentage()
    }

    func loadTransactions() {
        Task {
            do {
                let db = try DatabaseManager.shared.database()
                transactions = try await db.read { db in
                    try Transaction
                        .order(Transaction.Columns.date.desc)
                        .fetchAll(db)
                }

                // Load filter options
                cards = try await db.read { try Card.fetchAll($0) }
                cardMap = Dictionary(uniqueKeysWithValues: cards.map { ($0.id, $0.name) })
                vendorNames = Array(Set(transactions.compactMap { $0.vendor.isEmpty ? nil : $0.vendor })).sorted()
                categoryNames = Array(Set(transactions.compactMap { $0.merchantCategory })).sorted()

                // Load reward totals per transaction
                let allRewards = try await db.read { try TransactionReward.fetchAll($0) }
                var rewardsMap: [UUID: Decimal] = [:]
                for reward in allRewards {
                    rewardsMap[reward.transactionId, default: 0] += reward.cashValue
                }
                rewardsByTransaction = rewardsMap

                // Load existing credit links for statement credits
                let creditIds = transactions
                    .filter { $0.transactionType == .statementCredit }
                    .map { $0.id }
                if !creditIds.isEmpty {
                    let links = try await db.read { db in
                        try StatementCreditLink
                            .filter(creditIds.contains(StatementCreditLink.Columns.transactionId))
                            .fetchAll(db)
                    }
                    creditLinks = Dictionary(uniqueKeysWithValues: links.map { ($0.transactionId, $0) })
                }
            } catch {
                print("Error loading transactions: \(error)")
            }
        }
    }

    func loadAvailableSources(for transaction: Transaction) async -> [CreditLinkSourceInfo] {
        do {
            let db = try DatabaseManager.shared.database()
            return try await db.read { db in
                var sources: [CreditLinkSourceInfo] = []

                // All spend offers for this card (credits can post well after an offer ends)
                let offers = try SpendOffer.fetchAll(db).filter {
                    $0.cardId == transaction.cardId
                }
                for offer in offers {
                    sources.append(CreditLinkSourceInfo(
                        id: offer.id, type: "spend_offer", name: offer.name,
                        amount: offer.flatBonusAmount ?? offer.maxRewardAmount
                    ))
                }

                // All rebates for this card
                let rebates = try Rebate.fetchAll(db).filter {
                    $0.cardId == transaction.cardId
                }
                for rebate in rebates {
                    sources.append(CreditLinkSourceInfo(
                        id: rebate.id, type: "rebate", name: rebate.vendor,
                        amount: rebate.rebateType == .fixed ? rebate.rebateValue : nil
                    ))
                }

                // Point redemptions within 90 days
                let redemptions = try PointRedemption.fetchAll(db).filter {
                    $0.redemptionType == .statementCredit &&
                    abs($0.date.timeIntervalSince(transaction.date)) < 90 * 24 * 3600
                }
                for redemption in redemptions {
                    if let pointType = try PointType.findByID(db, id: redemption.pointTypeId) {
                        sources.append(CreditLinkSourceInfo(
                            id: redemption.id, type: "point_redemption",
                            name: "\(pointType.name) redemption", amount: redemption.cashValue
                        ))
                    }
                }

                return sources
            }
        } catch {
            print("Error loading sources: \(error)")
            return []
        }
    }

    func linkCredit(transactionId: UUID, sourceId: UUID?, sourceType: String?) {
        Task {
            do {
                try DatabaseManager.shared.write { db in
                    try StatementCreditLink
                        .filter(StatementCreditLink.Columns.transactionId == transactionId)
                        .deleteAll(db)

                    if let sourceId, let sourceType {
                        let link = StatementCreditLink(
                            transactionId: transactionId,
                            sourceType: sourceType,
                            sourceId: sourceId
                        )
                        try link.insert(db)
                        // Update local state on main actor
                        Task { @MainActor in
                            self.creditLinks[transactionId] = link
                        }
                    } else {
                        Task { @MainActor in
                            self.creditLinks.removeValue(forKey: transactionId)
                        }
                    }
                }
            } catch {
                print("Error linking credit: \(error)")
            }
        }
    }

    func addTransaction(_ transaction: Transaction) {
        // Just reload the list - the form has already saved the transaction
        loadTransactions()
    }

    func updateTransaction(_ transaction: Transaction) {
        Task {
            do {
                // Find the old transaction
                let db = try DatabaseManager.shared.database()
                guard let oldTransaction = try await db.read({ db in
                    try Transaction.filter(Transaction.Columns.id == transaction.id).fetchOne(db)
                }) else {
                    print("Error: Original transaction not found")
                    return
                }

                var updatedTransaction = transaction
                updatedTransaction.updatedAt = Date()

                // Use the engine to update with cache reversal
                let engine = RewardCalculationEngine(database: db)
                try engine.updateTransactionWithRewards(oldTransaction, newTransaction: updatedTransaction)

                loadTransactions()
            } catch {
                print("Error updating transaction: \(error)")
            }
        }
    }

    func deleteTransaction(_ transaction: Transaction) {
        Task {
            do {
                let db = try DatabaseManager.shared.database()
                let engine = RewardCalculationEngine(database: db)

                // Use the engine to delete with cache reversal
                try engine.deleteTransactionWithRewards(transaction)

                transactions.removeAll { $0.id == transaction.id }
            } catch {
                print("Error deleting transaction: \(error)")
            }
        }
    }

    /// Unlink a specific reward from a transaction (e.g., remove a rebate, earning rule, or spend offer reward)
    func unlinkReward(_ reward: TransactionReward, from transaction: Transaction) async throws {
        let db = try DatabaseManager.shared.database()

        try await db.write { db in
            // Reverse the specific reward's effects
            switch reward.rewardSourceType {
            case "earning_rule":
                // Reverse earning rule: subtract from cap spend and point balance
                let caps = try EarningRuleCap.capsForRule(db, ruleId: reward.rewardSourceId)
                for cap in caps where transaction.date >= cap.startDate && transaction.date <= cap.endDate {
                    var mutableCap = cap
                    mutableCap.currentSpend -= transaction.amount
                    mutableCap.currentSpend = max(0, mutableCap.currentSpend)
                    try mutableCap.update(db)
                }

                // Reverse point balance
                if let pointTypeId = reward.pointTypeId, let points = reward.pointsEarned {
                    if var balance = try PointBalance.findByPointType(db, pointTypeId: pointTypeId) {
                        try balance.adjustBalance(db, by: -points)
                    }
                }

            case "spend_offer":
                // Spend offer progress tracking remains (currentSpend/currentCount)
                // Only reverse point balance if applicable
                if let pointTypeId = reward.pointTypeId, let points = reward.pointsEarned {
                    if var balance = try PointBalance.findByPointType(db, pointTypeId: pointTypeId) {
                        try balance.adjustBalance(db, by: -points)
                    }
                }

            case "rebate":
                // Restore rebate uses
                if var rebate = try Rebate.filter(Rebate.Columns.id == reward.rewardSourceId).fetchOne(db) {
                    if let maxUses = rebate.maxUses {
                        rebate.usesRemaining = min((rebate.usesRemaining ?? 0) + 1, maxUses)
                        try rebate.update(db)
                    }
                }

            default:
                break
            }

            // Delete the reward record
            try reward.delete(db)
        }
    }
}
