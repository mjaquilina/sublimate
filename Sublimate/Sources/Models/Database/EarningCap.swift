import Foundation
import GRDB

struct EarningCap: Codable, Identifiable, FetchableRecord, PersistableRecord, Hashable {
    static let databaseTableName = "earning_caps"

    var id: UUID
    var name: String
    var maxSpend: Decimal
    var currentSpend: Decimal
    var startDate: Date
    var endDate: Date
    var createdAt: Date
    var updatedAt: Date

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let name = Column(CodingKeys.name)
        static let maxSpend = Column(CodingKeys.maxSpend)
        static let currentSpend = Column(CodingKeys.currentSpend)
        static let startDate = Column(CodingKeys.startDate)
        static let endDate = Column(CodingKeys.endDate)
        static let createdAt = Column(CodingKeys.createdAt)
        static let updatedAt = Column(CodingKeys.updatedAt)
    }

    init(id: UUID = UUID(), name: String, maxSpend: Decimal, currentSpend: Decimal = 0,
         startDate: Date, endDate: Date, createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.maxSpend = maxSpend
        self.currentSpend = currentSpend
        self.startDate = startDate
        self.endDate = endDate
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    mutating func willUpdate(_ db: Database, column: String) throws {
        updatedAt = Date()
    }

    // Helper properties
    var remainingSpend: Decimal {
        return max(0, maxSpend - currentSpend)
    }

    var progressPercentage: Decimal {
        guard maxSpend > 0 else { return 0 }
        return (currentSpend / maxSpend) * 100
    }

    var isActive: Bool {
        let now = Date()
        return now >= startDate && now <= endDate
    }

    var isFull: Bool {
        return currentSpend >= maxSpend
    }

    // Database queries
    static func findByID(_ db: Database, id: UUID) throws -> EarningCap? {
        try EarningCap.filter(Columns.id == id).fetchOne(db)
    }

    static func activeCaps(_ db: Database) throws -> [EarningCap] {
        let now = Date()
        return try EarningCap
            .filter(Columns.startDate <= now && Columns.endDate >= now)
            .fetchAll(db)
    }

    static func capsForCard(_ db: Database, cardId: UUID) throws -> [EarningCap] {
        // Get all earning rules for this card
        let rules = try EarningRule.activeRulesForCard(db, cardId: cardId)
        guard !rules.isEmpty else { return [] }

        let ruleIds = rules.map { $0.id }

        // Get all cap IDs linked to these rules
        let capIds = try EarningRuleCap
            .filter(ruleIds.contains(EarningRuleCap.Columns.earningRuleId))
            .fetchAll(db)
            .map { $0.earningCapId }

        guard !capIds.isEmpty else { return [] }

        // Fetch the caps
        return try EarningCap
            .filter(capIds.contains(EarningCap.Columns.id))
            .order(Columns.endDate.desc)
            .fetchAll(db)
    }
}

// Junction table for many-to-many relationship between earning rules and caps
struct EarningRuleCap: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "earning_rule_caps"

    var earningRuleId: UUID
    var earningCapId: UUID

    enum Columns {
        static let earningRuleId = Column(CodingKeys.earningRuleId)
        static let earningCapId = Column(CodingKeys.earningCapId)
    }

    // Fetch all caps for an earning rule
    static func capsForRule(_ db: Database, ruleId: UUID) throws -> [EarningCap] {
        let capIds = try EarningRuleCap
            .filter(Columns.earningRuleId == ruleId)
            .fetchAll(db)
            .map { $0.earningCapId }

        return try EarningCap
            .filter(capIds.contains(EarningCap.Columns.id))
            .fetchAll(db)
    }

    // Fetch all rules for a cap
    static func rulesForCap(_ db: Database, capId: UUID) throws -> [EarningRule] {
        let ruleIds = try EarningRuleCap
            .filter(Columns.earningCapId == capId)
            .fetchAll(db)
            .map { $0.earningRuleId }

        return try EarningRule
            .filter(ruleIds.contains(EarningRule.Columns.id))
            .fetchAll(db)
    }
}
