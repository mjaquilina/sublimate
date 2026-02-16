import Foundation

/// Application-wide constants
enum Constants {
    // MARK: - App Info
    static let appName = "Sublimate"
    static let appVersion = "1.0.0"

    // MARK: - Date Formats
    enum DateFormats {
        static let shortDate = "MM/dd/yyyy"
        static let mediumDate = "MMM d, yyyy"
        static let longDate = "MMMM d, yyyy"
        static let iso8601 = "yyyy-MM-dd"
    }

    // MARK: - Database
    enum Database {
        static let fileName = "sublimate.db"
        static let appSupportFolder = "Sublimate"
    }

    // MARK: - YNAB
    enum YNAB {
        static let baseURL = "https://api.ynab.com/v1"
        static let tokenLength = 64
    }

    // MARK: - AI Insights
    enum AIInsights {
        static let defaultDaysForOptimizations = 30
        static let defaultExpiringDaysThreshold = 14
        static let defaultSpendingPatternMonths = 3
    }

    // MARK: - UI
    enum UI {
        static let defaultPadding: CGFloat = 16
        static let smallPadding: CGFloat = 8
        static let largePadding: CGFloat = 24

        static let cornerRadius: CGFloat = 8
        static let shadowRadius: CGFloat = 4

        static let minimumWindowWidth: CGFloat = 900
        static let minimumWindowHeight: CGFloat = 600
    }

    // MARK: - Formatting
    enum Formatting {
        static let currencySymbol = "$"
        static let percentSymbol = "%"
        static let decimalPlaces = 2
    }
}
