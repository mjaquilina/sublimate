import Foundation
import SwiftUI
import GRDB
import Combine

struct CardRecommendation {
    let card: Card
    let rank: Int
    let effectiveRate: Decimal
    let earningRuleName: String?
    let activeOffers: [String]
    let availableRebates: [String]
}

@MainActor
class DashboardViewModel: ObservableObject {
    @Published var activeOffers: [SpendOffer] = []
    @Published var activeRebates: [Rebate] = []
    @Published var totalRewardsThisMonth: Decimal = 0
    @Published var totalSpendThisMonth: Decimal = 0
    @Published var effectiveRate: Decimal = 0
    @Published var totalRewardsLastMonth: Decimal = 0
    @Published var totalSpendLastMonth: Decimal = 0
    @Published var effectiveRateLastMonth: Decimal = 0
    @Published var recommendations: [CardRecommendation] = []
    @Published var hasSearched: Bool = false
    @Published var insights: LocalInsights?

    private var cards: [Card] = []

    func cardForId(_ id: UUID) -> Card? {
        return cards.first(where: { $0.id == id })
    }

    func loadData() {
        Task {
            do {
                let db = try DatabaseManager.shared.database()

                // Load active offers
                activeOffers = try await db.read { db in
                    let now = Date()
                    return try SpendOffer
                        .filter(SpendOffer.Columns.isActive == true
                            && SpendOffer.Columns.startDate <= now
                            && SpendOffer.Columns.endDate >= now)
                        .order(SpendOffer.Columns.endDate.asc)
                        .fetchAll(db)
                }

                // Load active rebates
                activeRebates = try await db.read { db in
                    let now = Date()
                    return try Rebate
                        .filter(Rebate.Columns.isActive == true)
                        .filter(Rebate.Columns.usesRemaining == nil || Rebate.Columns.usesRemaining > 0)
                        .filter(Rebate.Columns.startDate == nil || Rebate.Columns.startDate <= now)
                        .filter(Rebate.Columns.endDate == nil || Rebate.Columns.endDate >= now)
                        .order(Rebate.Columns.endDate.asc)
                        .fetchAll(db)
                }

                // Load cards for lookup
                let allCards = try await db.read { db in
                    try Card.all(db)
                }
                cards = allCards

                // Calculate this month's stats
                let (rewards, spend, rate) = try await calculateMonthStats(db, monthOffset: 0)
                totalRewardsThisMonth = rewards
                totalSpendThisMonth = spend
                effectiveRate = rate

                // Calculate last month's stats
                let (lastRewards, lastSpend, lastRate) = try await calculateMonthStats(db, monthOffset: -1)
                totalRewardsLastMonth = lastRewards
                totalSpendLastMonth = lastSpend
                effectiveRateLastMonth = lastRate

                print("📊 Dashboard Stats - This Month: \(rewards), Last Month: \(lastRewards)")

                // Generate insights
                let service = AIInsightsService(database: db)
                insights = try service.generateLocalInsights()

            } catch {
                print("Error loading dashboard data: \(error)")
            }
        }
    }

    func cardForOffer(_ offer: SpendOffer) -> Card? {
        return cards.first(where: { $0.id == offer.cardId })
    }

    func cardForRebate(_ rebate: Rebate) -> Card? {
        return cards.first(where: { $0.id == rebate.cardId })
    }

    func searchRecommendations(query: String) {
        hasSearched = true
        guard !query.isEmpty else {
            recommendations = []
            return
        }

        Task {
            do {
                let db = try DatabaseManager.shared.database()
                recommendations = try await generateRecommendations(db, query: query)
            } catch {
                print("Error generating recommendations: \(error)")
            }
        }
    }

