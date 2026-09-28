public import LedgerUI
public import SwiftUI
import Charts
import DesignSystem
import Domain
import FlowCore
import Observation

@MainActor
@Observable
final class NetWorthModel: LedgerObserving {
    enum Range: String, CaseIterable, Identifiable {
        case threeMonths = "3M", sixMonths = "6M", year = "1Y", all = "All"
        var id: Self {
            self
        }

        var months: Int {
            switch self {
            case .threeMonths: 3
            case .sixMonths: 6
            case .year: 12
            case .all: 60
            }
        }
    }

    var range = Range.sixMonths
    private(set) var summary: NetWorthSummary?
    private(set) var accounts: [(account: Account, balance: Money)] = []
    private var snapshot: LedgerSnapshot?

    let context: LedgerContext
    var lastRevision: Int?

    init(context: LedgerContext) {
        self.context = context
    }

    func update(with snapshot: LedgerSnapshot) {
        self.snapshot = snapshot
        accounts = snapshot.accounts.map { ($0, snapshot.balance(of: $0.id)) }.sorted { $0.1 > $1.1 }
        recompute()
    }

    func recompute() {
        guard let snapshot else { return }
        var months = range.months
        if range == .all, let oldest = snapshot.transactions.last?.date {
            months = max(2, YearMonth(oldest, calendar: context.calendar).months(to: context.currentMonth) + 1)
        }
        summary = NetWorth.summary(for: snapshot, months: months, now: context.now(), calendar: context.calendar)
    }

    var periodChange: Money {
        guard let history = summary?.history, let first = history.first, let last = history.last else { return .zero }
        return last.amount - first.amount
    }
}

/// Screen 19 — assets minus liabilities over time.
public struct NetWorthView: View {
    @State private var model: NetWorthModel

    public init(context: LedgerContext) {
        _model = State(initialValue: NetWorthModel(context: context))
    }

    public var body: some View {
        ScreenScroll {
            if let summary = model.summary {
                VStack(alignment: .leading, spacing: 6) {
                    AmountText(summary.total).font(.system(size: 40, weight: .bold, design: .rounded))
                    HStack(spacing: 6) {
                        AmountText(model.periodChange, style: .signed).font(.subheadline.weight(.semibold))
                        Text("over \(model.range.rawValue == "All" ? "all time" : model.range.rawValue)")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }

                VStack(spacing: 14) {
                    Chart(summary.history) { point in
                        LineMark(x: .value("Date", point.date), y: .value("Net worth", Double(point.amount.minorUnits) / 100))
                            .interpolationMethod(.monotone)
                            .foregroundStyle(Theme.brand)
                            .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                        AreaMark(x: .value("Date", point.date), y: .value("Net worth", Double(point.amount.minorUnits) / 100))
                            .interpolationMethod(.monotone)
                            .foregroundStyle(LinearGradient(
                                colors: [Theme.brand.opacity(0.25), .clear],
                                startPoint: .top,
                                endPoint: .bottom
                            ))
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .frame(height: 200)
                    .accessibilityLabel("Net worth over time")
                    Picker("Range", selection: $model.range) {
                        ForEach(NetWorthModel.Range.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                .card()

                VStack(spacing: 0) {
                    row("Assets", summary.assets, Theme.income, bold: true)
                    ForEach(summary.lines.filter { !$0.kind.isLiability }) { line in
                        row(line.kind.title, line.total, .secondary)
                    }
                    Divider().padding(.vertical, 6)
                    row("Liabilities", summary.liabilities, Theme.expense, bold: true)
                    ForEach(summary.lines.filter(\.kind.isLiability)) { line in
                        row(line.kind.title, line.total, .secondary)
                    }
                }
                .card()

                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader("Accounts")
                    ForEach(model.accounts, id: \.account.id) { item in
                        HStack(spacing: 12) {
                            IconBadge(item.account.kind.symbol, color: item.account.kind.color, size: 34)
                            Text(item.account.name).font(.subheadline)
                            Spacer()
                            AmountText(item.balance).font(.subheadline.weight(.semibold))
                                .foregroundStyle(item.balance.isNegative ? Theme.expense : .primary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .card()
            } else {
                LoadingView()
            }
        }
        .navigationTitle("Net Worth")
        .onChange(of: model.range) { model.recompute() }
        .task { await model.observe() }
    }

    private func row(_ title: String, _ amount: Money, _ color: Color, bold: Bool = false) -> some View {
        HStack {
            if bold {
                Circle().fill(color).frame(width: 8, height: 8)
            }
            Text(title).font(bold ? .subheadline.weight(.semibold) : .subheadline).foregroundStyle(bold ? .primary : .secondary)
            Spacer()
            AmountText(amount).font(bold ? .subheadline.weight(.semibold) : .subheadline)
        }
        .padding(.vertical, 5)
        .padding(.leading, bold ? 0 : 16)
        .accessibilityElement(children: .combine)
    }
}
