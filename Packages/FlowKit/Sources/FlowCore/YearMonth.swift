public import Foundation

/// A calendar month, the unit budgets, reports and cash-flow charts are computed in.
public struct YearMonth: Hashable, Sendable, Comparable, Codable, CustomStringConvertible {
    public let year: Int
    public let month: Int

    public init(year: Int, month: Int) {
        // Normalise so `YearMonth(year: 2026, month: 13)` is January 2027.
        let zeroBased = year * 12 + (month - 1)
        self.year = zeroBased.floorDiv(12)
        self.month = zeroBased.floorMod(12) + 1
    }

    public init(_ date: Date, calendar: Calendar) {
        let parts = calendar.dateComponents([.year, .month], from: date)
        self.init(year: parts.year ?? 1970, month: parts.month ?? 1)
    }

    public func adding(months: Int) -> YearMonth {
        YearMonth(year: year, month: month + months)
    }

    public var previous: YearMonth {
        adding(months: -1)
    }

    public var next: YearMonth {
        adding(months: 1)
    }

    /// Number of months from `self` to `other` (positive when `other` is later).
    public func months(to other: YearMonth) -> Int {
        (other.year - year) * 12 + (other.month - month)
    }

    /// `[start, end)` of the month in `calendar`'s time zone.
    public func interval(in calendar: Calendar) -> DateInterval {
        let start = firstDay(in: calendar)
        let end = next.firstDay(in: calendar)
        return DateInterval(start: start, end: end)
    }

    public func firstDay(in calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: 1)) ?? .distantPast
    }

    public func dayCount(in calendar: Calendar) -> Int {
        calendar.range(of: .day, in: .month, for: firstDay(in: calendar))?.count ?? 30
    }

    /// The `count` months ending at (and including) `self`, oldest first.
    public func trailing(_ count: Int) -> [YearMonth] {
        (0 ..< max(count, 0)).reversed().map { adding(months: -$0) }
    }

    public static func < (lhs: YearMonth, rhs: YearMonth) -> Bool {
        (lhs.year, lhs.month) < (rhs.year, rhs.month)
    }

    public var description: String {
        String(format: "%04d-%02d", year, month)
    }
}

extension Int {
    func floorDiv(_ divisor: Int) -> Int {
        let quotient = self / divisor
        return (self % divisor != 0 && (self < 0) != (divisor < 0)) ? quotient - 1 : quotient
    }

    func floorMod(_ divisor: Int) -> Int {
        self - floorDiv(divisor) * divisor
    }
}
