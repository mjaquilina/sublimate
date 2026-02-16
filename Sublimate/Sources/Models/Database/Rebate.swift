import Foundation
import GRDB

/// Represents a rebate or credit offer for specific vendors
struct Rebate: Codable, Identifiable {
    var id: UUID
    var cardId: UUID
    var vendor: String
    var rebateType: RebateType
    var rebateValue: Decimal
    var maxAmount: Decimal?
    var maxUses: Int?
    var usesRemaining: Int?
    var startDate: Date?
    var endDate: Date?
    var isActive: Bool
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(), cardId: UUID, vendor: String, rebateType: RebateType, rebateValue: Decimal,
         maxAmount: Decimal? = nil, maxUses: Int? = nil, usesRemaining: Int? = nil,
         startDate: Date? = nil, endDate: Date? = nil, isActive: Bool = true,
         createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.cardId = cardId
        self.vendor = vendor
        self.rebateType = rebateType
        self.rebateValue = rebateValue
        self.maxAmount = maxAmount
        self.maxUses = maxUses
        self.usesRemaining = usesRemaining ?? maxUses
        self.startDate = startDate
        self.endDate = endDate
        self.isActive = isActive
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - GRDB Persistence
extension Rebate: FetchableRecord, PersistableRecord {
    static let databaseTableName = "rebates"

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let cardId = Column(CodingKeys.cardId)
        static let vendor = Column(CodingKeys.vendor)
        static let rebateType = Column(CodingKeys.rebateType)
        static let rebateValue = Column(CodingKeys.rebateValue)
        static let maxAmount = Column(CodingKeys.maxAmount)
        static let maxUses = Column(CodingKeys.maxUses)
        static let usesRemaining = Column(CodingKeys.usesRemaining)
        static let startDate = Column(CodingKeys.startDate)
        static let endDate = Column(CodingKeys.endDate)
        static let isActive = Column(CodingKeys.isActive)
        static let createdAt = Column(CodingKeys.createdAt)
        static let updatedAt = Column(CodingKeys.updatedAt)
    }

    mutating func willUpdate(_ db: Database, column: String) throws {
        updatedAt = Date()
    }
}

// MARK: - Associations
extension Rebate {
    static let card = belongsTo(Card.self)

    var card: QueryInterfaceRequest<Card> {
        request(for: Rebate.card)
    }
}

// MARK: - Query Methods
extension Rebate {
    static func activeRebatesForCard(_ db: Database, cardId: UUID, vendor: String, date: Date) throws -> [Rebate] {
        let normalizedVendor = vendor.lowercased()

        // Fetch all rebates for the card and filter in Swift for case-insensitive vendor match
        let allRebates = try Rebate
            .filter(Columns.cardId == cardId && Columns.isActive == true)
            .filter(Columns.usesRemaining == nil || Columns.usesRemaining > 0)
            .filter(Columns.startDate == nil || Columns.startDate <= date)
            .filter(Columns.endDate == nil || Columns.endDate >= date)
            .fetchAll(db)

        // Filter by vendor name (case-insensitive)
        return allRebates.filter { $0.vendor.lowercased() == normalizedVendor }
    }

    mutating func decrementUse(_ db: Database) throws {
        if let remaining = usesRemaining, remaining > 0 {
            usesRemaining = remaining - 1
            updatedAt = Date()
            try update(db)
        }
    }
}
