import Foundation
import GRDB

/// Represents the current balance of a point type
struct PointBalance: Codable, Identifiable {
    var id: UUID
    var pointTypeId: UUID
    var balance: Decimal
    var updatedAt: Date

    init(id: UUID = UUID(), pointTypeId: UUID, balance: Decimal, updatedAt: Date = Date()) {
        self.id = id
        self.pointTypeId = pointTypeId
        self.balance = balance
        self.updatedAt = updatedAt
    }
}

// MARK: - GRDB Persistence
extension PointBalance: FetchableRecord, PersistableRecord {
    static let databaseTableName = "point_balances"

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let pointTypeId = Column(CodingKeys.pointTypeId)
        static let balance = Column(CodingKeys.balance)
        static let updatedAt = Column(CodingKeys.updatedAt)
    }

    mutating func willUpdate(_ db: Database, column: String) throws {
        updatedAt = Date()
    }
}

// MARK: - Associations
extension PointBalance {
    static let pointType = belongsTo(PointType.self)

    var pointType: QueryInterfaceRequest<PointType> {
        request(for: PointBalance.pointType)
    }
}

// MARK: - Query Methods
extension PointBalance {
    static func findByPointType(_ db: Database, pointTypeId: UUID) throws -> PointBalance? {
        try PointBalance
            .filter(Columns.pointTypeId == pointTypeId)
            .fetchOne(db)
    }

    static func all(_ db: Database) throws -> [PointBalance] {
        try PointBalance.fetchAll(db)
    }

    mutating func adjustBalance(_ db: Database, by amount: Decimal) throws {
        balance += amount
        updatedAt = Date()
        try update(db)
    }
}
