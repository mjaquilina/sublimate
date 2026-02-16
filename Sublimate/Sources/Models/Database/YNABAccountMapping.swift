import Foundation
import GRDB

/// Maps YNAB accounts to cards in the app
struct YNABAccountMapping: Codable, Identifiable {
    var id: UUID
    var ynabBudgetId: String
    var ynabAccountId: String
    var ynabAccountName: String
    var cardId: UUID
    var lastImportDate: Date?
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(), ynabBudgetId: String, ynabAccountId: String, ynabAccountName: String,
         cardId: UUID, lastImportDate: Date? = nil, createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.ynabBudgetId = ynabBudgetId
        self.ynabAccountId = ynabAccountId
        self.ynabAccountName = ynabAccountName
        self.cardId = cardId
        self.lastImportDate = lastImportDate
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - GRDB Persistence
extension YNABAccountMapping: FetchableRecord, PersistableRecord {
    static let databaseTableName = "ynab_account_mappings"

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let ynabBudgetId = Column(CodingKeys.ynabBudgetId)
        static let ynabAccountId = Column(CodingKeys.ynabAccountId)
        static let ynabAccountName = Column(CodingKeys.ynabAccountName)
        static let cardId = Column(CodingKeys.cardId)
        static let lastImportDate = Column(CodingKeys.lastImportDate)
        static let createdAt = Column(CodingKeys.createdAt)
        static let updatedAt = Column(CodingKeys.updatedAt)
    }

    mutating func willUpdate(_ db: Database, column: String) throws {
        updatedAt = Date()
    }
}

// MARK: - Associations
extension YNABAccountMapping {
    static let card = belongsTo(Card.self)

    var card: QueryInterfaceRequest<Card> {
        request(for: YNABAccountMapping.card)
    }
}

// MARK: - Query Methods
extension YNABAccountMapping {
    static func findByYNABAccount(_ db: Database, budgetId: String, accountId: String) throws -> YNABAccountMapping? {
        try YNABAccountMapping
            .filter(Columns.ynabBudgetId == budgetId && Columns.ynabAccountId == accountId)
            .fetchOne(db)
    }

    static func all(_ db: Database) throws -> [YNABAccountMapping] {
        try YNABAccountMapping.fetchAll(db)
    }

    mutating func updateLastImportDate(_ db: Database, date: Date) throws {
        lastImportDate = date
        updatedAt = Date()
        try update(db)
    }
}
