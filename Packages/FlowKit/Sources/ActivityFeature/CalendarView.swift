public import LedgerUI
public import SwiftUI
import DesignSystem
import Domain
import FlowCore
import Observation
import Routing

@MainActor
@Observable
final class CalendarModel: LedgerObserving {
    var month: YearMonth
    var selectedDay: Date
    private(set) var totals: [Date: (income: Money, expense: Money)] = [:]
    private(set) var dayTransactions: [LedgerTransaction] = []
    private(set) var monthExpense = Money.zero
    private(set) var maxDailyExpense = Money.zero

    let context: LedgerContext
    var lastRevision: Int?
    private var snapshot: LedgerSnapshot?

    init(context: LedgerContext) {
        self.context = context
        month = context.currentMonth
        selectedDay = context.calendar.startOfDay(for: context.now())
    }

    var calendar: Calendar {
        context.calendar
    }

    func update(with snapshot: LedgerSnapshot) {
        self.snapshot = snapshot
        recompute()
    }

    func recompute() {
        guard let snapshot else { return }
        totals = TransactionQuery.dailyTotals(for: month, in: snapshot, calendar: calendar)
        monthExpense = totals.values.sum(\.expense)
        maxDailyExpense = totals.values.map(\.expense).max() ?? .zero
        let interval = calendar.dateInterval(of: .day, for: selectedDay) ?? DateInterval(start: selectedDay, duration: 86400)
        dayTransactions = Array(snapshot.transactions(in: interval))
    }

    func move(by months: Int) {
        month = month.adding(months: months)
        selectedDay = month.firstDay(in: calendar)
        recompute()
    }

    func select(_ day: Date) {
        selectedDay = day
        recompute()
    }

    /// Leading blanks + the month's days, laid out in weeks starting on the locale's first weekday.
    var gridDays: [Date?] {
        let first = month.firstDay(in: calendar)
        let weekday = calendar.component(.weekday, from: first)
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        let days = (0 ..< month.dayCount(in: calendar)).compactMap { calendar.date(byAdding: .day, value: $0, to: first) }
        return Array(repeating: nil, count: leading) + days.map(Optional.some)
    }

    var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let start = calendar.firstWeekday - 1
        return Array(symbols[start...] + symbols[..<start])
    }
}

/// Screen 22 — spending heat-map calendar with the selected day's transactions.
public struct CalendarView: View {
    @State private var model: CalendarModel

    public init(context: LedgerContext) {
        _model = State(initialValue: CalendarModel(context: context))
    }

    public var body: some View {
        ScreenScroll {
            VStack(spacing: 14) {
                HStack {
                    Button { model.move(by: -1) } label: { Image(systemName: "chevron.left") }
                        .accessibilityLabel("Previous month")
                    Spacer()
                    VStack(spacing: 2) {
                        Text(model.month.title(in: model.calendar)).font(.headline)
                        HStack(spacing: 4) {
                            Text("Spent")
                            AmountText(model.monthExpense)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { model.move(by: 1) } label: { Image(systemName: "chevron.right") }
                        .accessibilityLabel("Next month")
                }
                .font(.title3.weight(.semibold))
                .tint(Theme.brand)

                let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(Array(model.weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                        Text(symbol).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    }
                    ForEach(Array(model.gridDays.enumerated()), id: \.offset) { _, day in
                        if let day {
                            dayCell(day)
                        } else {
                            Color.clear.frame(height: 44)
                        }
                    }
                }
            }
            .card()

            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(model.selectedDay.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                if model.dayTransactions.isEmpty {
                    Text("No transactions on this day.").font(.subheadline).foregroundStyle(.secondary).card()
                } else {
                    VStack(spacing: 4) {
                        ForEach(model.dayTransactions) { transaction in
                            NavigationLink(value: Route.transaction(transaction.id)) {
                                TransactionRow(transaction)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .card(padding: 12)
                }
            }
        }
        .navigationTitle("Calendar")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.observe() }
    }

    private func dayCell(_ day: Date) -> some View {
        let expense = model.totals[day]?.expense ?? .zero
        let intensity = model.maxDailyExpense.isZero ? 0 : expense.fraction(of: model.maxDailyExpense)
        let isSelected = model.calendar.isDate(day, inSameDayAs: model.selectedDay)
        let isToday = model.calendar.isDateInToday(day)
        return Button {
            model.select(day)
        } label: {
            VStack(spacing: 3) {
                Text(day.formatted(.dateTime.day()))
                    .font(.subheadline.weight(isToday ? .bold : .regular))
                    .foregroundStyle(isSelected ? Theme.onBrand : .primary)
                Circle()
                    .fill(isSelected ? Theme.onBrand : Theme.expense.opacity(0.25 + 0.75 * intensity))
                    .frame(width: 5, height: 5)
                    .opacity(expense.isZero ? 0 : 1)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(isSelected ? Theme.brand : (isToday ? Theme.brandSoft : .clear), in: .rect(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(day.formatted(date: .complete, time: .omitted))
        .accessibilityValue(expense.isZero ? "No spending" : "Spent \(expense.minorUnits / 100)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
