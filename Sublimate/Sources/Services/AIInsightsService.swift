import Foundation
import GRDB

/// Local insights computed without API calls
struct LocalInsights {
    let missedOptimizations: [MissedOptimization]
    let pacingAlerts: [PacingAlert]
    let expiringOpportunities: [ExpiringOpportunity]
    let spendingPatterns: [SpendingPattern]
    let capWarnings: [CapWarning]
}

struct MissedOptimization {
    let transaction: Transaction
    let usedCard: Card
    let earnedValue: Decimal
    let betterCard: Card
    let potentialValue: Decimal
    let difference: Decimal
}

struct PacingAlert {
    let offer: SpendOffer
    let card: Card
    let progressPercent: Decimal
    let timeElapsedPercent: Decimal
    let isOnTrack: Bool
}

struct ExpiringOpportunity {
    let type: String  // "rebate" or "offer"
    let id: UUID
    let name: String
    let card: Card
    let daysRemaining: Int
    let value: String
}

struct SpendingPattern {
    let category: String
    let totalSpend: Decimal
    let currentAvgRate: Decimal
    let bestAvailableRate: Decimal
    let potentialGain: Decimal
}

struct CapWarning {
    let cap: EarningCap
    let affectedRules: [EarningRule]
    let progressPercentage: Decimal
    let remainingSpend: Decimal
    let daysRemaining: Int
}

/// AI Insights payload for Claude API
struct AIInsightsPayload: Codable {
    let summaryStats: SummaryStats
    let missedOptimizations: [MissedOptSummary]
    let pacingAlerts: [PacingAlertSummary]
    let expiringOpportunities: [ExpiringOppSummary]
    let spendingPatterns: [SpendingPatternSummary]
}

struct SummaryStats: Codable {
    let totalRewardsThisMonth: Decimal
    let totalSpendThisMonth: Decimal
    let effectiveRate: Decimal
}

struct MissedOptSummary: Codable {
    let date: String
    let category: String
    let amount: Decimal
    let missedValue: Decimal
}

struct PacingAlertSummary: Codable {
    let offerName: String
    let progressPercent: Decimal
    let timeElapsedPercent: Decimal
    let needsAttention: Bool
}

struct ExpiringOppSummary: Codable {
    let type: String
    let name: String
    let daysRemaining: Int
    let value: String
}

struct SpendingPatternSummary: Codable {
    let category: String
    let monthlyAverage: Decimal
    let currentRate: Decimal
    let bestRate: Decimal
    let potentialMonthlyGain: Decimal
}

/// Service for generating AI-powered insights
class AIInsightsService {
    private let db: DatabaseQueue
    private let keychain = KeychainService.shared

    init(database: DatabaseQueue) {
        self.db = database
    }

    // MARK: - Local Computations

    func generateMissedOptimizations(days: Int = 30) throws -> [MissedOptimization] {
        return try db.read { db in
            let cutoffDate = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
            let transactions = try Transaction.forDateRange(db, startDate: cutoffDate, endDate: Date())

            var optimizations: [MissedOptimization] = []

            let allCards = try Card.all(db)

            for transaction in transactions where transaction.isEligibleForRewards {
                // Calculate used card's value using same methodology as alternatives
                // (includes earning rules + amortized offer values + rebates)
                let usedCard = try Card.findByID(db, id: transaction.cardId)!
                let earnedValue = try calculatePotentialReward(db, transaction: transaction, cardId: transaction.cardId)

                var bestAlt: (Card, Decimal)?
                for card in allCards where card.id != transaction.cardId {
                    let potentialValue = try calculatePotentialReward(db, transaction: transaction, cardId: card.id)

                    if potentialValue > earnedValue && (bestAlt == nil || potentialValue > bestAlt!.1) {
                        bestAlt = (card, potentialValue)
                    }
                }

                if let (betterCard, potentialValue) = bestAlt {
                    print("⚠️ MISSED OPT: \(transaction.vendor) \(transaction.amount.toCurrency()) — used \(usedCard.name)=\(earnedValue.toCurrency()) vs \(betterCard.name)=\(potentialValue.toCurrency())")
                    optimizations.append(MissedOptimization(
                        transaction: transaction,
                        usedCard: usedCard,
                        earnedValue: earnedValue,
                        betterCard: betterCard,
                        potentialValue: potentialValue,
                        difference: potentialValue - earnedValue
                    ))
                }
            }

            return optimizations.sorted { $0.difference > $1.difference }
        }
    }

