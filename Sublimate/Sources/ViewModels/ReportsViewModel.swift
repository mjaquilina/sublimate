import Foundation
import SwiftUI
import GRDB
import AppKit
import Combine
import UniformTypeIdentifiers

struct CardPerformanceData: Identifiable {
    let id: UUID
    let cardName: String
    let eligibleSpend: Decimal
    let pointsValue: Decimal
    let spendOfferValue: Decimal
    let rebateValue: Decimal

    var totalRewards: Decimal {
        pointsValue + spendOfferValue + rebateValue
    }

    var effectiveRate: Decimal {
        eligibleSpend > 0 ? (totalRewards / eligibleSpend) * 100 : 0
    }
}

struct CategoryPerformanceData: Identifiable {
    let id = UUID()
    let categoryName: String
    let totalSpend: Decimal
    let totalRewards: Decimal
    let bestCard: String?

    var effectiveRate: Decimal {
        totalSpend > 0 ? (totalRewards / totalSpend) * 100 : 0
    }
}

struct RewardsBreakdownData {
    let pointsValue: Decimal
    let spendOfferValue: Decimal
    let rebateValue: Decimal
    let pointsByType: [String: Decimal]

    var totalRewards: Decimal {
        pointsValue + spendOfferValue + rebateValue
    }
}

@MainActor
class ReportsViewModel: ObservableObject {
    @Published var cardPerformance: [CardPerformanceData] = []
    @Published var categoryPerformance: [CategoryPerformanceData] = []
    @Published var rewardsBreakdown: RewardsBreakdownData?

    func loadReports(for dateRange: (Date, Date)) {
        Task {
            do {
                let db = try DatabaseManager.shared.database()
                let (startDate, endDate) = dateRange

                // Load card performance
                cardPerformance = try await loadCardPerformance(db, startDate: startDate, endDate: endDate)

                // Load category performance
                categoryPerformance = try await loadCategoryPerformance(db, startDate: startDate, endDate: endDate)

                // Load rewards breakdown
                rewardsBreakdown = try await loadRewardsBreakdown(db, startDate: startDate, endDate: endDate)
            } catch {
                print("Error loading reports: \(error)")
            }
        }
    }

    private func loadCardPerformance(_ db: DatabaseQueue, startDate: Date, endDate: Date) async throws -> [CardPerformanceData] {
        return try await db.read { db in
            let cards = try Card.fetchAll(db)
            var performance: [CardPerformanceData] = []

            for card in cards {
                // Get eligible spend
                let transactions = try Transaction
                    .filter(Transaction.Columns.cardId == card.id
                        && Transaction.Columns.date >= startDate
                        && Transaction.Columns.date <= endDate
                        && Transaction.Columns.transactionType == TransactionType.purchase.rawValue)
                    .fetchAll(db)

                let eligibleSpend = transactions.reduce(0) { $0 + $1.amount }

                // Get transaction IDs for this card in range
                let transactionIds = transactions.map { $0.id }

                guard !transactionIds.isEmpty else {
                    // Include card with zero values if it has no transactions
                    performance.append(CardPerformanceData(
                        id: card.id,
                        cardName: card.name,
                        eligibleSpend: 0,
                        pointsValue: 0,
                        spendOfferValue: 0,
                        rebateValue: 0
                    ))
                    continue
                }

                // Get rewards for these transactions
                let rewards = try TransactionReward
                    .filter(transactionIds.contains(TransactionReward.Columns.transactionId))
                    .fetchAll(db)

                let pointsValue = rewards
                    .filter { $0.rewardSourceType == "earning_rule" }
                    .reduce(0) { $0 + $1.cashValue }

                let spendOfferValue = rewards
                    .filter { $0.rewardSourceType == "spend_offer" }
                    .reduce(0) { $0 + $1.cashValue }

                let rebateValue = rewards
                    .filter { $0.rewardSourceType == "rebate" }
                    .reduce(0) { $0 + $1.cashValue }

                performance.append(CardPerformanceData(
                    id: card.id,
                    cardName: card.name,
                    eligibleSpend: eligibleSpend,
                    pointsValue: pointsValue,
                    spendOfferValue: spendOfferValue,
                    rebateValue: rebateValue
                ))
            }

            return performance.sorted { $0.effectiveRate > $1.effectiveRate }
        }
    }

