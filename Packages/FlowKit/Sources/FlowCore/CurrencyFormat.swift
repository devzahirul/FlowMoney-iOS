public import Foundation

/// Formats and parses `Money` for one currency + locale.
///
/// `FormatStyle` values are cheap to copy but expensive to create, and SwiftUI rebuilds rows constantly,
/// so the app builds one `CurrencyFormat` per currency change and shares it through the environment.
public struct CurrencyFormat: Sendable, Hashable {
    public let currencyCode: String
    public let locale: Locale
    public let fractionDigits: Int

    private let style: Decimal.FormatStyle.Currency
    private let compactStyle: Decimal.FormatStyle.Currency

    public init(currencyCode: String, locale: Locale = .autoupdatingCurrent) {
        self.currencyCode = currencyCode
        self.locale = locale
        fractionDigits = Self.fractionDigits(for: currencyCode)
        style = .currency(code: currencyCode).locale(locale)
        compactStyle = .currency(code: currencyCode).locale(locale).precision(.fractionLength(0))
    }

    /// "$1,240.50", "-$15.99".
    public func string(_ money: Money) -> String {
        money.decimalValue(fractionDigits: fractionDigits).formatted(style)
    }

    /// "+$3,200.00" for income, "-$5.20" for spending.
    public func signed(_ money: Money) -> String {
        let text = string(money)
        return money.minorUnits > 0 ? "+" + text : text
    }

    /// "$1,240" — whole units, for chart axes and big headline numbers.
    public func whole(_ money: Money) -> String {
        money.decimalValue(fractionDigits: fractionDigits).formatted(compactStyle)
    }

    /// Parses keypad input such as "12.5" into money, `nil` when it is not a valid non-negative amount.
    public func parse(keypadInput input: String) -> Money? {
        guard !input.isEmpty, let decimal = Decimal(string: input, locale: Locale(identifier: "en_US_POSIX")),
              decimal >= 0 else { return nil }
        return Money(decimal, fractionDigits: fractionDigits)
    }

    /// Parses free-typed amounts from a decimal-pad text field: accepts "12.50", "12,50" (comma-decimal
    /// locales) and "1,240.50"; rejects negatives and garbage. `nil` when it isn't a valid amount.
    public func parse(userInput input: String) -> Money? {
        var text = input.filter { $0.isNumber || $0 == "." || $0 == "," }
        guard !text.isEmpty else { return nil }
        if let lastSeparator = text.lastIndex(where: { $0 == "." || $0 == "," }) {
            let fraction = text[text.index(after: lastSeparator)...]
            // A final separator followed by 1…digits digits is the decimal point; the others are grouping.
            if (1 ... max(fractionDigits, 1)).contains(fraction.count), fractionDigits > 0 {
                let integer = text[..<lastSeparator].filter(\.isNumber)
                text = integer + "." + fraction
            } else {
                text = text.filter(\.isNumber)
            }
        }
        return parse(keypadInput: text)
    }

    /// The currency symbol for this locale, e.g. "$" or "€".
    public var symbol: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        formatter.locale = locale
        return formatter.currencySymbol
    }

    static func fractionDigits(for code: String) -> Int {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        return formatter.maximumFractionDigits
    }

    public static func == (lhs: CurrencyFormat, rhs: CurrencyFormat) -> Bool {
        lhs.currencyCode == rhs.currencyCode && lhs.locale == rhs.locale
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(currencyCode)
        hasher.combine(locale)
    }

    public static let usd = CurrencyFormat(currencyCode: "USD", locale: Locale(identifier: "en_US"))

    /// Currencies offered in Settings. Amounts are not converted when the currency changes (single-currency ledger).
    public static let supportedCodes = ["USD", "EUR", "GBP", "CAD", "AUD", "JPY", "INR", "BDT", "SGD", "AED"]
}