    func generatePacingAlerts() throws -> [PacingAlert] {
        return try db.read { db in
            let now = Date()
            let activeOffers = try SpendOffer
                .filter(SpendOffer.Columns.isActive == true
                    && SpendOffer.Columns.startDate <= now
                    && SpendOffer.Columns.endDate >= now)
                .fetchAll(db)

            return try activeOffers.compactMap { offer -> PacingAlert? in
                guard let progressPercent = offer.progressPercentage() else { return nil }

                let card = try Card.findByID(db, id: offer.cardId)!

                let totalDuration = offer.endDate.timeIntervalSince(offer.startDate)
                let elapsed = now.timeIntervalSince(offer.startDate)
                let timeElapsedPercent = (Decimal(elapsed) / Decimal(totalDuration)) * 100

                let isOnTrack = progressPercent >= timeElapsedPercent

                // Only alert if significantly behind
                if !isOnTrack && (timeElapsedPercent - progressPercent) > 10 {
                    return PacingAlert(
                        offer: offer,
                        card: card,
                        progressPercent: progressPercent,
                        timeElapsedPercent: timeElapsedPercent,
                        isOnTrack: false
                    )
                }

                return nil
            }
        }
    }

    func generateExpiringOpportunities(daysThreshold: Int = 14) throws -> [ExpiringOpportunity] {
        return try db.read { db in
            let now = Date()
            let threshold = Calendar.current.date(byAdding: .day, value: daysThreshold, to: now)!

            var opportunities: [ExpiringOpportunity] = []

            // Expiring rebates with uses remaining
            let rebates = try Rebate
                .filter(Rebate.Columns.isActive == true
                    && Rebate.Columns.endDate != nil
                    && Rebate.Columns.endDate <= threshold
                    && Rebate.Columns.endDate > now)
                .filter(Rebate.Columns.usesRemaining == nil || Rebate.Columns.usesRemaining > 0)
                .fetchAll(db)

            for rebate in rebates {
                let card = try Card.findByID(db, id: rebate.cardId)!
                let days = Calendar.current.dateComponents([.day], from: now, to: rebate.endDate!).day ?? 0

                opportunities.append(ExpiringOpportunity(
                    type: "rebate",
                    id: rebate.id,
                    name: rebate.vendor,
                    card: card,
                    daysRemaining: days,
                    value: "\(rebate.rebateValue) \(rebate.rebateType == .percentage ? "%" : "fixed")"
                ))
            }

            // Expiring spend offers
            let offers = try SpendOffer
                .filter(SpendOffer.Columns.isActive == true
                    && SpendOffer.Columns.endDate <= threshold
                    && SpendOffer.Columns.endDate > now)
                .fetchAll(db)

            for offer in offers {
                let card = try Card.findByID(db, id: offer.cardId)!
                let days = Calendar.current.dateComponents([.day], from: now, to: offer.endDate).day ?? 0

                opportunities.append(ExpiringOpportunity(
                    type: "offer",
                    id: offer.id,
                    name: offer.name,
                    card: card,
                    daysRemaining: days,
                    value: offer.name
                ))
            }

            return opportunities.sorted { $0.daysRemaining < $1.daysRemaining }
        }
    }

    func generateSpendingPatterns(months: Int = 3) throws -> [SpendingPattern] {
        return try db.read { db in
            let cutoffDate = Calendar.current.date(byAdding: .month, value: -months, to: Date())!
            let transactions = try Transaction.forDateRange(db, startDate: cutoffDate, endDate: Date())
                .filter { $0.transactionType == .purchase && $0.isEligibleForRewards }

            // Group by category
            var categorySpend: [String: Decimal] = [:]
            var categoryRewards: [String: Decimal] = [:]

            for transaction in transactions {
                let category = transaction.merchantCategory ?? "Uncategorized"
                categorySpend[category, default: 0] += transaction.amount

                let rewards = try TransactionReward.forTransaction(db, transactionId: transaction.id)
                categoryRewards[category, default: 0] += rewards.reduce(0) { $0 + $1.cashValue }
            }

            // Calculate patterns
            return try categorySpend.map { category, spend -> SpendingPattern in
                let rewards = categoryRewards[category] ?? 0
                let currentRate = spend > 0 ? (rewards / spend) * 100 : 0

                // Find best available rate for this category
                let bestRate = try findBestRateForCategory(db, category: category)
                let potentialGain = spend * ((bestRate - currentRate) / 100)

                return SpendingPattern(
                    category: category,
                    totalSpend: spend,
                    currentAvgRate: currentRate,
                    bestAvailableRate: bestRate,
                    potentialGain: potentialGain
                )
            }.filter { $0.potentialGain > 1 }  // Only show meaningful gains
                .sorted { $0.potentialGain > $1.potentialGain }
        }
    }

