import Foundation
import SwiftUI
import GRDB
import Combine

/// Enriched balance data with card and point type names
struct BalanceDetail: Identifiable {
    let id: UUID
    let cardName: String
    let pointTypeName: String
    let balance: Decimal
    let cashValuePerPoint: Decimal
    let pointTypeId: UUID

    var cashValue: Decimal {
        balance * cashValuePerPoint
    }
}

/// A unified history entry for the points ledger
struct HistoryEntry: Identifiable {
    let id: UUID
    let date: Date
    let description: String
    let points: Decimal // positive = earned/added, negative = redeemed/removed
    let pointTypeId: UUID
    let entryType: HistoryEntryType
    var runningBalance: Decimal = 0

    enum HistoryEntryType {
        case earned
        case redeemed
        case adjustment
    }
}

/// Display info for point types in pickers
struct PointTypeDisplay: Identifiable, Hashable {
    let id: UUID
    let name: String
    let cardName: String

    var displayName: String {
        "\(name) (\(cardName))"
    }
}

@MainActor
class PointsViewModel: ObservableObject {
    @Published var balanceDetails: [BalanceDetail] = []
    @Published var redemptions: [PointRedemption] = []
    @Published var historyEntries: [HistoryEntry] = []
    @Published var pointTypeDisplays: [PointTypeDisplay] = []
    private var pointTypes: [PointType] = []
    private var cards: [Card] = []

    func loadData() {
        Task {
            do {
                let db = try DatabaseManager.shared.database()

                // Load all necessary data
                let balances = try await db.read { try PointBalance.fetchAll($0) }
                pointTypes = try await db.read { try PointType.fetchAll($0) }
                cards = try await db.read { try Card.fetchAll($0) }

                // Build enriched balance details
                balanceDetails = balances.compactMap { balance in
                    guard let pointType = pointTypes.first(where: { $0.id == balance.pointTypeId }),
                          let card = cards.first(where: { $0.id == pointType.cardId }) else {
                        return nil
                    }

                    return BalanceDetail(
                        id: balance.id,
                        cardName: card.name,
                        pointTypeName: pointType.name,
                        balance: balance.balance,
                        cashValuePerPoint: pointType.cashValuePerPoint,
                        pointTypeId: pointType.id
                    )
                }

                // Build point type displays for pickers
                pointTypeDisplays = pointTypes.compactMap { pt in
                    guard let card = cards.first(where: { $0.id == pt.cardId }) else { return nil }
                    return PointTypeDisplay(id: pt.id, name: pt.name, cardName: card.name)
                }

                redemptions = try await db.read { db in
                    try PointRedemption
                        .order(PointRedemption.Columns.date.desc)
                        .fetchAll(db)
                }

                try await loadHistory()
            } catch {
                print("Error loading points data: \(error)")
            }
        }
    }

    func getPointTypeName(for id: UUID) -> String {
        pointTypes.first(where: { $0.id == id })?.name ?? "Unknown"
    }

    func getCardName(for pointTypeId: UUID) -> String {
        guard let pt = pointTypes.first(where: { $0.id == pointTypeId }),
              let card = cards.first(where: { $0.id == pt.cardId }) else {
            return "Unknown"
        }
        return card.name
    }

    // MARK: - Redemption CRUD

    func addRedemption(_ redemption: PointRedemption) {
        Task {
            do {
                let db = try DatabaseManager.shared.database()
                try await db.write { db in
                    try redemption.insert(db)
                    if var balance = try PointBalance.findByPointType(db, pointTypeId: redemption.pointTypeId) {
                        try balance.adjustBalance(db, by: -redemption.pointsRedeemed)
                    }
                }
                loadData()
            } catch {
                print("Error adding redemption: \(error)")
            }
        }
    }

