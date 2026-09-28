@testable import FlowCore
import Foundation
import Testing

@Suite("Money")
struct MoneyTests {
    @Test("Decimal input rounds half-even to the currency precision")
    func roundsBankers() throws {
        #expect(try Money(#require(Decimal(string: "0.125"))).minorUnits == 12)
        #expect(try Money(#require(Decimal(string: "0.135"))).minorUnits == 14)
        #expect(try Money(#require(Decimal(string: "19.99"))).minorUnits == 1999)
        #expect(try Money(#require(Decimal(string: "1500")), fractionDigits: 0).minorUnits == 1500)
    }

    @Test("Arithmetic is exact where Double is not")
    func exactArithmetic() {
        let tenCents = Money(minorUnits: 10)
        let twentyCents = Money(minorUnits: 20)
        #expect(tenCents + twentyCents == Money(minorUnits: 30))
        #expect((0 ..< 1000).map { _ in tenCents }.sum() == Money(minorUnits: 10000))
    }

    @Test("Fraction of zero total is zero, not NaN")
    func fractionOfZero() {
        #expect(Money(minorUnits: 500).fraction(of: .zero) == 0)
        #expect(Money(minorUnits: 250).fraction(of: Money(minorUnits: 1000)) == 0.25)
    }

    @Test("Encodes as a bare integer to match the Postgres bigint column")
    func codable() throws {
        let data = try JSONEncoder().encode(Money(minorUnits: 1234))
        #expect(String(data: data, encoding: .utf8) == "1234")
        #expect(try JSONDecoder().decode(Money.self, from: data) == Money(minorUnits: 1234))
    }

    @Test("Magnitude never traps on Int64.min")
    func magnitude() {
        #expect(Money(minorUnits: -500).magnitude == Money(minorUnits: 500))
        #expect(Money(minorUnits: .min).magnitude == Money(minorUnits: .max))
    }
}

@Suite("CurrencyFormat")
struct CurrencyFormatTests {
    let usd = CurrencyFormat(currencyCode: "USD", locale: Locale(identifier: "en_US"))

    @Test func formatsAndSigns() {
        #expect(usd.string(Money(minorUnits: 124_050)) == "$1,240.50")
        #expect(usd.signed(Money(minorUnits: 320_000)) == "+$3,200.00")
        #expect(usd.signed(Money(minorUnits: -520)) == "-$5.20")
        #expect(usd.whole(Money(minorUnits: 124_049)) == "$1,240") // whole units for headlines and axes
    }

    @Test("Zero-decimal currencies use whole units")
    func yen() {
        let yen = CurrencyFormat(currencyCode: "JPY", locale: Locale(identifier: "ja_JP"))
        #expect(yen.fractionDigits == 0)
        #expect(yen.parse(keypadInput: "1500") == Money(minorUnits: 1500))
    }

    @Test(arguments: [
        ("12.5", Int64?.some(1250)),
        ("0", 0),
        ("", nil),
        ("abc", nil),
        ("-3", nil),
    ])
    func parsesKeypadInput(input: String, expected: Int64?) {
        #expect(usd.parse(keypadInput: input)?.minorUnits == expected)
    }
}

@Suite("Free-typed amount parsing")
struct UserInputParsingTests {
    let usd = CurrencyFormat(currencyCode: "USD", locale: Locale(identifier: "en_US"))

    @Test(arguments: [
        ("12.50", Int64?.some(1250)),
        ("12,50", 1250),
        ("1,240.50", 124_050),
        ("1.240,50", 124_050),
        ("1,240", 124_000),
        ("$ 9.99", 999),
        ("", nil),
        ("abc", nil),
    ])
    func parses(input: String, expected: Int64?) {
        #expect(usd.parse(userInput: input)?.minorUnits == expected)
    }
}

@Suite("YearMonth")
struct YearMonthTests {
    @Test func normalisesOverflowingMonths() {
        #expect(YearMonth(year: 2026, month: 13) == YearMonth(year: 2027, month: 1))
        #expect(YearMonth(year: 2026, month: 0) == YearMonth(year: 2025, month: 12))
        #expect(YearMonth(year: 2026, month: -11) == YearMonth(year: 2025, month: 1))
    }

    @Test func trailingMonthsAreOldestFirst() {
        let months = YearMonth(year: 2026, month: 2).trailing(3)
        #expect(months == [YearMonth(year: 2025, month: 12), YearMonth(year: 2026, month: 1), YearMonth(year: 2026, month: 2)])
    }

    @Test func monthsBetween() {
        #expect(YearMonth(year: 2025, month: 11).months(to: YearMonth(year: 2026, month: 2)) == 3)
    }

    @Test("Interval spans the month in the calendar's time zone")
    func interval() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        let february = YearMonth(year: 2028, month: 2)
        #expect(february.dayCount(in: calendar) == 29)
        #expect(february.interval(in: calendar).duration == 29 * 86400)
    }
}

@Suite("Deterministic UUID")
struct DeterministicIDTests {
    @Test func sameInputsSameID() {
        let namespace = UUID()
        #expect(UUID(namespace: namespace, name: "2026-03-01") == UUID(namespace: namespace, name: "2026-03-01"))
        #expect(UUID(namespace: namespace, name: "2026-03-01") != UUID(namespace: namespace, name: "2026-04-01"))
        #expect(UUID(namespace: UUID(), name: "x") != UUID(namespace: UUID(), name: "x"))
    }

    @Test("Sets RFC version 5 and variant bits")
    func versionBits() {
        let id = UUID(namespace: UUID(), name: "a").uuidString
        let chars = Array(id)
        #expect(chars[14] == "5")
        #expect("89AB".contains(chars[19]))
    }
}
