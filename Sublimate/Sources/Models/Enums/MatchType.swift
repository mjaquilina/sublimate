import Foundation

/// Type of matching criteria for earning rules, spend offers, and rebates
enum MatchType: String, Codable {
    case vendor = "vendor"
    case category = "category"
    case allSpend = "all_spend"
    case allOnline = "all_online"
}
