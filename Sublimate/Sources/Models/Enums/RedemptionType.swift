import Foundation

/// Type of points redemption
enum RedemptionType: String, Codable {
    case giftCard = "gift_card"
    case travel = "travel"
    case statementCredit = "statement_credit"
    case merchandise = "merchandise"
    case transfer = "transfer"
    case other = "other"
}
