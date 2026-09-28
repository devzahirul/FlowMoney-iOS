public import LedgerUI
public import SwiftUI
import DesignSystem
import Domain
import FlowCore
import Observation
import Routing

@MainActor
@Observable
final class MonthlyReportModel: LedgerObserving {
    var month: YearMonth
    private(set) var report: MonthlyReport?
    private var snapshot: LedgerSnapshot?

    let context: LedgerContext
    var lastRevision: Int?

    init(context: LedgerContext) {
        self.context = context
        month = context.currentMonth
    }

    func update(with snapshot: LedgerSnapshot) {
        self.snapshot = snapshot
        recompute()
    }

    func move(by months: Int) {
        let target = month.adding(months: months)
        guard target <= context.currentMonth else { return }
        month = target
        recompute()
    }

    var canGoForward: Bool {
        month < context.currentMonth
    }

    private func recompute() {
        guard let snapshot else { return }
        report = MonthlyReport.make(for: month, in: snapshot, now: context.now(), calendar: context.calendar)
    }
}

/// Screen 18 — the month in review.
public struct MonthlyReportView: View {
    @State private var model: MonthlyReportModel

    public init(context: LedgerContext) {
        _model = State(initialValue: MonthlyReportModel(context: context))
    }

    public var body: some View {
        ScreenScroll {
            HStack {
                Button { model.move(by: -1) } label: { Image(systemName: "chevron.left") }
                    .accessibilityLabel("Previous month")
                Spacer()
                Text(model.month.title(in: model.context.calendar)).font(.headline)
                Spacer()
                Button { model.move(by: 1) } label: { Image(systemName: "chevron.right") }
                    .disabled(!model.canGoForward)
                    .accessibilityLabel("Next month")
            }
            .tint(Theme.brand)

            if let report = model.report {
                HStack(spacing: 12) {
                    Image(systemName: (report.spendingChange ?? 0) <= 0 ? "chart.line.downtrend.xyaxis" : "chart.line.uptrend.xyaxis")
                        .font(.title)
                        .foregroundStyle(Theme.brand)
                    Text(report.headline).font(.headline)
                }
                .card()
                .background(Theme.brandSoft, in: .rect(cornerRadius: Theme.cornerRadius))

                VStack(alignment: .leading, spacing: 14) {
                    SectionHeader("Key highlights")
                    highlight(
                        "Total spending",
                        report.flow.expenses,
                        change: report.spendingChange,
                        positiveIsGood: false,
                        symbol: "cart.fill",
                        color: Theme.expense
                    )
                    Divider()
                    highlight(
                        "Total income",
                        report.flow.income,
                        change: report.incomeChange,
                        positiveIsGood: true,
                        symbol: "banknote.fill",
                        color: Theme.income
                    )
                    Divider()
                    highlight(
                        "Net cash flow",
                        report.flow.net,
                        change: report.netChange,
                        positiveIsGood: true,
                        symbol: "arrow.left.arrow.right",
                        color: Theme.brand
                    )
                }
                .card()

                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader("Top categories")
                    if report.topCategories.isEmpty {
                        Text("No spending this month.").foregroundStyle(.secondary)
                    }
                    ForEach(report.topCategories) { spend in
                        HStack(spacing: 12) {
                            IconBadge(spend.category.symbol, color: spend.category.color, size: 36)
                            Text(spend.category.name).font(.subheadline.weight(.medium))
                            Spacer()
                            AmountText(spend.amount).font(.subheadline.weight(.semibold))
                            Text(spend.share, format: .percent.precision(.fractionLength(0)))
                                .font(.caption).foregroundStyle(.secondary).frame(width: 36, alignment: .trailing)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .card()

                VStack(spacing: 0) {
                    LabeledContent("Daily average") { AmountText(report.dailyAverage) }.padding(16)
                    Divider()
                    LabeledContent("Transactions", value: "\(report.transactionCount)").padding(16)
                    if let largest = report.largestExpense {
                        Divider()
                        NavigationLink(value: Route.transaction(largest.id)) {
                            LabeledContent("Largest expense") {
                                HStack(spacing: 4) {
                                    Text(largest.displayTitle)
                                    AmountText(largest.amount).fontWeight(.semibold)
                                }
                            }
                            .padding(16)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .card(padding: 0)
            } else {
                LoadingView()
            }
        }
        .navigationTitle("Monthly Report")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(value: Route.export) { Image(systemName: "square.and.arrow.up") }
                    .accessibilityLabel("Export report")
            }
        }
        .task { await model.observe() }
    }

    // swiftlint:disable:next function_parameter_count
    private func highlight(
        _ title: String,
        _ amount: Money,
        change: Double?,
        positiveIsGood: Bool,
        symbol: String,
        color: Color
    ) -> some View {
        HStack(spacing: 12) {
            IconBadge(symbol, color: color, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                AmountText(amount).font(.headline)
                Text(title).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let change {
                ChangeBadge(change, positiveIsGood: positiveIsGood)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
