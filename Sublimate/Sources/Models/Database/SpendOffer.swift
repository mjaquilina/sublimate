import Foundation
import GRDB

/// Represents a promotional spend offer
struct SpendOffer: Codable, Identifiable {
    var id: UUID
    var cardId: UUID
    var name: String
    var offerType: OfferType
    var matchType: MatchType
    var matchValues: [String]  // JSON array
    var rewardPercentage: Decimal?
    var maxRewardAmount: Decimal?
    var flatBonusAmount: Decimal?
    var spendThreshold: Decimal?
    var countRequired: Int?
    var transactionMinAmount: Decimal?
    var pointTypeId: UUID?
    var startDate: Date
    var endDate: Date
    var currentSpend: Decimal
    var currentCount: Int
    var isActive: Bool
    var includeInOptimizations: Bool
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(), cardId: UUID, name: String, offerType: OfferType, matchType: MatchType,
         matchValues: [String], rewardPercentage: Decimal? = nil, maxRewardAmount: Decimal? = nil,
         flatBonusAmount: Decimal? = nil, spendThreshold: Decimal? = nil, countRequired: Int? = nil,
         transactionMinAmount: Decimal? = nil, pointTypeId: UUID? = nil, startDate: Date, endDate: Date,
         currentSpend: Decimal = 0, currentCount: Int = 0, isActive: Bool = true,
         includeInOptimizations: Bool = true,
         createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.cardId = cardId
        self.name = name
        self.offerType = offerType
        self.matchType = matchType
        self.matchValues = matchValues
        self.rewardPercentage = rewardPercentage
        self.maxRewardAmount = maxRewardAmount
        self.flatBonusAmount = flatBonusAmount
        self.spendThreshold = spendThreshold
        self.countRequired = countRequired
        self.transactionMinAmount = transactionMinAmount
        self.pointTypeId = pointTypeId
        self.startDate = startDate
        self.endDate = endDate
        self.currentSpend = currentSpend
        self.currentCount = currentCount
        self.isActive = isActive
        self.includeInOptimizations = includeInOptimizations
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - GRDB Persistence
extension SpendOffer: FetchableRecord, PersistableRecord {
    static let databaseTableName = "spend_offers"

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let cardId = Column(CodingKeys.cardId)
        static let name = Column(CodingKeys.name)
        static let offerType = Column(CodingKeys.offerType)
        static let matchType = Column(CodingKeys.matchType)
        static let matchValues = Column(CodingKeys.matchValues)
        static let rewardPercentage = Column(CodingKeys.rewardPercentage)
        static let maxRewardAmount = Column(CodingKeys.maxRewardAmount)
        static let flatBonusAmount = Column(CodingKeys.flatBonusAmount)
        static let spendThreshold = Column(CodingKeys.spendThreshold)
        static let countRequired = Column(CodingKeys.countRequired)
        static let transactionMinAmount = Column(CodingKeys.transactionMinAmount)
        static let pointTypeId = Column(CodingKeys.pointTypeId)
        static let startDate = Column(CodingKeys.startDate)
        static let endDate = Column(CodingKeys.endDate)
        static let currentSpend = Column(CodingKeys.currentSpend)
        static let currentCount = Column(CodingKeys.currentCount)
        static let isActive = Column(CodingKeys.isActive)
        static let includeInOptimizations = Column(CodingKeys.includeInOptimizations)
        static let createdAt = Column(CodingKeys.createdAt)
        static let updatedAt = Column(CodingKeys.updatedAt)
    }

    mutating func willUpdate(_ db: Database, column: String) throws {
        updatedAt = Date()
    }
}

// MARK: - Associations
extension SpendOffer {
    static let card = belongsTo(Card.self)
    static let pointType = belongsTo(PointType.self)

    var card: QueryInterfaceRequest<Card> {
        request(for: SpendOffer.card)
    }

    var pointType: QueryInterfaceRequest<PointType> {
        request(for: SpendOffer.pointType)
    }
}

// MARK: - Query Methods
extension SpendOffer {
    static func activeOffersForCard(_ db: Database, cardId: UUID, date: Date) throws -> [SpendOffer] {
        try SpendOffer
            .filter(Columns.cardId == cardId
                && Columns.isActive == true
                && Columns.startDate <= date
                && Columns.endDate >= date)
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

    func progressPercentage() -> Decimal? {
        switch offerType {
        case .percentageBack:
            guard let max = maxRewardAmount, let percentage = rewardPercentage, percentage > 0 else {
                return nil
            }
            let maxSpend = (max / percentage) * 100
            return maxSpend > 0 ? (currentSpend / maxSpend) * 100 : 0
        case .flatBonusSpendThreshold:
            guard let threshold = spendThreshold, threshold > 0 else { return nil }
            return (currentSpend / threshold) * 100
        case .flatBonusTransactionCount:
            guard let required = countRequired, required > 0 else { return nil }
            return (Decimal(currentCount) / Decimal(required)) * 100
        }
    }
}
