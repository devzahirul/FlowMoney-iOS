public import Foundation

/// An exact amount of money in the ledger's currency, stored as integer minor units (cents).
///
/// Why not `Double`: 0.1 + 0.2 != 0.3. Why not `Decimal`: it is 20 bytes, slower to sum and awkward to
/// persist. An `Int64` of cents is exact, sums in a single instruction, and maps 1:1 to Postgres `bigint`.
/// The ledger is single-currency (see ADR-0004), so the currency lives on the profile, not on every amount.
public struct Money: Hashable, Sendable, Comparable, Codable {
    public var minorUnits: Int64

    public init(minorUnits: Int64) {
        self.minorUnits = minorUnits
    }

    public static let zero = Money(minorUnits: 0)

    /// Builds an amount from a decimal major-unit value, rounding half-even to the currency's precision.
    public init(_ major: Decimal, fractionDigits: Int = 2) {
        var scaled = major * Decimal(sign: .plus, exponent: fractionDigits, significand: 1)
        var rounded = Decimal()
        NSDecimalRound(&rounded, &scaled, 0, .bankers)
        minorUnits = NSDecimalNumber(decimal: rounded).int64Value
    }

    /// The amount in major units (e.g. dollars) as an exact `Decimal`.
    public func decimalValue(fractionDigits: Int = 2) -> Decimal {
        Decimal(minorUnits) / Decimal(sign: .plus, exponent: fractionDigits, significand: 1)
    }

    public var isZero: Bool {
        minorUnits == 0
    }

    public var isNegative: Bool {
        minorUnits < 0
    }

    public var magnitude: Money {
        Money(minorUnits: minorUnits == .min ? .max : abs(minorUnits))
    }

    public static func < (lhs: Money, rhs: Money) -> Bool {
        lhs.minorUnits < rhs.minorUnits
    }

    public static func + (lhs: Money, rhs: Money) -> Money {
        Money(minorUnits: lhs.minorUnits + rhs.minorUnits)
    }

    public static func - (lhs: Money, rhs: Money) -> Money {
        Money(minorUnits: lhs.minorUnits - rhs.minorUnits)
    }

    public static prefix func - (value: Money) -> Money {
        Money(minorUnits: -value.minorUnits)
    }

    public static func += (lhs: inout Money, rhs: Money) {
        lhs.minorUnits += rhs.minorUnits
    }

    public static func -= (lhs: inout Money, rhs: Money) {
        lhs.minorUnits -= rhs.minorUnits
    }

    public static func * (lhs: Money, rhs: Int) -> Money {
        Money(minorUnits: lhs.minorUnits * Int64(rhs))
    }

    /// `self / total` as a fraction, `0` when `total` is zero. Used for progress bars and shares.
    public func fraction(of total: Money) -> Double {
        guard total.minorUnits != 0 else { return 0 }
        return Double(minorUnits) / Double(total.minorUnits)
    }

    /// A bare number in JSON keeps the wire format identical to the Postgres `bigint` column.
    public init(from decoder: any Decoder) throws {
        minorUnits = try decoder.singleValueContainer().decode(Int64.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(minorUnits)
    }
}

public extension Sequence {
    /// Sums the money values produced by `transform` without intermediate arrays.
    func sum(_ transform: (Element) throws -> Money) rethrows -> Money {
        var total = Money.zero
        for element in self {
            total += try transform(element)
        }
        return total
    }
}

public extension Sequence<Money> {
    func sum() -> Money {
        sum { $0 }
    }
}
