import Foundation
import GRDB

/// Represents a rule for earning points on transactions
struct EarningRule: Codable, Identifiable {
    var id: UUID
    var cardId: UUID
    var pointTypeId: UUID
    var name: String
    var matchType: MatchType
    var matchValues: [String]  // JSON array stored as string in DB
    var pointsPerDollar: Decimal
    var isActive: Bool
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(), cardId: UUID, pointTypeId: UUID, name: String, matchType: MatchType,
         matchValues: [String], pointsPerDollar: Decimal, isActive: Bool = true,
         createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.cardId = cardId
        self.pointTypeId = pointTypeId
        self.name = name
        self.matchType = matchType
        self.matchValues = matchValues
        self.pointsPerDollar = pointsPerDollar
        self.isActive = isActive
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - GRDB Persistence
extension EarningRule: FetchableRecord, PersistableRecord {
    static let databaseTableName = "earning_rules"

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let cardId = Column(CodingKeys.cardId)
        static let pointTypeId = Column(CodingKeys.pointTypeId)
        static let name = Column(CodingKeys.name)
        static let matchType = Column(CodingKeys.matchType)
        static let matchValues = Column(CodingKeys.matchValues)
        static let pointsPerDollar = Column(CodingKeys.pointsPerDollar)
        static let isActive = Column(CodingKeys.isActive)
        static let createdAt = Column(CodingKeys.createdAt)
        static let updatedAt = Column(CodingKeys.updatedAt)
    }

    mutating func willUpdate(_ db: Database, column: String) throws {
        updatedAt = Date()
    }
}

// MARK: - Associations
extension EarningRule {
    static let card = belongsTo(Card.self)
    static let pointType = belongsTo(PointType.self)

    var card: QueryInterfaceRequest<Card> {
        request(for: EarningRule.card)
    }

    var pointType: QueryInterfaceRequest<PointType> {
        request(for: EarningRule.pointType)
    }
}

// MARK: - Query Methods
extension EarningRule {
    static func activeRulesForCard(_ db: Database, cardId: UUID) throws -> [EarningRule] {
        try EarningRule
            .filter(Columns.cardId == cardId && Columns.isActive == true)
            .fetchAll(db)
    }

    func matches(vendor: String?, category: String?, onlineTransaction: Bool = false) -> Bool {
        switch matchType {
        case .allSpend:
            return true
        case .allOnline:
            return onlineTransaction
        case .vendor:
            guard let vendor = vendor else { return false }
            return matchValues.contains { $0.lowercased() == vendor.lowercased() }
        case .category:
            guard let category = category else { return false }
            return matchValues.contains { $0.lowercased() == category.lowercased() }
        }
    }
}
