import Foundation

/// Type of spend offer
enum OfferType: String, Codable {
    case percentageBack = "percentage_back"
    case flatBonusSpendThreshold = "flat_bonus_spend_threshold"
    case flatBonusTransactionCount = "flat_bonus_transaction_count"
}
