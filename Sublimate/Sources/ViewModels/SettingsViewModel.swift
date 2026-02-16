import Foundation
import SwiftUI
import AppKit
import Combine
import GRDB
import UniformTypeIdentifiers

@MainActor
class SettingsViewModel: ObservableObject {
    @Published var ynabConnectionStatus: String?
    @Published var ynabConnected = false
    @Published var accountMappings: [YNABAccountMapping] = []
    @Published var showingDeleteTransactionsConfirm = false
    @Published var showingGenerateSampleDataConfirm = false

    private var cards: [UUID: Card] = [:]
    private var databaseSwitchObserver: NSObjectProtocol?

    init() {
        // Observe database switches and reload data
        databaseSwitchObserver = NotificationCenter.default.addObserver(
            forName: DatabaseManager.databaseDidSwitchNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.loadAccountMappings()
        }
    }

    deinit {
        if let observer = databaseSwitchObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func testYNABConnection(token: String) {
        Task {
            do {
                let service = YNABService.shared
                let success = try await service.authenticateWithToken(token)
                ynabConnected = success
                ynabConnectionStatus = success ? "Connected successfully" : "Connection failed"

                if success {
                    loadAccountMappings()
                }
            } catch {
                ynabConnected = false
                ynabConnectionStatus = "Error: \(error.localizedDescription)"
            }
        }
    }

    func loadAccountMappings() {
        Task {
            do {
                let db = try DatabaseManager.shared.database()
                accountMappings = try await db.read { try YNABAccountMapping.fetchAll($0) }

                let allCards = try await db.read { try Card.fetchAll($0) }
                cards = Dictionary(uniqueKeysWithValues: allCards.map { ($0.id, $0) })

                ynabConnected = YNABService.shared.isAuthenticated()
            } catch {
                print("Error loading mappings: \(error)")
            }
        }
    }

    func getCardName(for cardId: UUID) -> String {
        cards[cardId]?.name ?? "Unknown Card"
    }

    func exportData() {
        Task {
            let savePanel = NSSavePanel()
            savePanel.title = "Export Data"
            savePanel.message = "Choose where to save the exported data"
            savePanel.nameFieldStringValue = "sublimate-export-\(Date().formatted(date: .numeric, time: .omitted)).csv"
            savePanel.allowedContentTypes = [.commaSeparatedText]

            let response = await savePanel.begin()

            if response == .OK, let url = savePanel.url {
                do {
                    let csvData = try await generateExportCSV()
                    try csvData.write(to: url, atomically: true, encoding: .utf8)

                    // Show success and reveal in Finder
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                } catch {
                    await showAlert(title: "Export Failed", message: error.localizedDescription)
                }
            }
        }
    }

    func showDatabaseLocation() {
        do {
            let dbURL = try DatabaseManager.shared.getDatabaseURL()
            // Reveal the database file in Finder
            NSWorkspace.shared.activateFileViewerSelecting([dbURL])
        } catch {
            Task {
                await showAlert(title: "Cannot Locate Database", message: error.localizedDescription)
            }
        }
    }

    private func generateExportCSV() async throws -> String {
        let db = try DatabaseManager.shared.database()

        return try await db.read { db in
            var csv = ""

            // SECTION 1: Transactions with Rewards
            csv += "=== TRANSACTIONS WITH REWARDS ===\n"
            csv += "Date,Card,Vendor,Category,Amount,Type,Reward Eligible,Points Value,Spend Offer Value,Rebate Value,Total Rewards\n"

            let transactions = try Transaction.fetchAll(db).sorted { $0.date > $1.date }

            for transaction in transactions {
                let card = try Card.findByID(db, id: transaction.cardId)
                let rewards = try TransactionReward.forTransaction(db, transactionId: transaction.id)

                let pointsValue = rewards.filter { $0.rewardSourceType == "earning_rule" }.reduce(0) { $0 + $1.cashValue }
                let offerValue = rewards.filter { $0.rewardSourceType == "spend_offer" }.reduce(0) { $0 + $1.cashValue }
                let rebateValue = rewards.filter { $0.rewardSourceType == "rebate" }.reduce(0) { $0 + $1.cashValue }
                let totalRewards = rewards.reduce(0) { $0 + $1.cashValue }

                csv += "\(transaction.date.toShortString()),"
                csv += "\"\(card?.name ?? "Unknown")\","
                csv += "\"\(transaction.vendor)\","
                csv += "\"\(transaction.merchantCategory ?? "")\","
                csv += "\(transaction.amount),"
                csv += "\(transaction.transactionType.rawValue),"
                csv += "\(transaction.rewardEligible),"
                csv += "\(pointsValue),"
                csv += "\(offerValue),"
                csv += "\(rebateValue),"
                csv += "\(totalRewards)\n"
            }

            csv += "\n"

            // SECTION 2: Card Summary
            csv += "=== CARD PERFORMANCE SUMMARY ===\n"
            csv += "Card,Eligible Spend,Points Value,Spend Offer Value,Rebate Value,Total Rewards,Effective Rate %\n"

            let cards = try Card.all(db)
            for card in cards {
                let cardTransactions = transactions.filter {
                    $0.cardId == card.id &&
                    ($0.transactionType == .purchase || $0.transactionType == .refund)
                }

                let eligibleSpend = cardTransactions.reduce(0) { $0 + $1.amount }

                var totalPoints: Decimal = 0
                var totalOffers: Decimal = 0
                var totalRebates: Decimal = 0

                for tx in cardTransactions {
                    let rewards = try TransactionReward.forTransaction(db, transactionId: tx.id)
                    totalPoints += rewards.filter { $0.rewardSourceType == "earning_rule" }.reduce(0) { $0 + $1.cashValue }
                    totalOffers += rewards.filter { $0.rewardSourceType == "spend_offer" }.reduce(0) { $0 + $1.cashValue }
                    totalRebates += rewards.filter { $0.rewardSourceType == "rebate" }.reduce(0) { $0 + $1.cashValue }
                }

                let totalRewards = totalPoints + totalOffers + totalRebates
                let effectiveRate = eligibleSpend > 0 ? (totalRewards / eligibleSpend) * 100 : 0

                csv += "\"\(card.name)\","
                csv += "\(eligibleSpend),"
                csv += "\(totalPoints),"
                csv += "\(totalOffers),"
                csv += "\(totalRebates),"
                csv += "\(totalRewards),"
                csv += "\(effectiveRate)\n"
            }

            csv += "\n"

            // SECTION 3: Point Balances
            csv += "=== POINT BALANCES ===\n"
            csv += "Card,Point Type,Balance,Cash Value Per Point,Total Cash Value\n"

            for card in cards {
                let pointTypes = try PointType.forCard(db, cardId: card.id)
                for pointType in pointTypes {
                    if let balance = try PointBalance.findByPointType(db, pointTypeId: pointType.id) {
                        let totalValue = balance.balance * pointType.cashValuePerPoint
                        csv += "\"\(card.name)\","
                        csv += "\"\(pointType.name)\","
                        csv += "\(balance.balance),"
                        csv += "\(pointType.cashValuePerPoint),"
                        csv += "\(totalValue)\n"
                    }
                }
            }

            csv += "\n"

            // SECTION 4: Point Redemptions
            csv += "=== POINT REDEMPTIONS ===\n"
            csv += "Date,Point Type,Points Redeemed,Redemption Type,Cash Value,Description\n"

            let redemptions = try PointRedemption.fetchAll(db).sorted { $0.date > $1.date }
            for redemption in redemptions {
                if let pointType = try PointType.findByID(db, id: redemption.pointTypeId) {
                    csv += "\(redemption.date.toShortString()),"
                    csv += "\"\(pointType.name)\","
                    csv += "\(redemption.pointsRedeemed),"
                    csv += "\(redemption.redemptionType.rawValue),"
                    csv += "\(redemption.cashValue ?? 0),"
                    csv += "\"\(redemption.description ?? "")\"\n"
                }
            }

            csv += "\n"

            // SECTION 5: Active Spend Offers
            csv += "=== ACTIVE SPEND OFFERS ===\n"
            csv += "Card,Name,Type,Start Date,End Date,Current Spend,Progress %,Status\n"

            let now = Date()
            let offers = try SpendOffer.fetchAll(db).filter { $0.isActive && $0.startDate <= now && $0.endDate >= now }
            for offer in offers {
                let card = try Card.findByID(db, id: offer.cardId)
                let progress = offer.progressPercentage() ?? 0
                let status = progress >= 100 ? "Complete" : "In Progress"

                csv += "\"\(card?.name ?? "Unknown")\","
                csv += "\"\(offer.name)\","
                csv += "\(offer.offerType.rawValue),"
                csv += "\(offer.startDate.toShortString()),"
                csv += "\(offer.endDate.toShortString()),"
                csv += "\(offer.currentSpend),"
                csv += "\(progress),"
                csv += "\(status)\n"
            }

            csv += "\n"

            // SECTION 6: Active Rebates
            csv += "=== ACTIVE REBATES ===\n"
            csv += "Card,Vendor,Type,Value,Max Uses,Uses Remaining,Expires\n"

            let rebates = try Rebate.fetchAll(db).filter { $0.isActive }
            for rebate in rebates {
                let card = try Card.findByID(db, id: rebate.cardId)
                csv += "\"\(card?.name ?? "Unknown")\","
                csv += "\"\(rebate.vendor)\","
                csv += "\(rebate.rebateType.rawValue),"
                csv += "\(rebate.rebateValue),"
                csv += "\(rebate.maxUses ?? 0),"
                csv += "\(rebate.usesRemaining ?? 0),"
                csv += "\(rebate.endDate?.toShortString() ?? "No expiration")\n"
            }

            return csv
        }
    }

    func repairOfferProgress() {
        Task {
            do {
                let db = try DatabaseManager.shared.database()
                let engine = RewardCalculationEngine(database: db)
                let result = try engine.repairOfferProgress()
                await showAlert(
                    title: "Success",
                    message: "Repaired offer progress: \(result.offersUpdated) offers updated, \(result.transactionsScanned) transactions scanned."
                )
            } catch {
                await showAlert(title: "Error", message: "Failed to repair offer progress: \(error.localizedDescription)")
            }
        }
    }

    func recalculatePointBalances() {
        Task {
            do {
                let db = try DatabaseManager.shared.database()

                try await db.write { db in
                    // Reset all balances to 0
                    try db.execute(sql: "UPDATE point_balances SET balance = 0, updatedAt = ?", arguments: [Date()])

                    // Get all transaction rewards that added points
                    let rewards = try TransactionReward.fetchAll(db)

                    // Group by point type and sum up
                    var pointTotals: [UUID: Decimal] = [:]
                    for reward in rewards {
                        if let pointTypeId = reward.pointTypeId, let points = reward.pointsEarned {
                            pointTotals[pointTypeId, default: 0] += points
                        }
                    }

                    // Subtract redeemed points
                    let redemptions = try PointRedemption.fetchAll(db)
                    for redemption in redemptions {
                        pointTotals[redemption.pointTypeId, default: 0] -= redemption.pointsRedeemed
                    }

                    // Update balances
                    for (pointTypeId, balance) in pointTotals {
                        try db.execute(
                            sql: "UPDATE point_balances SET balance = ?, updatedAt = ? WHERE pointTypeId = ?",
                            arguments: [balance, Date(), pointTypeId]
                        )
                    }
                }

                await showAlert(title: "Success", message: "Point balances have been recalculated.")
            } catch {
                await showAlert(title: "Error", message: "Failed to recalculate balances: \(error.localizedDescription)")
            }
        }
    }

    func generateSampleData() {
        Task {
            do {
                try SampleDataGenerator.generate()
                await showAlert(title: "Success", message: "Sample data has been generated. You can now explore cards, transactions, offers, and more.")
            } catch {
                await showAlert(title: "Error", message: "Failed to generate sample data: \(error.localizedDescription)")
            }
        }
    }

    func deleteAllTransactions() {
        Task {
            do {
                let db = try DatabaseManager.shared.database()

                try await db.write { db in
                    // Delete transaction rewards first (foreign key constraint)
                    try db.execute(sql: "DELETE FROM transaction_rewards")

                    // Delete transactions
                    try db.execute(sql: "DELETE FROM transactions")

                    // Reset spend offer progress
                    try db.execute(sql: "UPDATE spend_offers SET currentSpend = 0, currentCount = 0")

                    // Reset rebate uses
                    try db.execute(sql: "UPDATE rebates SET usesRemaining = maxUses WHERE maxUses IS NOT NULL")

                    // Reset point balances to 0
                    try db.execute(sql: "UPDATE point_balances SET balance = 0, updatedAt = ?", arguments: [Date()])

                    // Note: Point redemptions are kept for historical record
                    // If you want to delete those too, uncomment:
                    // try db.execute(sql: "DELETE FROM point_redemptions")
                }

                await showAlert(title: "Success", message: "All transactions have been deleted and point balances reset to 0.")
            } catch {
                await showAlert(title: "Error", message: "Failed to delete transactions: \(error.localizedDescription)")
            }
        }
    }

    private func showAlert(title: String, message: String) async {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        await alert.runModal()
    }
}
