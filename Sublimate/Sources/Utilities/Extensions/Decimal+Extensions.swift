import Foundation

extension Decimal {
    /// Parse a user-entered numeric string, stripping grouping separators (commas)
    static func fromUserInput(_ string: String) -> Decimal? {
        let cleaned = string.replacingOccurrences(of: ",", with: "")
        return Decimal(string: cleaned)
    }

    /// Format as currency (e.g., "$1,234.56")
    func toCurrency() -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: self as NSDecimalNumber) ?? "$0.00"
    }

    /// Format as percentage (e.g., "12.5%")
    func toPercentage(decimals: Int = 1) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = decimals
        formatter.maximumFractionDigits = decimals
        let numberString = formatter.string(from: self as NSDecimalNumber) ?? "0"
        return "\(numberString)%"
    }

    /// Format as plain number with optional decimals
    func toFormattedString(decimals: Int = 2) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = decimals
        formatter.maximumFractionDigits = decimals
        return formatter.string(from: self as NSDecimalNumber) ?? "0"
    }

    /// Round to specified decimal places
    func rounded(to places: Int) -> Decimal {
        var result = self
        var rounded = Decimal()
        NSDecimalRound(&rounded, &result, places, .plain)
        return rounded
    }

    /// Check if value is effectively zero
    var isZero: Bool {
        return self == 0
    }

    /// Check if value is positive
    var isPositive: Bool {
        return self > 0
    }

    /// Check if value is negative
    var isNegative: Bool {
        return self < 0
    }

    /// Absolute value
    var absolute: Decimal {
        return self < 0 ? -self : self
    }
}

// Decimal already has built-in initializers for Int and Double
// No need for custom extensions here
