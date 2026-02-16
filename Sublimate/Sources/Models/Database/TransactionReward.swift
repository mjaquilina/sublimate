import Foundation
import GRDB

/// Represents rewards earned from a transaction
struct TransactionReward: Codable, Identifiable {
    var id: UUID
    var transactionId: UUID
    var rewardSourceType: String  // "earning_rule", "spend_offer", "rebate"
    var rewardSourceId: UUID
    var pointTypeId: UUID?
    var pointsEarned: Decimal?
    var cashValue: Decimal
    var description: String
    var createdAt: Date

    init(id: UUID = UUID(), transactionId: UUID, rewardSourceType: String, rewardSourceId: UUID,
         pointTypeId: UUID? = nil, pointsEarned: Decimal? = nil, cashValue: Decimal, description: String,
         createdAt: Date = Date()) {
        self.id = id
        self.transactionId = transactionId
        self.rewardSourceType = rewardSourceType
        self.rewardSourceId = rewardSourceId
        self.pointTypeId = pointTypeId
        self.pointsEarned = pointsEarned
        self.cashValue = cashValue
        self.description = description
        self.createdAt = createdAt
    }
}

// MARK: - GRDB Persistence
extension TransactionReward: FetchableRecord, PersistableRecord {
    static let databaseTableName = "transaction_rewards"

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let transactionId = Column(CodingKeys.transactionId)
        static let rewardSourceType = Column(CodingKeys.rewardSourceType)
        static let rewardSourceId = Column(CodingKeys.rewardSourceId)
        static let pointTypeId = Column(CodingKeys.pointTypeId)
        static let pointsEarned = Column(CodingKeys.pointsEarned)
        static let cashValue = Column(CodingKeys.cashValue)
        static let description = Column(CodingKeys.description)
        static let createdAt = Column(CodingKeys.createdAt)
    }
}

// MARK: - Associations
extension TransactionReward {
    static let transaction = belongsTo(Transaction.self)
    static let pointType = belongsTo(PointType.self)

    var transaction: QueryInterfaceRequest<Transaction> {
        request(for: TransactionReward.transaction)
    }

    var pointType: QueryInterfaceRequest<PointType> {
        request(for: TransactionReward.pointType)
    }
}

// MARK: - Query Methods
extension TransactionReward {
    static func forTransaction(_ db: Database, transactionId: UUID) throws -> [TransactionReward] {
        try TransactionReward
            .filter(Columns.transactionId == transactionId)
            .fetchAll(db)
    }

    static func totalCashValueForDateRange(_ db: Database, startDate: Date, endDate: Date) throws -> Decimal {
        // Get all transactions in date range (fetch full objects, not just IDs)
        let transactions = try Transaction
            .filter(Transaction.Columns.date >= startDate && Transaction.Columns.date <= endDate)
            .fetchAll(db)

        let transactionIds = transactions.map { $0.id }

        // Get all rewards for those transactions and sum manually
        let rewards = try TransactionReward
            .filter(transactionIds.contains(Columns.transactionId))
            .fetchAll(db)

        return rewards.reduce(0) { $0 + $1.cashValue }
    }
}
