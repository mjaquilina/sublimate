import Foundation
import SwiftUI
import GRDB
import Combine

enum ImportState {
    case selectingAccounts
    case loadingTransactions
    case reviewingTransactions([ImportableTransaction])
    case calculatingRewards
    case linkingCredits([Transaction])  // Statement credits to link
    case completed(Int)
    case error(String)
}

struct CreditLinkSource: Identifiable {
    let id: UUID
    let type: String  // "spend_offer", "rebate", "redemption"
    let name: String
    let date: Date
    let amount: Decimal?
}

@MainActor
class YNABImportViewModel: ObservableObject {
    @Published var importState: ImportState = .selectingAccounts
    @Published var accountMappings: [YNABAccountMapping] = []
    @Published var selectedMappings: Set<YNABAccountMapping.ID> = []
    @Published var importSinceDate = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @Published var vendors: [Vendor] = []
    @Published var categories: [Category] = []
    @Published var importProgress: (current: Int, total: Int) = (0, 0)

    private var cards: [UUID: Card] = [:]
    private let ynabService = YNABService.shared

    func loadMappings() {
        Task {
            do {
                let db = try DatabaseManager.shared.database()

                // Load cards first
                let allCards = try await db.read { try Card.fetchAll($0) }
                cards = Dictionary(uniqueKeysWithValues: allCards.map { ($0.id, $0) })

                // Then load mappings (so card names are already available)
                accountMappings = try await db.read { try YNABAccountMapping.fetchAll($0) }
            } catch {
                print("Error loading mappings: \(error)")
                importState = .error("Failed to load account mappings")
            }
        }
    }

    func getCardName(for cardId: UUID) -> String {
        cards[cardId]?.name ?? "Unknown Card"
    }

    func loadTransactions() {
        importState = .loadingTransactions

        Task {
            do {
                let db = try DatabaseManager.shared.database()

                // Load vendors and categories first
                vendors = try await db.read { try Vendor.fetchAll($0) }

                do {
                    categories = try await db.read { try Category.fetchAll($0) }
                } catch {
                    print("Error loading categories: \(error)")
                    importState = .error("Failed to load categories: \(error.localizedDescription)")
                    return
                }

                var allTransactions: [ImportableTransaction] = []

                for mappingId in selectedMappings {
                    guard let mapping = accountMappings.first(where: { $0.id == mappingId }) else { continue }

                    // Fetch transactions from YNAB
                    let ynabTransactions = try await ynabService.fetchTransactions(
                        budgetId: mapping.ynabBudgetId,
                        accountId: mapping.ynabAccountId,
                        sinceDate: importSinceDate
                    )

                    // Check for duplicates — fetch just the string column, not full Transaction structs
                    let existingIds: Set<String> = try await db.read { db in
                        let ids = try String.fetchAll(db,
                            Transaction
                                .select(Transaction.Columns.ynabTransactionId)
                                .filter(Transaction.Columns.ynabTransactionId != nil))
                        return Set(ids)
                    }

                    // Convert to importable transactions
                    for ynabTx in ynabTransactions {
                        // Skip if already imported
                        if existingIds.contains(ynabTx.id) {
                            continue
                        }

                        // Parse date (YNAB uses YYYY-MM-DD format)
                        // Parse as local date to avoid timezone issues
                        let dateFormatter = DateFormatter()
                        dateFormatter.dateFormat = "yyyy-MM-dd"
                        dateFormatter.timeZone = TimeZone.current
                        guard let date = dateFormatter.date(from: ynabTx.date) else { continue }

                        // Classify transaction type
                        let type = ynabService.classifyTransactionType(
                            amount: ynabTx.amount,
                            memo: ynabTx.memo,
                            payeeName: ynabTx.payeeName
                        )

                        // Get vendor name
                        let vendor = ynabTx.payeeName ?? "Unknown"

                        // Get category
                        let category = ynabTx.categoryName

                        // Convert amount
                        let amount = ynabService.convertAmount(ynabTx.amount)

                        let importable = ImportableTransaction(
                            id: ynabTx.id,
                            date: date,
                            vendor: vendor,
                            category: category,
                            amount: amount,
                            type: type,
                            cardId: mapping.cardId,
                            ynabTransactionId: ynabTx.id
                        )

                        // Default to no vendor or category for statement credits (they'll be linked later)
                        if type == .statementCredit {
                            importable.vendor = ""
                            importable.selectedVendor = nil
                            importable.category = nil
                            importable.selectedCategory = nil
                        } else {
                            // Try VendorMapping first (learned from previous imports)
                            var matched = false
                            let mapping = try DatabaseManager.shared.read { db in
                                try VendorMapping.findMapping(db, vendorName: vendor)
                            }
                            if let mapping {
                                importable.vendor = mapping.displayName
                                // Try to match to an existing Vendor object
                                let normalizedDisplay = mapping.displayName.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                                if let matchedVendor = vendors.first(where: { $0.name == normalizedDisplay }) {
                                    importable.selectedVendor = matchedVendor
                                    if let categoryId = matchedVendor.defaultCategoryId {
                                        importable.selectedCategory = categories.first(where: { $0.id == categoryId })
                                        importable.category = importable.selectedCategory?.name
                                    }
                                    importable.onlineTransaction = matchedVendor.defaultToOnlineTransaction
                                    matched = true
                                } else if let mappingCategory = mapping.category {
                                    // Use category from the mapping
                                    importable.selectedCategory = categories.first(where: { $0.name == mappingCategory })
                                    importable.category = importable.selectedCategory?.name
                                    matched = true
                                }
                            }

                            // Fall back to exact vendor name match
                            if !matched {
                                let normalizedVendor = vendor.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                                if let matchedVendor = vendors.first(where: { $0.name == normalizedVendor }) {
                                    importable.selectedVendor = matchedVendor
                                    if let categoryId = matchedVendor.defaultCategoryId {
                                        importable.selectedCategory = categories.first(where: { $0.id == categoryId })
                                        importable.category = importable.selectedCategory?.name
                                    }
                                    importable.onlineTransaction = matchedVendor.defaultToOnlineTransaction
                                }
                            }
                        }

                        // Try to match category from YNAB if not already set (skip for statement credits)
                        if type != .statementCredit, importable.selectedCategory == nil, let ynabCategory = category {
                            importable.selectedCategory = categories.first(where: { $0.name == ynabCategory })
                        }

                        allTransactions.append(importable)
                    }
                }

                if allTransactions.isEmpty {
                    importState = .error("No new transactions to import")
                } else {
                    importState = .reviewingTransactions(allTransactions)
                }
            } catch {
                print("Error loading YNAB transactions: \(error)")
                importState = .error(error.localizedDescription)
            }
        }
    }

