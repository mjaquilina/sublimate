import Foundation
import GRDB

/// Represents a type of points currency for a card
struct PointType: Codable, Identifiable, Hashable {
    var id: UUID
    var cardId: UUID
    var name: String
    var cashValuePerPoint: Decimal
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(), cardId: UUID, name: String, cashValuePerPoint: Decimal,
         createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.cardId = cardId
        self.name = name
        self.cashValuePerPoint = cashValuePerPoint
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - GRDB Persistence
extension PointType: FetchableRecord, PersistableRecord {
    static let databaseTableName = "point_types"

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let cardId = Column(CodingKeys.cardId)
        static let name = Column(CodingKeys.name)
        static let cashValuePerPoint = Column(CodingKeys.cashValuePerPoint)
        static let createdAt = Column(CodingKeys.createdAt)
        static let updatedAt = Column(CodingKeys.updatedAt)
    }

    mutating func willUpdate(_ db: Database, column: String) throws {
        updatedAt = Date()
    }
}

// MARK: - Associations
extension PointType {
    static let card = belongsTo(Card.self)
    static let pointBalances = hasMany(PointBalance.self)
    static let earningRules = hasMany(EarningRule.self)

    var card: QueryInterfaceRequest<Card> {
        request(for: PointType.card)
    }
}

// MARK: - Query Methods
extension PointType {
    static func findByID(_ db: Database, id: UUID) throws -> PointType? {
        try PointType.fetchOne(db, key: id)
    }

    static func forCard(_ db: Database, cardId: UUID) throws -> [PointType] {
        try PointType
            .filter(Columns.cardId == cardId)
            .fetchAll(db)
    }
}
