import Foundation
import GRDB

/// Represents a redemption of points
struct PointRedemption: Codable, Identifiable {
    var id: UUID
    var pointTypeId: UUID
    var date: Date
    var pointsRedeemed: Decimal
    var redemptionType: RedemptionType
    var cashValue: Decimal?
    var description: String
    var linkedTransactionId: UUID?
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(), pointTypeId: UUID, date: Date, pointsRedeemed: Decimal,
         redemptionType: RedemptionType, cashValue: Decimal? = nil, description: String,
         linkedTransactionId: UUID? = nil, createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.pointTypeId = pointTypeId
        self.date = date
        self.pointsRedeemed = pointsRedeemed
        self.redemptionType = redemptionType
        self.cashValue = cashValue
        self.description = description
        self.linkedTransactionId = linkedTransactionId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - GRDB Persistence
extension PointRedemption: FetchableRecord, PersistableRecord {
    static let databaseTableName = "point_redemptions"

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let pointTypeId = Column(CodingKeys.pointTypeId)
        static let date = Column(CodingKeys.date)
        static let pointsRedeemed = Column(CodingKeys.pointsRedeemed)
        static let redemptionType = Column(CodingKeys.redemptionType)
        static let cashValue = Column(CodingKeys.cashValue)
        static let description = Column(CodingKeys.description)
        static let linkedTransactionId = Column(CodingKeys.linkedTransactionId)
        static let createdAt = Column(CodingKeys.createdAt)
        static let updatedAt = Column(CodingKeys.updatedAt)
    }

    mutating func willUpdate(_ db: Database, column: String) throws {
        updatedAt = Date()
    }
}

// MARK: - Associations
extension PointRedemption {
    static let pointType = belongsTo(PointType.self)
    static let linkedTransaction = belongsTo(Transaction.self)

    var pointType: QueryInterfaceRequest<PointType> {
        request(for: PointRedemption.pointType)
    }

    var linkedTransaction: QueryInterfaceRequest<Transaction> {
        request(for: PointRedemption.linkedTransaction)
    }
}

// MARK: - Query Methods
extension PointRedemption {
    static func forPointType(_ db: Database, pointTypeId: UUID) throws -> [PointRedemption] {
        try PointRedemption
            .filter(Columns.pointTypeId == pointTypeId)
            .order(Columns.date.desc)
            .fetchAll(db)
    }

    static func forDateRange(_ db: Database, startDate: Date, endDate: Date) throws -> [PointRedemption] {
        try PointRedemption
            .filter(Columns.date >= startDate && Columns.date <= endDate)
            .order(Columns.date.desc)
            .fetchAll(db)
    }

    var effectiveRedemptionRate: Decimal? {
        guard let cash = cashValue, pointsRedeemed > 0 else { return nil }
        return cash / pointsRedeemed
    }
}
