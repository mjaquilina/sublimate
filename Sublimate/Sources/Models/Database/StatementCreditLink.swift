import Foundation
import GRDB

/// Links a statement credit transaction to its source
struct StatementCreditLink: Codable, Identifiable {
    var id: UUID
    var transactionId: UUID
    var sourceType: String  // "spend_offer", "rebate", "point_redemption", "other"
    var sourceId: UUID?
    var notes: String?
    var createdAt: Date

    init(id: UUID = UUID(), transactionId: UUID, sourceType: String, sourceId: UUID? = nil,
         notes: String? = nil, createdAt: Date = Date()) {
        self.id = id
        self.transactionId = transactionId
        self.sourceType = sourceType
        self.sourceId = sourceId
        self.notes = notes
        self.createdAt = createdAt
    }
}

// MARK: - GRDB Persistence
extension StatementCreditLink: FetchableRecord, PersistableRecord {
    static let databaseTableName = "statement_credit_links"

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let transactionId = Column(CodingKeys.transactionId)
        static let sourceType = Column(CodingKeys.sourceType)
        static let sourceId = Column(CodingKeys.sourceId)
        static let notes = Column(CodingKeys.notes)
        static let createdAt = Column(CodingKeys.createdAt)
    }
}

// MARK: - Associations
extension StatementCreditLink {
    static let transaction = belongsTo(Transaction.self)

    var transaction: QueryInterfaceRequest<Transaction> {
        request(for: StatementCreditLink.transaction)
    }
}

// MARK: - Query Methods
extension StatementCreditLink {
    static func forTransaction(_ db: Database, transactionId: UUID) throws -> StatementCreditLink? {
        try StatementCreditLink
            .filter(Columns.transactionId == transactionId)
            .fetchOne(db)
    }

    static func unlinkedStatementCredits(_ db: Database) throws -> [Transaction] {
        let credits = Transaction.filter(Transaction.Columns.transactionType == TransactionType.statementCredit.rawValue)
        let links = StatementCreditLink.all()

        return try credits
            .filter(!links.select(Columns.transactionId).contains(Transaction.Columns.id))
            .fetchAll(db)
    }
}