    func importTransactions() {
        guard case .reviewingTransactions(let transactions) = importState else { return }

        importState = .calculatingRewards

        Task {
            do {
                let db = try DatabaseManager.shared.database()
                let engine = RewardCalculationEngine(database: db)

                var importedCount = 0
                var importedTransactions: [Transaction] = []

                // Filter to only selected transactions
                let selectedTransactions = transactions.filter { $0.isSelected }
                importProgress = (0, selectedTransactions.count)

                for importableTx in selectedTransactions {
                    // Create vendor if needed (skip if vendor is empty - no vendor selected)
                    if importableTx.selectedVendor == nil && !importableTx.vendor.isEmpty {
                        let normalizedName = importableTx.vendor.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

                        // Check if vendor already exists in DB before inserting
                        let existingVendor = try DatabaseManager.shared.read { db in
                            try Vendor.filter(Vendor.Columns.name == normalizedName).fetchOne(db)
                        }

                        if existingVendor == nil {
                            // Only use category if it exists in our loaded categories (which came from DB)
                            let categoryId: UUID? = if let selectedCat = importableTx.selectedCategory,
                                                       categories.contains(where: { $0.id == selectedCat.id }) {
                                selectedCat.id
                            } else {
                                nil
                            }

                            let newVendor = Vendor(
                                name: normalizedName,
                                displayName: importableTx.vendor,
                                defaultCategoryId: categoryId
                            )
                            try DatabaseManager.shared.write { db in
                                try newVendor.insert(db)
                            }
                        }
                    } else if let vendor = importableTx.selectedVendor,
                              let selectedCat = importableTx.selectedCategory,
                              categories.contains(where: { $0.id == selectedCat.id }),
                              vendor.defaultCategoryId != selectedCat.id {
                        // Update vendor's default category (already validated it exists)
                        var updatedVendor = vendor
                        updatedVendor.defaultCategoryId = selectedCat.id
                        try DatabaseManager.shared.write { db in
                            try updatedVendor.update(db)
                        }
                    }

                    // Create Transaction object
                    // Only use the category if the user explicitly selected a Sublimate category
                    let transaction = Transaction(
                        cardId: importableTx.cardId,
                        date: importableTx.date,
                        vendor: importableTx.vendor,
                        merchantCategory: importableTx.selectedCategory?.name,
                        amount: importableTx.amount,
                        transactionType: importableTx.type,
                        rewardEligible: importableTx.type == .purchase || importableTx.type == .refund,
                        ynabTransactionId: importableTx.ynabTransactionId,
                        onlineTransaction: importableTx.onlineTransaction
                    )

                    // Calculate and save rewards if eligible
                    if transaction.isEligibleForRewards {
                        let preview = try engine.calculateTransactionRewards(transaction)
                        try engine.saveTransactionWithRewards(transaction, preview: preview)
                    } else {
                        // Save without rewards
                        try DatabaseManager.shared.write { db in
                            let mutableTx = transaction
                            try mutableTx.insert(db)
                        }
                    }

                    // Learn vendor mapping for future imports
                    if !importableTx.vendor.isEmpty && !importableTx.originalVendorName.isEmpty {
                        try DatabaseManager.shared.write { db in
                            _ = try VendorMapping.createOrUpdate(
                                db,
                                rawName: importableTx.originalVendorName,
                                displayName: importableTx.vendor,
                                category: importableTx.selectedCategory?.name
                            )
                        }
                    }

                    importedTransactions.append(transaction)
                    importedCount += 1
                    importProgress = (importedCount, selectedTransactions.count)
                }

                // Update last import date for selected mappings
                let mappingIds = selectedMappings  // Capture before async closure
                try await db.write { db in
                    for mappingId in mappingIds {
                        if var mapping = try YNABAccountMapping.fetchOne(db, key: mappingId) {
                            mapping.lastImportDate = Date()
                            try mapping.update(db)
                        }
                    }
                }

                // Check for statement credits that need linking
                let statementCredits = importedTransactions.filter { $0.transactionType == .statementCredit }
                if !statementCredits.isEmpty {
                    importState = .linkingCredits(statementCredits)
                } else {
                    importState = .completed(importedCount)
                }
            } catch {
                print("Error importing transactions: \(error)")
                importState = .error("Failed to import: \(error.localizedDescription)")
            }
        }
    }

