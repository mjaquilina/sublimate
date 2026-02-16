import Foundation
import GRDB

/// Represents a credit card transaction
struct Transaction: Codable, Identifiable {
    var id: UUID
    var cardId: UUID
    var date: Date
    var vendor: String
    var merchantCategory: String?
    var amount: Decimal
    var transactionType: TransactionType
    var rewardEligible: Bool
    var notes: String?
    var ynabTransactionId: String?
    var linkedTransactionId: UUID?  // For linking statement credits to their source
    var onlineTransaction: Bool
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(), cardId: UUID, date: Date, vendor: String, merchantCategory: String? = nil,
         amount: Decimal, transactionType: TransactionType, rewardEligible: Bool = true,
         notes: String? = nil, ynabTransactionId: String? = nil, linkedTransactionId: UUID? = nil,
         onlineTransaction: Bool = false,
         createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.cardId = cardId
        self.date = date
        self.vendor = vendor
        self.merchantCategory = merchantCategory
        self.amount = amount
        self.transactionType = transactionType
        self.rewardEligible = rewardEligible
        self.notes = notes
        self.ynabTransactionId = ynabTransactionId
        self.linkedTransactionId = linkedTransactionId
        self.onlineTransaction = onlineTransaction
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - GRDB Persistence
extension Transaction: FetchableRecord, PersistableRecord {
    static let databaseTableName = "transactions"

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let cardId = Column(CodingKeys.cardId)
        static let date = Column(CodingKeys.date)
        static let vendor = Column(CodingKeys.vendor)
        static let merchantCategory = Column(CodingKeys.merchantCategory)
        static let amount = Column(CodingKeys.amount)
        static let transactionType = Column(CodingKeys.transactionType)
        static let rewardEligible = Column(CodingKeys.rewardEligible)
        static let notes = Column(CodingKeys.notes)
        static let ynabTransactionId = Column(CodingKeys.ynabTransactionId)
        static let linkedTransactionId = Column(CodingKeys.linkedTransactionId)
        static let onlineTransaction = Column(CodingKeys.onlineTransaction)
        static let createdAt = Column(CodingKeys.createdAt)
        static let updatedAt = Column(CodingKeys.updatedAt)
    }

    mutating func willUpdate(_ db: Database, column: String) throws {
        updatedAt = Date()
    }
}

// MARK: - Associations
extension Transaction {
    static let card = belongsTo(Card.self)
    static let rewards = hasMany(TransactionReward.self)

    var card: QueryInterfaceRequest<Card> {
        request(for: Transaction.card)
    }

    var rewards: QueryInterfaceRequest<TransactionReward> {
        request(for: Transaction.rewards)
    }
}

// MARK: - Query Methods
extension Transaction {
    static func findByID(_ db: Database, id: UUID) throws -> Transaction? {
        try Transaction.fetchOne(db, key: id)
    }

    static func forCard(_ db: Database, cardId: UUID, limit: Int? = nil) throws -> [Transaction] {
        var query = Transaction
            .filter(Columns.cardId == cardId)
            .order(Columns.date.desc)

        if let limit = limit {
            query = query.limit(limit)
        }

        return try query.fetchAll(db)
    }

    static func forDateRange(_ db: Database, startDate: Date, endDate: Date) throws -> [Transaction] {
        try Transaction
            .filter(Columns.date >= startDate && Columns.date <= endDate)
            .order(Columns.date.desc)
            .fetchAll(db)
    }

    static func existsWithYNABId(_ db: Database, ynabId: String) throws -> Bool {
        try Transaction
            .filter(Columns.ynabTransactionId == ynabId)
            .fetchCount(db) > 0
    }

    var isEligibleForRewards: Bool {
        if transactionType == .statementCredit || transactionType == .payment || transactionType == .fee {
            return false
        }
        return rewardEligible
    }
}