    func generateCapWarnings(threshold: Decimal = 80) throws -> [CapWarning] {
        return try db.read { db in
            let activeCaps = try EarningCap.activeCaps(db)

            return try activeCaps.compactMap { cap -> CapWarning? in
                // Only warn if at or above threshold percentage
                guard cap.progressPercentage >= threshold else { return nil }

                let affectedRules = try EarningRuleCap.rulesForCap(db, capId: cap.id)
                let daysRemaining = Calendar.current.dateComponents([.day], from: Date(), to: cap.endDate).day ?? 0

                return CapWarning(
                    cap: cap,
                    affectedRules: affectedRules,
                    progressPercentage: cap.progressPercentage,
                    remainingSpend: cap.remainingSpend,
                    daysRemaining: daysRemaining
                )
            }.sorted { $0.progressPercentage > $1.progressPercentage }
        }
    }

    func generateLocalInsights() throws -> LocalInsights {
        return LocalInsights(
            missedOptimizations: try generateMissedOptimizations(),
            pacingAlerts: try generatePacingAlerts(),
            expiringOpportunities: try generateExpiringOpportunities(),
            spendingPatterns: try generateSpendingPatterns(),
            capWarnings: try generateCapWarnings()
        )
    }

    // MARK: - AI Integration (Claude API)

    func generateInsightsBriefing(insights: LocalInsights) async throws -> String {
        guard let apiKey = keychain.getClaudeAPIKey() else {
            throw AIInsightsError.noAPIKey
        }

        let payload = try buildAPIPayload(insights: insights)

        // Call Claude API
        // Note: This is a simplified implementation. In production, use the official Anthropic SDK
        let briefing = try await callClaudeAPI(apiKey: apiKey, payload: payload)

        return briefing
    }

    private func buildAPIPayload(insights: LocalInsights) throws -> AIInsightsPayload {
        return try db.read { db in
            let now = Date()
            let monthStart = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: now))!

            let monthTransactions = try Transaction.forDateRange(db, startDate: monthStart, endDate: now)
                .filter { $0.transactionType == .purchase }

            let totalSpend = monthTransactions.reduce(0) { $0 + $1.amount }
            let totalRewards = try TransactionReward.totalCashValueForDateRange(db, startDate: monthStart, endDate: now)
            let effectiveRate = totalSpend > 0 ? (totalRewards / totalSpend) * 100 : 0

            let stats = SummaryStats(
                totalRewardsThisMonth: totalRewards,
                totalSpendThisMonth: totalSpend,
                effectiveRate: effectiveRate
            )

            let formatter = DateFormatter()
            formatter.dateStyle = .short

