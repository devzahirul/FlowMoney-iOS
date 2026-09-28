import Domain
import FlowCore
import Foundation
import UIKit

enum ExportFormat: String, CaseIterable, Identifiable {
    case pdf = "PDF", csv = "CSV"
    var id: Self {
        self
    }

    var detail: String {
        switch self {
        case .pdf: "Best for reports and sharing"
        case .csv: "Best for spreadsheets"
        }
    }
}

enum ExportRange: String, CaseIterable, Identifiable {
    case thisMonth = "This month"
    case lastThreeMonths = "Last 3 months"
    case thisYear = "This year"
    case allTime = "All time"
    var id: Self {
        self
    }

    func interval(now: Date, calendar: Calendar) -> DateInterval {
        let month = YearMonth(now, calendar: calendar)
        let end = month.next.firstDay(in: calendar)
        switch self {
        case .thisMonth: return month.interval(in: calendar)
        case .lastThreeMonths: return DateInterval(start: month.adding(months: -2).firstDay(in: calendar), end: end)
        case .thisYear: return calendar.dateInterval(of: .year, for: now) ?? month.interval(in: calendar)
        case .allTime: return DateInterval(start: .distantPast, end: end)
        }
    }
}

/// Writes CSV / PDF reports to a temporary file for the share sheet. Runs off the main actor.
enum ReportExporter {
    static func export(
        format: ExportFormat,
        range: ExportRange,
        snapshot: LedgerSnapshot,
        now: Date,
        calendar: Calendar
    ) throws -> URL {
        let interval = range.interval(now: now, calendar: calendar)
        let transactions = Array(snapshot.transactions(in: interval))
        let stamp = now.formatted(.iso8601.year().month().day())
        let url = FileManager.default.temporaryDirectory
            .appending(
                path: "FlowMoney-\(range.rawValue.replacingOccurrences(of: " ", with: "-"))-\(stamp).\(format.rawValue.lowercased())"
            )
        switch format {
        case .csv:
            try Data(LedgerCSV.make(transactions, snapshot: snapshot, calendar: calendar).utf8).write(to: url, options: .atomic)
        case .pdf:
            try pdf(transactions: transactions, range: range, interval: interval, snapshot: snapshot, now: now).write(
                to: url,
                options: .atomic
            )
        }
        return url
    }

    // MARK: PDF

    private static let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792) // US Letter
    private static let margin: CGFloat = 48

    // swiftlint:disable:next function_body_length
    static func pdf(
        transactions: [LedgerTransaction],
        range: ExportRange,
        interval: DateInterval,
        snapshot: LedgerSnapshot,
        now: Date
    ) -> Data {
        let currency = snapshot.currency
        let income = transactions.filter { $0.kind == .income }.sum(\.amount)
        let expenses = transactions.filter { $0.kind == .expense }.sum(\.amount)
        var byCategory: [CategoryID: Money] = [:]
        for transaction in transactions where transaction.kind == .expense {
            byCategory[transaction.categoryID, default: .zero] += transaction.amount
        }
        let brand = UIColor(red: 0.08, green: 0.54, blue: 0.29, alpha: 1)

        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: {
            let format = UIGraphicsPDFRendererFormat()
            format.documentInfo = [kCGPDFContextTitle as String: "FlowMoney Report", kCGPDFContextCreator as String: "FlowMoney"]
            return format
        }())

        return renderer.pdfData { context in
            var cursorY = margin
            func newPageIfNeeded(_ height: CGFloat) {
                if cursorY + height > pageRect.height - margin {
                    context.beginPage()
                    cursorY = margin
                }
            }
            func draw(
                _ text: String,
                font: UIFont,
                color: UIColor = .black,
                x originX: CGFloat = margin,
                width: CGFloat? = nil,
                align: NSTextAlignment = .left
            ) {
                let style = NSMutableParagraphStyle()
                style.alignment = align
                style.lineBreakMode = .byTruncatingTail
                let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: style]
                let rect = CGRect(x: originX, y: cursorY, width: width ?? (pageRect.width - margin - originX), height: font.lineHeight + 2)
                (text as NSString).draw(in: rect, withAttributes: attributes)
            }

            context.beginPage()
            draw("FlowMoney", font: .systemFont(ofSize: 26, weight: .bold), color: brand)
            cursorY += 34
            let dates = interval.start == .distantPast
                ? "All time"
                : interval.start.formatted(date: .abbreviated, time: .omitted) + " – "
                + interval.end.addingTimeInterval(-1).formatted(date: .abbreviated, time: .omitted)
            draw("\(range.rawValue) · \(dates)", font: .systemFont(ofSize: 13), color: .darkGray)
            cursorY += 18
            draw(
                "Prepared for \(snapshot.profile.displayName) on \(now.formatted(date: .long, time: .omitted))",
                font: .systemFont(ofSize: 11),
                color: .gray
            )
            cursorY += 32

            let columnWidth = (pageRect.width - margin * 2) / 3
            for (index, item) in [("Income", income), ("Spending", expenses), ("Net", income - expenses)].enumerated() {
                let originX = margin + CGFloat(index) * columnWidth
                draw(item.0.uppercased(), font: .systemFont(ofSize: 10, weight: .semibold), color: .gray, x: originX, width: columnWidth)
            }
            cursorY += 14
            for (index, amount) in [income, expenses, income - expenses].enumerated() {
                let originX = margin + CGFloat(index) * columnWidth
                draw(currency.string(amount), font: .systemFont(ofSize: 18, weight: .bold), x: originX, width: columnWidth)
            }
            cursorY += 40

            draw("Spending by category", font: .systemFont(ofSize: 15, weight: .semibold))
            cursorY += 24
            for (category, amount) in byCategory.sorted(by: { $0.value > $1.value }) {
                newPageIfNeeded(20)
                draw(category.category.name, font: .systemFont(ofSize: 11))
                draw(currency.string(amount), font: .monospacedDigitSystemFont(ofSize: 11, weight: .regular), align: .right)
                cursorY += 18
            }
            cursorY += 20

            newPageIfNeeded(60)
            draw("Transactions (\(transactions.count))", font: .systemFont(ofSize: 15, weight: .semibold))
            cursorY += 24
            for transaction in transactions {
                newPageIfNeeded(18)
                draw(
                    transaction.date.formatted(.dateTime.month(.abbreviated).day()),
                    font: .systemFont(ofSize: 10),
                    color: .gray,
                    width: 60
                )
                draw(transaction.displayTitle, font: .systemFont(ofSize: 10), x: margin + 64, width: 220)
                draw(transaction.category.name, font: .systemFont(ofSize: 10), color: .gray, x: margin + 290, width: 120)
                draw(
                    currency.signed(transaction.signedAmount),
                    font: .monospacedDigitSystemFont(ofSize: 10, weight: .medium),
                    color: transaction.kind == .income ? brand : .black,
                    align: .right
                )
                cursorY += 16
            }
        }
    }
}
