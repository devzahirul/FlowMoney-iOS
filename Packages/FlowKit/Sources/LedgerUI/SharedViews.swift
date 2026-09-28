public import Domain
public import FlowCore
public import SwiftUI
import DesignSystem

public extension EnvironmentValues {
    /// Formatter for the ledger's currency — built once per currency change, shared by every row.
    @Entry var currency: CurrencyFormat = .usd
    /// When true, amounts render as "••••" (privacy mode).
    @Entry var hideAmounts = false
}

/// A money amount that respects privacy mode and uses tabular digits so columns line up.
public struct AmountText: View {
    public enum Style {
        case plain
        /// "+$3,200.00" in green / "-$5.20" in the primary color.
        case signed
        case whole
    }

    let money: Money
    let style: Style
    @Environment(\.currency) private var currency
    @Environment(\.hideAmounts) private var hideAmounts

    public init(_ money: Money, style: Style = .plain) {
        self.money = money
        self.style = style
    }

    public var body: some View {
        Text(hideAmounts ? "••••" : formatted)
            .monospacedDigit()
            .foregroundStyle(style == .signed && money.minorUnits > 0 ? Theme.income : Color.primary)
            .contentTransition(.numericText(value: Double(money.minorUnits)))
            .accessibilityLabel(hideAmounts ? "Hidden amount" : formatted)
    }

    private var formatted: String {
        switch style {
        case .plain: currency.string(money)
        case .signed: currency.signed(money)
        case .whole: currency.whole(money)
        }
    }
}

/// The transaction list row used on Home, Activity, Search, Calendar and Account detail.
public struct TransactionRow: View {
    let transaction: LedgerTransaction
    var subtitle: String?

    public init(_ transaction: LedgerTransaction, subtitle: String? = nil) {
        self.transaction = transaction
        self.subtitle = subtitle
    }

    public var body: some View {
        HStack(spacing: 12) {
            IconBadge(transaction.category.symbol, color: transaction.category.color)
            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.displayTitle)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text(subtitle ?? transaction.category.name)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            AmountText(transaction.signedAmount, style: .signed)
                .font(.body.weight(.semibold))
        }
        .padding(.vertical, 4)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Shows transaction details")
    }
}

/// "Today", "Yesterday", or "Mon, Mar 3" — list section headers.
public enum DayTitle {
    public static func title(for day: Date, now: Date, calendar: Calendar) -> String {
        if calendar.isDate(day, inSameDayAs: now) {
            return "Today"
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(day, inSameDayAs: yesterday) {
            return "Yesterday"
        }
        let sameYear = calendar.component(.year, from: day) == calendar.component(.year, from: now)
        let style = sameYear
            ? Date.FormatStyle.dateTime.weekday(.abbreviated).month(.abbreviated).day()
            : Date.FormatStyle.dateTime.month(.abbreviated).day().year()
        return day.formatted(style)
    }
}

public extension YearMonth {
    /// "March 2026".
    func title(in calendar: Calendar) -> String {
        firstDay(in: calendar).formatted(.dateTime.month(.wide).year())
    }

    /// "Mar".
    func shortTitle(in calendar: Calendar) -> String {
        firstDay(in: calendar).formatted(.dateTime.month(.abbreviated))
    }
}

/// Placeholder shown while the first snapshot loads (usually < 1 frame from disk).
public struct LoadingView: View {
    public init() {}

    public var body: some View {
        ProgressView()
            .controlSize(.large)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityLabel("Loading")
    }
}

/// Screen scaffold: grouped background, scrolling content with standard margins.
public struct ScreenScroll<Content: View>: View {
    let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                content
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(Theme.background)
    }
}

/// Shows a thrown error as a dismissible alert.
public struct ErrorAlert: ViewModifier {
    @Binding var message: String?

    public func body(content: Content) -> some View {
        content.alert(
            "Something went wrong",
            isPresented: Binding(get: { message != nil }, set: {
                if !$0 {
                    message = nil
                }
            }),
            actions: { Button("OK", role: .cancel) {} },
            message: { Text(message ?? "") }
        )
    }
}

public extension View {
    func errorAlert(_ message: Binding<String?>) -> some View {
        modifier(ErrorAlert(message: message))
    }
}
