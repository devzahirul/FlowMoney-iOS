public import LedgerUI
public import SwiftUI
import Charts
import DesignSystem
import Domain
import FlowCore
import Observation

@MainActor
@Observable
final class CashFlowModel: LedgerObserving {
    private(set) var flows: [MonthFlow] = []
    private(set) var current: MonthFlow?

    let context: LedgerContext
    var lastRevision: Int?

    init(context: LedgerContext) {
        self.context = context
    }

    func update(with snapshot: LedgerSnapshot) {
        flows = CashFlow.trailing(6, endingAt: context.currentMonth, in: snapshot, calendar: context.calendar)
        current = flows.last
    }

    var averageNet: Money {
        guard !flows.isEmpty else { return .zero }
        return Money(minorUnits: flows.sum(\.net).minorUnits / Int64(flows.count))
    }
}

/// Screen 16 — income vs spending, month by month.
public struct CashFlowView: View {
    @State private var model: CashFlowModel

    public init(context: LedgerContext) {
        _model = State(initialValue: CashFlowModel(context: context))
    }

    public var body: some View {
        ScreenScroll {
            if let current = model.current {
                VStack(spacing: 4) {
                    AmountText(current.net, style: .signed)
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                    Text("Net cash flow this month").font(.subheadline).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)

                VStack(alignment: .leading, spacing: 14) {
                    Chart {
                        ForEach(model.flows) { flow in
                            BarMark(
                                x: .value("Month", flow.month.shortTitle(in: model.context.calendar)),
                                y: .value("Amount", Double(flow.income.minorUnits) / 100)
                            )
                            .foregroundStyle(by: .value("Type", "Income"))
                            .position(by: .value("Type", "Income"))
                            .cornerRadius(4)
                            BarMark(
                                x: .value("Month", flow.month.shortTitle(in: model.context.calendar)),
                                y: .value("Amount", Double(flow.expenses.minorUnits) / 100)
                            )
                            .foregroundStyle(by: .value("Type", "Expenses"))
                            .position(by: .value("Type", "Expenses"))
                            .cornerRadius(4)
                        }
                    }
                    .chartForegroundStyleScale(["Income": Theme.income, "Expenses": Theme.expense.opacity(0.8)])
                    .chartLegend(position: .top, alignment: .leading)
                    .frame(height: 220)
                    .accessibilityLabel("Income and expenses for the last six months")

                    HStack {
                        legendValue("Income", current.income, Theme.income)
                        Spacer()
                        legendValue("Expenses", current.expenses, Theme.expense)
                        Spacer()
                        legendValue("Saved", Money(minorUnits: max(0, current.net.minorUnits)), Theme.brand)
                    }
                }
                .card()

                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader("Monthly trend")
                    Chart(model.flows) { flow in
                        LineMark(
                            x: .value("Month", flow.month.shortTitle(in: model.context.calendar)),
                            y: .value("Net", Double(flow.net.minorUnits) / 100)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(Theme.brand)
                        .symbol(.circle)
                        AreaMark(
                            x: .value("Month", flow.month.shortTitle(in: model.context.calendar)),
                            y: .value("Net", Double(flow.net.minorUnits) / 100)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(Theme.brand.opacity(0.12))
                    }
                    .frame(height: 160)
                    HStack(spacing: 4) {
                        Text("6-month average:")
                        AmountText(model.averageNet, style: .signed).fontWeight(.semibold)
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
                .card()
            } else {
                LoadingView()
            }
        }
        .navigationTitle("Cash Flow")
        .task { await model.observe() }
    }

    private func legendValue(_ title: String, _ amount: Money, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(title).font(.caption).foregroundStyle(.secondary)
            }
            AmountText(amount, style: .whole).font(.subheadline.weight(.semibold))
        }
        .accessibilityElement(children: .combine)
    }
}
