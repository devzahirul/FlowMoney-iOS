public import SwiftUI

/// Pure keypad input logic (screen 8/9), unit-tested: digits, one decimal point, at most `maxFractionDigits`
/// decimals, no leading zeros, and a length cap so the value can't overflow.
public struct KeypadInput: Equatable, Sendable {
    public private(set) var text: String
    public let maxFractionDigits: Int
    public static let maxIntegerDigits = 9

    public init(text: String = "", maxFractionDigits: Int = 2) {
        self.text = text
        self.maxFractionDigits = maxFractionDigits
    }

    public enum Key: Hashable, Sendable {
        case digit(Int)
        case decimal
        case backspace
    }

    public mutating func press(_ key: Key) {
        switch key {
        case let .digit(value):
            let parts = text.split(separator: ".", omittingEmptySubsequences: false)
            if parts.count == 2 {
                guard parts[1].count < maxFractionDigits else { return }
            } else {
                guard text.count < Self.maxIntegerDigits else { return }
                if text == "0" {
                    text = String(value)
                    return
                }
            }
            text.append(String(value))
        case .decimal:
            guard maxFractionDigits > 0, !text.contains(".") else { return }
            text = (text.isEmpty ? "0" : text) + "."
        case .backspace:
            if !text.isEmpty {
                text.removeLast()
            }
        }
    }

    /// What the big amount label shows ("0" when empty).
    public var display: String {
        text.isEmpty ? "0" : text
    }
}

/// The on-screen number pad.
public struct KeypadView: View {
    @Binding var input: KeypadInput

    public init(input: Binding<KeypadInput>) {
        _input = input
    }

    private let rows: [[KeypadInput.Key]] = [
        [.digit(1), .digit(2), .digit(3)],
        [.digit(4), .digit(5), .digit(6)],
        [.digit(7), .digit(8), .digit(9)],
        [.decimal, .digit(0), .backspace],
    ]

    public var body: some View {
        Grid(horizontalSpacing: 10, verticalSpacing: 10) {
            ForEach(rows, id: \.self) { row in
                GridRow {
                    ForEach(row, id: \.self) { key in
                        Button {
                            input.press(key)
                        } label: {
                            label(for: key)
                                .font(.title2.weight(.medium))
                                .frame(maxWidth: .infinity, minHeight: 50)
                                .background(Theme.card, in: .rect(cornerRadius: 14))
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .disabled(key == .decimal && input.maxFractionDigits == 0)
                        .accessibilityLabel(accessibilityLabel(for: key))
                        .accessibilityIdentifier(identifier(for: key))
                    }
                }
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: input)
    }

    @ViewBuilder
    private func label(for key: KeypadInput.Key) -> some View {
        switch key {
        case let .digit(value): Text("\(value)")
        case .decimal: Text(".")
        case .backspace: Image(systemName: "delete.left")
        }
    }

    private func identifier(for key: KeypadInput.Key) -> String {
        switch key {
        case let .digit(value): "keypad.\(value)"
        case .decimal: "keypad.decimal"
        case .backspace: "keypad.backspace"
        }
    }

    private func accessibilityLabel(for key: KeypadInput.Key) -> String {
        switch key {
        case let .digit(value): "\(value)"
        case .decimal: "Decimal point"
        case .backspace: "Delete"
        }
    }
}
