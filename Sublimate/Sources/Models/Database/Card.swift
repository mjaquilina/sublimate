import Foundation
import GRDB

/// Represents a credit card
struct Card: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var issuer: String
    var lastFour: String
    var notes: String?
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(), name: String, issuer: String, lastFour: String, notes: String? = nil,
         createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.issuer = issuer
        self.lastFour = lastFour
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - GRDB Persistence
extension Card: FetchableRecord, PersistableRecord {
    static let databaseTableName = "cards"

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let name = Column(CodingKeys.name)
        static let issuer = Column(CodingKeys.issuer)
        static let lastFour = Column(CodingKeys.lastFour)
        static let notes = Column(CodingKeys.notes)
        static let createdAt = Column(CodingKeys.createdAt)
        static let updatedAt = Column(CodingKeys.updatedAt)
    }

    mutating func willUpdate(_ db: Database, column: String) throws {
        updatedAt = Date()
    }
}

// MARK: - Associations
extension Card {
    static let pointTypes = hasMany(PointType.self)
    static let earningRules = hasMany(EarningRule.self)
    static let spendOffers = hasMany(SpendOffer.self)
    static let rebates = hasMany(Rebate.self)
    static let transactions = hasMany(Transaction.self)

    var pointTypes: QueryInterfaceRequest<PointType> {
        request(for: Card.pointTypes)
    }

    var earningRules: QueryInterfaceRequest<EarningRule> {
        request(for: Card.earningRules)
    }

    var spendOffers: QueryInterfaceRequest<SpendOffer> {
        request(for: Card.spendOffers)
    }

    var rebates: QueryInterfaceRequest<Rebate> {
        request(for: Card.rebates)
    }

    var transactions: QueryInterfaceRequest<Transaction> {
        request(for: Card.transactions)
    }
}

// MARK: - Query Methods
extension Card {
    static func findByID(_ db: Database, id: UUID) throws -> Card? {
        try Card.fetchOne(db, key: id)
    }

    static func all(_ db: Database) throws -> [Card] {
        try Card.fetchAll(db)
    }
}