            return AIInsightsPayload(
                summaryStats: stats,
                missedOptimizations: insights.missedOptimizations.prefix(5).map {
                    MissedOptSummary(
                        date: formatter.string(from: $0.transaction.date),
                        category: $0.transaction.merchantCategory ?? "General",
                        amount: $0.transaction.amount,
                        missedValue: $0.difference
                    )
                },
                pacingAlerts: insights.pacingAlerts.map {
                    PacingAlertSummary(
                        offerName: $0.offer.name,
                        progressPercent: $0.progressPercent,
                        timeElapsedPercent: $0.timeElapsedPercent,
                        needsAttention: !$0.isOnTrack
                    )
                },
                expiringOpportunities: insights.expiringOpportunities.prefix(5).map {
                    ExpiringOppSummary(
                        type: $0.type,
                        name: $0.name,
                        daysRemaining: $0.daysRemaining,
                        value: $0.value
                    )
                },
                spendingPatterns: insights.spendingPatterns.prefix(5).map {
                    SpendingPatternSummary(
                        category: $0.category,
                        monthlyAverage: $0.totalSpend / 3,
                        currentRate: $0.currentAvgRate,
                        bestRate: $0.bestAvailableRate,
                        potentialMonthlyGain: $0.potentialGain
                    )
                }
            )
        }
    }

    private func callClaudeAPI(apiKey: String, payload: AIInsightsPayload) async throws -> String {
        // This is a placeholder for Claude API integration
        // In production, use the Anthropic SDK

        // TODO: Build prompt from payload and call Claude API
        // Example prompt structure:
        // - Summary: totalRewards, totalSpend, effectiveRate
        // - Missed Optimizations: list with dates and missed values
        // - Pacing Alerts: offers with progress vs time
        // - Expiring Opportunities: rebates/offers expiring soon

        // For now, return a mock response
        return "AI Insights: Based on your spending patterns, consider using your higher rewards card for grocery purchases. You have 3 offers expiring soon - make sure to use them!"
    }

    // MARK: - Helper Methods

    private func calculatePotentialReward(_ db: Database, transaction: Transaction, cardId: UUID) throws -> Decimal {
        var totalValue: Decimal = 0

        // 1. Earning rules
        let rules = try EarningRule.activeRulesForCard(db, cardId: cardId)
        let matchingRules = rules.filter {
            $0.matches(vendor: transaction.vendor, category: transaction.merchantCategory)
        }

        let bestRuleValue = try matchingRules.compactMap { rule -> Decimal? in
            guard let pointType = try PointType.findByID(db, id: rule.pointTypeId) else { return nil }
            let points = transaction.amount * rule.pointsPerDollar
            return points * pointType.cashValuePerPoint
        }.max()

        totalValue += bestRuleValue ?? 0

        // 2. Active spend offers (only those marked for optimization)
        // Use current date to find offers that are active NOW — even if the transaction was in the past,
        // we want to account for currently-active offers when evaluating card choices
        let now = Date()
        let activeOffers = try SpendOffer
            .filter(SpendOffer.Columns.cardId == cardId
                && SpendOffer.Columns.isActive == true
                && SpendOffer.Columns.includeInOptimizations == true
                && SpendOffer.Columns.startDate <= now
                && SpendOffer.Columns.endDate >= now)
            .fetchAll(db)
        let matchingOffers = activeOffers.filter {
            $0.matches(vendor: transaction.vendor, category: transaction.merchantCategory)
        }

        print("🔍 calcPotentialReward card=\(cardId) tx=\(transaction.vendor) amt=\(transaction.amount) cat=\(transaction.merchantCategory ?? "nil")")
        print("   rules=\(matchingRules.count) bestRuleValue=\(bestRuleValue ?? 0)")
        print("   activeOffers=\(activeOffers.count) matchingOffers=\(matchingOffers.count)")

        for offer in matchingOffers {
            var offerContribution: Decimal = 0
            switch offer.offerType {
            case .percentageBack:
                if let pct = offer.rewardPercentage {
                    let offerValue = transaction.amount * pct / 100
                    if let maxReward = offer.maxRewardAmount {
                        offerContribution = min(offerValue, maxReward)
                    } else {
                        offerContribution = offerValue
                    }
                }
            case .flatBonusSpendThreshold:
                if let bonus = offer.flatBonusAmount, let threshold = offer.spendThreshold, threshold > 0 {
                    let effectiveRate = bonus / threshold
                    offerContribution = transaction.amount * effectiveRate
                }
            case .flatBonusTransactionCount:
                if let bonus = offer.flatBonusAmount, let count = offer.countRequired, count > 0 {
                    offerContribution = bonus / Decimal(count)
                }
            }
            print("   offer '\(offer.name)' type=\(offer.offerType) contributes=\(offerContribution)")
            totalValue += offerContribution
        }

        // 3. Rebates
        let rebates = try Rebate.fetchAll(db).filter {
            $0.cardId == cardId &&
            $0.isActive &&
            ($0.usesRemaining == nil || $0.usesRemaining! > 0) &&
            $0.vendor.lowercased() == transaction.vendor.lowercased()
        }

        for rebate in rebates {
            switch rebate.rebateType {
            case .fixed:
                totalValue += rebate.rebateValue
            case .percentage:
                let rebateValue = transaction.amount * rebate.rebateValue / 100
                if let max = rebate.maxAmount {
                    totalValue += min(rebateValue, max)
                } else {
                    totalValue += rebateValue
                }
            }
        }

        print("   TOTAL for card \(cardId): \(totalValue)")
        return totalValue
    }

    private func findBestRateForCategory(_ db: Database, category: String) throws -> Decimal {
        let allRules = try EarningRule
            .filter(EarningRule.Columns.isActive == true)
            .fetchAll(db)

        let matchingRules = allRules.filter {
            $0.matches(vendor: nil, category: category)
        }

        let rates = try matchingRules.compactMap { rule -> Decimal? in
            guard let pointType = try PointType.findByID(db, id: rule.pointTypeId) else { return nil }
            return rule.pointsPerDollar * pointType.cashValuePerPoint * 100
        }

        return rates.max() ?? 0
    }
}

// MARK: - Errors

enum AIInsightsError: LocalizedError {
    case noAPIKey
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "No Claude API key configured."
        case .apiError(let message):
            return "AI Insights error: \(message)"
        }
    }
}
