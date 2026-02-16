import Foundation

extension Date {
    /// Format date as short string (e.g., "1/15/24")
    func toShortString() -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter.string(from: self)
    }

    /// Format date as medium string (e.g., "Jan 15, 2024")
    func toMediumString() -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: self)
    }

    /// Get start of day
    func startOfDay() -> Date {
        return Calendar.current.startOfDay(for: self)
    }

    /// Get end of day
    func endOfDay() -> Date {
        var components = DateComponents()
        components.day = 1
        components.second = -1
        return Calendar.current.date(byAdding: components, to: startOfDay())!
    }

    /// Get start of month
    func startOfMonth() -> Date {
        let components = Calendar.current.dateComponents([.year, .month], from: self)
        return Calendar.current.date(from: components)!
    }

    /// Get end of month
    func endOfMonth() -> Date {
        var components = DateComponents()
        components.month = 1
        components.second = -1
        return Calendar.current.date(byAdding: components, to: startOfMonth())!
    }

    /// Get date N days ago
    func daysAgo(_ days: Int) -> Date {
        return Calendar.current.date(byAdding: .day, value: -days, to: self)!
    }

    /// Get date N days from now
    func daysFromNow(_ days: Int) -> Date {
        return Calendar.current.date(byAdding: .day, value: days, to: self)!
    }

    /// Days between this date and another
    func daysBetween(_ other: Date) -> Int {
        let components = Calendar.current.dateComponents([.day], from: self, to: other)
        return components.day ?? 0
    }

    /// Check if date is in the past
    var isPast: Bool {
        return self < Date()
    }

    /// Check if date is in the future
    var isFuture: Bool {
        return self > Date()
    }

    /// Check if date is today
    var isToday: Bool {
        return Calendar.current.isDateInToday(self)
    }

    /// Check if date is in this month
    var isThisMonth: Bool {
        let now = Date()
        return Calendar.current.isDate(self, equalTo: now, toGranularity: .month)
    }
}
