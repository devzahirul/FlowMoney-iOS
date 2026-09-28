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
final class InsightsHubModel: LedgerObserving {
    private(set) var monthSpend = Money.zero
    private(set) var breakdown: [CategorySpend] = []
    private(set) var flow: MonthFlow?
    private(set) var netWorth = Money.zero
    private(set) var topInsight: Insight?

    let context: LedgerContext
    var lastRevision: Int?

    init(context: LedgerContext) {
        self.context = context
    }

    func update(with snapshot: LedgerSnapshot) {
        let now = context.now()
        let month = context.currentMonth
        breakdown = SpendingBreakdown.byCategory(in: snapshot, interval: month.interval(in: context.calendar), limit: 5)
        monthSpend = breakdown.sum(\.amount)
        flow = CashFlow.month(month, in: snapshot, calendar: context.calendar)
        netWorth = snapshot.totalBalance
        topInsight = InsightEngine.insights(for: snapshot, now: now, calendar: context.calendar).first
    }
}

/// "Insights" tab root: entry points to every analysis screen.
public struct InsightsHubView: View {
    @State private var model: InsightsHubModel

    public init(context: LedgerContext) {
        _model = State(initialValue: InsightsHubModel(context: context))
    }

    public var body: some View {
        ScreenScroll {
            if let insight = model.topInsight {
                NavigationLink(value: Route.insights) {
                    InsightCard(insight: insight)
                }
                .buttonStyle(.plain)
            }

            NavigationLink(value: Route.spendingAnalytics) {
                HStack(spacing: 16) {
                    SpendingDonut(breakdown: model.breakdown, total: model.monthSpend, size: 110)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Spending this month").font(.headline)
                        ForEach(model.breakdown.prefix(3)) { spend in
                            HStack(spacing: 6) {
                                Circle().fill(spend.category.color).frame(width: 8, height: 8)
                                Text(spend.category.name).font(.caption).lineLimit(1)
                                Spacer(minLength: 4)
                                Text(spend.share, format: .percent.precision(.fractionLength(0))).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .card()
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("insights.analytics")

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                tile("Cash Flow", "arrow.left.arrow.right", Theme.palette[2], route: .cashFlow) {
                    AmountText(model.flow?.net ?? .zero, style: .signed)
                }
                tile("Net Worth", "chart.line.uptrend.xyaxis", Theme.palette[4], route: .netWorth) {
                    AmountText(model.netWorth, style: .whole)
                }
                tile("Monthly Report", "doc.text.fill", Theme.palette[1], route: .monthlyReport) {
                    Text(model.context.currentMonth.title(in: model.context.calendar))
                }
                tile("Insights", "lightbulb.fill", Theme.palette[5], route: .insights) {
                    Text("Personal tips")
                }
            }
        }
        .navigationTitle("Insights")
        .task { await model.observe() }
    }

    private func tile(_ title: String, _ symbol: String, _ color: Color, route: Route, @ViewBuilder value: () -> some View) -> some View {
        NavigationLink(value: route) {
            VStack(alignment: .leading, spacing: 8) {
                IconBadge(symbol, color: color, size: 36)
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                value().font(.footnote).foregroundStyle(.secondary).lineLimit(1)
            }
            .card(padding: 14)
        }
        .buttonStyle(.plain)
    }
}

/// Donut with the total in the middle (screen 17), reused on the hub.
struct SpendingDonut: View {
    let breakdown: [CategorySpend]
    let total: Money
    var size: CGFloat = 220

    var body: some View {
        Chart(breakdown) { spend in
            SectorMark(angle: .value("Amount", spend.amount.minorUnits), innerRadius: .ratio(0.68), angularInset: 1.5)
                .foregroundStyle(spend.category.color)
                .cornerRadius(4)
        }
        .chartBackground { _ in
            VStack(spacing: 0) {
                AmountText(total, style: .whole)
                    .font(size > 150 ? .title.bold() : .subheadline.bold())
                    .minimumScaleFactor(0.5)
                if size > 150 {
                    Text("Total spending").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(size * 0.18)
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel("Spending by category")
        .accessibilityValue(breakdown.map { "\($0.category.name) \(Int(($0.share * 100).rounded())) percent" }.joined(separator: ", "))
    }
}

struct InsightCard: View {
    let insight: Insight

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            IconBadge(symbol, color: insight.tone.color, size: 40)
            VStack(alignment: .leading, spacing: 4) {
                Text(insight.title).font(.caption.weight(.semibold)).foregroundStyle(insight.tone.color)
                Text(insight.message).font(.subheadline.weight(.medium))
                if let tip = insight.tip {
                    Text(tip).font(.footnote).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .card()
        .accessibilityElement(children: .combine)
    }

    private var symbol: String {
        switch insight.kind {
        case .spending: "cart.fill"
        case .saving: "banknote.fill"
        case .goal: "target"
        case .subscription: "play.rectangle.fill"
        case .budget: "chart.pie.fill"
        }
    }
}