    private func calculateMonthStats(_ db: DatabaseQueue, monthOffset: Int = 0) async throws -> (Decimal, Decimal, Decimal) {
        return try await db.read { db in
            let targetDate = Calendar.current.date(byAdding: .month, value: monthOffset, to: Date())!
            let monthStart = targetDate.startOfMonth()
            let monthEnd = targetDate.endOfMonth()

            print("📅 Calculating stats for: \(monthStart.toShortString()) to \(monthEnd.toShortString())")

            let allTransactions = try Transaction.forDateRange(db, startDate: monthStart, endDate: monthEnd)
            print("📊 Found \(allTransactions.count) transactions in date range")

            let transactions = allTransactions.filter { $0.transactionType == .purchase }
            print("📊 Filtered to \(transactions.count) purchase transactions")

            let totalSpend = transactions.reduce(0) { $0 + $1.amount }
            print("💰 Total spend: \(totalSpend)")

            let totalRewards = try TransactionReward.totalCashValueForDateRange(db, startDate: monthStart, endDate: monthEnd)
            print("🎁 Total rewards: \(totalRewards)")

            let rate = totalSpend > 0 ? (totalRewards / totalSpend) * 100 : 0

            return (totalRewards, totalSpend, rate)
        }
    }

    private func generateRecommendations(_ db: DatabaseQueue, query: String) async throws -> [CardRecommendation] {
        return try await db.read { db in
            let allCards = try Card.all(db)
            let now = Date()

            var recs: [(Card, Decimal)] = []

            for card in allCards {
                var effectiveRate: Decimal = 0

                // Check earning rules
                let rules = try EarningRule.activeRulesForCard(db, cardId: card.id)
                let matchingRules = rules.filter {
                    $0.matches(vendor: query, category: query)
                }

                var earningRuleName: String?
                if let bestRule = matchingRules.max(by: { r1, r2 in
                    guard let pt1 = try? PointType.findByID(db, id: r1.pointTypeId),
                          let pt2 = try? PointType.findByID(db, id: r2.pointTypeId) else {
                        return false
                    }
                    let v1 = r1.pointsPerDollar * pt1.cashValuePerPoint
                    let v2 = r2.pointsPerDollar * pt2.cashValuePerPoint
                    return v1 < v2
                }) {
                    if let pointType = try PointType.findByID(db, id: bestRule.pointTypeId) {
                        effectiveRate += bestRule.pointsPerDollar * pointType.cashValuePerPoint * 100
                        earningRuleName = bestRule.name
                    }
                }

                // Check active spend offers
                let offers = try SpendOffer.activeOffersForCard(db, cardId: card.id, date: now)
                let matchingOffers = offers.filter {
                    $0.matches(vendor: query, category: query)
                }

                // Check active rebates
                let rebates = try Rebate
                    .filter(Rebate.Columns.cardId == card.id && Rebate.Columns.isActive == true)
                    .filter(sql: "LOWER(\(Rebate.Columns.vendor)) LIKE ?", arguments: ["%\(query.lowercased())%"])
                    .fetchAll(db)

                let activeRebateNames = rebates.map { $0.vendor }

                if effectiveRate > 0 || !matchingOffers.isEmpty || !rebates.isEmpty {
                    recs.append((card, effectiveRate))
                }
            }

            // Sort by effective rate
            recs.sort { $0.1 > $1.1 }

            return recs.enumerated().map { index, item in
                let card = item.0
                let rate = item.1

                // Get details for this card
                let rules = (try? EarningRule.activeRulesForCard(db, cardId: card.id).filter {
                    $0.matches(vendor: query, category: query)
                }) ?? []
                let offers = (try? SpendOffer.activeOffersForCard(db, cardId: card.id, date: now).filter {
                    $0.matches(vendor: query, category: query)
                }) ?? []
                let rebates = (try? Rebate
                    .filter(Rebate.Columns.cardId == card.id && Rebate.Columns.isActive == true)
                    .filter(sql: "LOWER(\(Rebate.Columns.vendor)) LIKE ?", arguments: ["%\(query.lowercased())%"])
                    .fetchAll(db)) ?? []

                return CardRecommendation(
                    card: card,
                    rank: index,
                    effectiveRate: rate,
                    earningRuleName: rules.first?.name,
                    activeOffers: offers.map { $0.name },
                    availableRebates: rebates.map { $0.vendor }
                )
            }
        }
    }
}
