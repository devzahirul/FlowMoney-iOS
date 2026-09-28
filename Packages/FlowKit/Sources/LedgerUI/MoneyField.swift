public import FlowCore
public import SwiftUI
import DesignSystem

/// A decimal-pad amount field for forms (budgets, goals, subscriptions). Validates as you type.
public struct MoneyField: View {
    let title: String
    @Binding var text: String
    @Environment(\.currency) private var currency

    public init(_ title: String, text: Binding<String>) {
        self.title = title
        _text = text
    }

    public var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(currency.symbol).foregroundStyle(.secondary)
            TextField("0", text: $text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 140)
                .foregroundStyle(text.isEmpty || currency.parse(userInput: text) != nil ? Color.primary : Theme.expense)
        }
        .accessibilityElement(children: .combine)
    }
}

public extension CurrencyFormat {
    /// Text for pre-filling a `MoneyField` when editing ("1240.5").
    func editingText(_ money: Money) -> String {
        money.isZero ? "" : "\(money.decimalValue(fractionDigits: fractionDigits))"
    }
}