    func deleteRedemption(_ redemption: PointRedemption) {
        Task {
            do {
                let db = try DatabaseManager.shared.database()
                try await db.write { db in
                    _ = try redemption.delete(db)
                    if var balance = try PointBalance.findByPointType(db, pointTypeId: redemption.pointTypeId) {
                        try balance.adjustBalance(db, by: redemption.pointsRedeemed)
                    }
                }
                loadData()
            } catch {
                print("Error deleting redemption: \(error)")
            }
        }
    }

    // MARK: - Balance Adjustment

    func adjustBalance(pointTypeId: UUID, newBalance: Decimal) {
        Task {
            do {
                let db = try DatabaseManager.shared.database()
                try await db.write { db in
                    guard var balance = try PointBalance.findByPointType(db, pointTypeId: pointTypeId) else { return }
                    let difference = newBalance - balance.balance

                    // Insert audit trail as a PointRedemption with type .other
                    // Store the difference directly in pointsRedeemed (can be positive or negative)
                    let adjustment = PointRedemption(
                        pointTypeId: pointTypeId,
                        date: Date(),
                        pointsRedeemed: difference,
                        redemptionType: .other,
                        description: "Manual balance adjustment"
                    )
                    try adjustment.insert(db)

                    try balance.adjustBalance(db, by: difference)
                }
                loadData()
            } catch {
                print("Error adjusting balance: \(error)")
            }
        }
    }

    // MARK: - History

    private func loadHistory() async throws {
        let db = try DatabaseManager.shared.database()

        // Load point-based earnings from TransactionRewards
        let rewards = try await db.read { db in
            try TransactionReward
                .filter(TransactionReward.Columns.pointTypeId != nil)
                .filter(TransactionReward.Columns.pointsEarned != nil)
                .fetchAll(db)
        }

        // Load transactions for their dates
        let transactions = try await db.read { db in
            try Transaction.fetchAll(db)
        }
        let transactionMap = Dictionary(uniqueKeysWithValues: transactions.map { ($0.id, $0) })

        // Load all redemptions
        let allRedemptions = try await db.read { db in
            try PointRedemption
                .order(PointRedemption.Columns.date.asc)
                .fetchAll(db)
        }

        // Build unified entries
        var entries: [HistoryEntry] = []

        for reward in rewards {
            guard let ptId = reward.pointTypeId, let pts = reward.pointsEarned else { continue }
            let txDate = transactionMap[reward.transactionId]?.date ?? reward.createdAt
            entries.append(HistoryEntry(
                id: reward.id,
                date: txDate,
                description: reward.description,
                points: pts,
                pointTypeId: ptId,
                entryType: .earned
            ))
        }

        for redemption in allRedemptions {
            let isAdjustment = redemption.redemptionType == .other
                && redemption.description == "Manual balance adjustment"

            if isAdjustment {
                // Adjustment: pointsRedeemed stores the raw difference (can be +/-)
                entries.append(HistoryEntry(
                    id: redemption.id,
                    date: redemption.date,
                    description: redemption.description,
                    points: redemption.pointsRedeemed,
                    pointTypeId: redemption.pointTypeId,
                    entryType: .adjustment
                ))
            } else {
                // Normal redemption: pointsRedeemed is positive, show as negative
                entries.append(HistoryEntry(
                    id: redemption.id,
                    date: redemption.date,
                    description: redemption.description,
                    points: -redemption.pointsRedeemed,
                    pointTypeId: redemption.pointTypeId,
                    entryType: .redeemed
                ))
            }
        }

        // Sort ascending by date for running balance calculation
        entries.sort { $0.date < $1.date }

        // Calculate running balance per point type
        var balanceByType: [UUID: Decimal] = [:]
        for i in 0..<entries.count {
            let ptId = entries[i].pointTypeId
            balanceByType[ptId, default: 0] += entries[i].points
            entries[i].runningBalance = balanceByType[ptId]!
        }

        // Reverse for display (newest first)
        historyEntries = entries.reversed()
    }
}
