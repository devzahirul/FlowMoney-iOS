public import LedgerUI
public import SwiftUI
import Charts
import DesignSystem
import Domain
import FlowCore
import Observation
import Routing

@MainActor
@Observable
final class SpendingAnalyticsModel: LedgerObserving {
    var period = AnalyticsPeriod.month
    private(set) var breakdown: [CategorySpend] = []
    private(set) var series: [DatedAmount] = []
    private(set) var total = Money.zero
    private var snapshot: LedgerSnapshot?

    let context: LedgerContext
    var lastRevision: Int?

    init(context: LedgerContext) {
        self.context = context
    }

    func update(with snapshot: LedgerSnapshot) {
        self.snapshot = snapshot
        recompute()
    }

    func recompute() {
        guard let snapshot else { return }
        let now = context.now()
        let interval = period.interval(containing: now, calendar: context.calendar)
        breakdown = SpendingBreakdown.byCategory(in: snapshot, interval: interval, limit: 7)
        total = breakdown.sum(\.amount)
        series = SpendingBreakdown.series(in: snapshot, period: period, now: now, calendar: context.calendar)
    }
}

/// Screen 17 — where the money went, by category, for a week / month / year.
public struct SpendingAnalyticsView: View {
    @State private var model: SpendingAnalyticsModel

    public init(context: LedgerContext) {
        _model = State(initialValue: SpendingAnalyticsModel(context: context))
    }

    public var body: some View {
        ScreenScroll {
            PillPicker(AnalyticsPeriod.allCases, selection: $model.period) { $0.title }
                .accessibilityIdentifier("analytics.period")

            if model.breakdown.isEmpty {
                ContentUnavailableView("No spending", systemImage: "chart.pie", description: Text("Nothing spent in this period yet."))
            } else {
                SpendingDonut(breakdown: model.breakdown, total: model.total)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)

                VStack(spacing: 12) {
                    ForEach(model.breakdown) { spend in
                        NavigationLink(value: Route.transactions()) {
                            HStack(spacing: 12) {
                                IconBadge(spend.category.symbol, color: spend.category.color, size: 36)
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(spend.category.name).font(.subheadline.weight(.medium))
                                        Spacer()
                                        AmountText(spend.amount).font(.subheadline.weight(.semibold))
                                    }
                                    HStack(spacing: 8) {
                                        ProgressBar(fraction: spend.share, color: spend.category.color, height: 6)
                                        Text(spend.share, format: .percent.precision(.fractionLength(0)))
                                            .font(.caption).foregroundStyle(.secondary).frame(width: 36, alignment: .trailing)
                                    }
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityElement(children: .combine)
                    }
                }
                .card()

                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(model.period == .year ? "By month" : "By day")
                    Chart(model.series) { point in
                        BarMark(
                            x: .value("Date", point.date, unit: model.period == .year ? .month : .day),
                            y: .value("Spent", Double(point.amount.minorUnits) / 100)
                        )
                        .foregroundStyle(Theme.brand.gradient)
                        .cornerRadius(3)
                    }
                    .frame(height: 160)
                }
                .card()
            }
        }
        .navigationTitle("Spending Analytics")
        .onChange(of: model.period) { model.recompute() }
        .task { await model.observe() }
    }
}
