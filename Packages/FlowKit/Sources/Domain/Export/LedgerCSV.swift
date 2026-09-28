public import Foundation

/// RFC 4180 CSV of transactions — opens cleanly in Numbers, Excel and Google Sheets.
public enum LedgerCSV {
    public static let header = ["Date", "Type", "Merchant", "Category", "Account", "Amount", "Currency", "Note"]

    public static func make(_ transactions: some Sequence<LedgerTransaction>, snapshot: LedgerSnapshot, calendar: Calendar) -> String {
        let dateStyle = Date.ISO8601FormatStyle(dateSeparator: .dash, timeZone: calendar.timeZone).year().month().day()
        let digits = snapshot.currency.fractionDigits
        let amountStyle = Decimal.FormatStyle(locale: Locale(identifier: "en_US_POSIX")).precision(.fractionLength(digits)).grouping(.never)
        var lines = [header.map(escape).joined(separator: ",")]
        for transaction in transactions {
            let amount = transaction.signedAmount.decimalValue(fractionDigits: digits)
            let row = [
                transaction.date.formatted(dateStyle),
                transaction.kind == .income ? "Income" : "Expense",
                transaction.merchant,
                transaction.category.name,
                snapshot.accountsByID[transaction.accountID]?.name ?? "",
                amount.formatted(amountStyle),
                snapshot.profile.currencyCode,
                transaction.note,
            ]
            lines.append(row.map(escape).joined(separator: ","))
        }
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    /// Quotes fields containing separators, quotes or newlines, and defuses spreadsheet formula injection
    /// (a merchant named `=HYPERLINK(...)` must not execute when the file is opened).
    static func escape(_ field: String) -> String {
        var value = field
        if let first = value.first, "=+-@\t\r".contains(first), Double(value) == nil {
            value = "'" + value
        }
        guard value.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