    private func loadCategoryPerformance(_ db: DatabaseQueue, startDate: Date, endDate: Date) async throws -> [CategoryPerformanceData] {
        return try await db.read { db in
            let transactions = try Transaction
                .filter(Transaction.Columns.date >= startDate
                    && Transaction.Columns.date <= endDate
                    && Transaction.Columns.transactionType == TransactionType.purchase.rawValue)
                .fetchAll(db)

            let transactionIds = transactions.map { $0.id }
            let allRewards = try TransactionReward
                .filter(transactionIds.contains(TransactionReward.Columns.transactionId))
                .fetchAll(db)

            let cards = try Card.fetchAll(db)
            let cardMap = Dictionary(uniqueKeysWithValues: cards.map { ($0.id, $0.name) })

            // Group by category
            var categoryData: [String: (spend: Decimal, rewards: Decimal, cardRewards: [UUID: Decimal])] = [:]

            for transaction in transactions {
                let category = transaction.merchantCategory ?? "Uncategorized"

                let transactionRewards = allRewards
                    .filter { $0.transactionId == transaction.id }
                    .reduce(0) { $0 + $1.cashValue }

                let existing = categoryData[category] ?? (0, 0, [:])
                categoryData[category] = (
                    existing.spend + transaction.amount,
                    existing.rewards + transactionRewards,
                    existing.cardRewards.merging([transaction.cardId: transactionRewards]) { $0 + $1 }
                )
            }

            return categoryData.map { category, data in
                let bestCardId = data.cardRewards.max(by: { $0.value < $1.value })?.key
                let bestCard = bestCardId.flatMap { cardMap[$0] }

                return CategoryPerformanceData(
                    categoryName: category,
                    totalSpend: data.spend,
                    totalRewards: data.rewards,
                    bestCard: bestCard
                )
            }.sorted { $0.effectiveRate > $1.effectiveRate }
        }
    }

    private func loadRewardsBreakdown(_ db: DatabaseQueue, startDate: Date, endDate: Date) async throws -> RewardsBreakdownData {
        return try await db.read { db in
            let transactions = try Transaction
                .filter(Transaction.Columns.date >= startDate && Transaction.Columns.date <= endDate)
                .fetchAll(db)

            let transactionIds = transactions.map { $0.id }
            let rewards = try TransactionReward
                .filter(transactionIds.contains(TransactionReward.Columns.transactionId))
                .fetchAll(db)

            let pointsValue = rewards
                .filter { $0.rewardSourceType == "earning_rule" }
                .reduce(0) { $0 + $1.cashValue }

            let spendOfferValue = rewards
                .filter { $0.rewardSourceType == "spend_offer" }
                .reduce(0) { $0 + $1.cashValue }

            let rebateValue = rewards
                .filter { $0.rewardSourceType == "rebate" }
                .reduce(0) { $0 + $1.cashValue }

            // Group points by type
            let pointTypes = try PointType.fetchAll(db)
            let pointTypeMap = Dictionary(uniqueKeysWithValues: pointTypes.map { ($0.id, $0.name) })

            var pointsByType: [String: Decimal] = [:]
            for reward in rewards where reward.pointTypeId != nil {
                if let pointTypeId = reward.pointTypeId,
                   let typeName = pointTypeMap[pointTypeId],
                   let points = reward.pointsEarned {
                    pointsByType[typeName, default: 0] += points
                }
            }

            return RewardsBreakdownData(
                pointsValue: pointsValue,
                spendOfferValue: spendOfferValue,
                rebateValue: rebateValue,
                pointsByType: pointsByType
            )
        }
    }

    func exportToCSV() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "sublimate-report-\(Date().toShortString()).csv"
        panel.allowedContentTypes = [.commaSeparatedText]

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }

            Task {
                await self.generateCSV(url: url)
            }
        }
    }

    private func generateCSV(url: URL) async {
        var csv = "Card Performance Report\n\n"
        csv += "Card,Eligible Spend,Points Value,Spend Offers,Rebates,Total Rewards,Effective Rate\n"

        for item in cardPerformance {
            csv += "\(item.cardName),\(item.eligibleSpend),\(item.pointsValue),\(item.spendOfferValue),\(item.rebateValue),\(item.totalRewards),\(item.effectiveRate)%\n"
        }

        csv += "\n\nCategory Performance Report\n\n"
        csv += "Category,Total Spend,Total Rewards,Effective Rate,Best Card\n"

        for item in categoryPerformance {
            csv += "\(item.categoryName),\(item.totalSpend),\(item.totalRewards),\(item.effectiveRate)%,\(item.bestCard ?? "")\n"
        }

        do {
            try csv.write(to: url, atomically: true, encoding: .utf8)
            print("Exported to \(url.path)")
        } catch {
            print("Error exporting CSV: \(error)")
        }
    }
}