    func loadAvailableSources(for transaction: Transaction) async throws -> [CreditLinkSource] {
        let db = try DatabaseManager.shared.database()

        return try await db.read { db in
            var sources: [CreditLinkSource] = []

            // Get spend offers for this card (within reasonable date range)
            let dateRange = Calendar.current.date(byAdding: .month, value: -3, to: transaction.date) ?? transaction.date
            let offers = try SpendOffer.fetchAll(db).filter {
                $0.cardId == transaction.cardId &&
                $0.startDate <= transaction.date &&
                $0.endDate >= dateRange
            }

            for offer in offers {
                sources.append(CreditLinkSource(
                    id: offer.id,
                    type: "spend_offer",
                    name: offer.name,
                    date: offer.endDate,
                    amount: nil
                ))
            }

            // Get rebates for this card
            let rebates = try Rebate.fetchAll(db).filter {
                $0.cardId == transaction.cardId &&
                ($0.endDate == nil || $0.endDate! >= dateRange)
            }

            for rebate in rebates {
                sources.append(CreditLinkSource(
                    id: rebate.id,
                    type: "rebate",
                    name: rebate.vendor,
                    date: rebate.endDate ?? Date(),
                    amount: rebate.rebateType == .fixed ? rebate.rebateValue : nil
                ))
            }

            // Get point redemptions
            let redemptions = try PointRedemption.fetchAll(db).filter {
                $0.redemptionType == .statementCredit &&
                abs($0.date.timeIntervalSince(transaction.date)) < 30 * 24 * 3600  // Within 30 days
            }

            for redemption in redemptions {
                if let pointType = try PointType.findByID(db, id: redemption.pointTypeId) {
                    sources.append(CreditLinkSource(
                        id: redemption.id,
                        type: "redemption",
                        name: "\(pointType.name) redemption",
                        date: redemption.date,
                        amount: redemption.cashValue
                    ))
                }
            }

            return sources.sorted { $0.date > $1.date }
        }
    }

    func linkCredit(transactionId: UUID, sourceId: UUID?, sourceType: String?) {
        Task {
            do {
                try DatabaseManager.shared.write { db in
                    // Remove any existing link for this transaction
                    try StatementCreditLink
                        .filter(StatementCreditLink.Columns.transactionId == transactionId)
                        .deleteAll(db)

                    // Create new link if a source was selected
                    if let sourceId, let sourceType {
                        let link = StatementCreditLink(
                            transactionId: transactionId,
                            sourceType: sourceType,
                            sourceId: sourceId
                        )
                        try link.insert(db)
                    }
                }
            } catch {
                print("Error linking credit: \(error)")
            }
        }
    }

    func skipCreditLinking(importedCount: Int) {
        importState = .completed(importedCount)
    }

    func reset() {
        importState = .selectingAccounts
        selectedMappings.removeAll()
    }
}
