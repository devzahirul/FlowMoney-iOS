public import SwiftUI

// MARK: - Card

public struct CardModifier: ViewModifier {
    var padding: CGFloat

    public func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: .rect(cornerRadius: Theme.cornerRadius))
    }
}

public extension View {
    /// The rounded "card" surface used throughout the app.
    func card(padding: CGFloat = 16) -> some View {
        modifier(CardModifier(padding: padding))
    }
}

// MARK: - Icon badge

/// An SF Symbol on a tinted rounded square — category, account and goal icons.
public struct IconBadge: View {
    let symbol: String
    let color: Color
    var size: CGFloat

    public init(_ symbol: String, color: Color, size: CGFloat = 40) {
        self.symbol = symbol
        self.color = color
        self.size = size
    }

    public var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(color.opacity(0.15), in: .rect(cornerRadius: size * 0.3))
            .accessibilityHidden(true)
    }
}

/// Initial-letter avatar for merchants and subscriptions (no third-party logos needed).
public struct MonogramBadge: View {
    let text: String
    var size: CGFloat

    public init(_ text: String, size: CGFloat = 40) {
        self.text = text
        self.size = size
    }

    public var body: some View {
        let color = StableColor.color(for: text)
        Text(text.first.map { String($0).uppercased() } ?? "?")
            .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color.gradient, in: .rect(cornerRadius: size * 0.3))
            .accessibilityHidden(true)
    }
}

// MARK: - Progress

public struct ProgressBar: View {
    let fraction: Double
    let color: Color
    var height: CGFloat

    public init(fraction: Double, color: Color = Theme.brand, height: CGFloat = 8) {
        self.fraction = fraction
        self.color = color
        self.height = height
    }

    public var body: some View {
        Capsule()
            .fill(color.opacity(0.15))
            .frame(height: height)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule()
                        .fill(color)
                        .frame(width: proxy.size.width * min(max(fraction, 0), 1))
                }
            }
            .clipShape(Capsule())
            .animation(.snappy, value: fraction)
            .accessibilityElement()
            .accessibilityValue(Text(fraction, format: .percent.precision(.fractionLength(0))))
    }
}

public struct ProgressRing: View {
    let fraction: Double
    let color: Color
    var lineWidth: CGFloat

    public init(fraction: Double, color: Color = Theme.brand, lineWidth: CGFloat = 8) {
        self.fraction = fraction
        self.color = color
        self.lineWidth = lineWidth
    }

    public var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.15), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(fraction, 0), 1))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .animation(.snappy, value: fraction)
        .accessibilityElement()
        .accessibilityValue(Text(fraction, format: .percent.precision(.fractionLength(0))))
    }
}

// MARK: - Section header

public struct SectionHeader<Trailing: View>: View {
    let title: String
    let trailing: Trailing

    public init(_ title: String, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.title = title
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.headline)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            trailing.font(.subheadline.weight(.medium)).tint(Theme.brand)
        }
    }
}

// MARK: - Buttons

public struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Theme.onBrand)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(Theme.brand.opacity(isEnabled ? 1 : 0.4), in: .rect(cornerRadius: 16))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

public struct SecondaryButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Theme.brand)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(Theme.brandSoft, in: .rect(cornerRadius: 16))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

public extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle {
        PrimaryButtonStyle()
    }
}

public extension ButtonStyle where Self == SecondaryButtonStyle {
    static var secondary: SecondaryButtonStyle {
        SecondaryButtonStyle()
    }
}

// MARK: - Pills (segmented)

/// Capsule segmented control matching the design (Expense | Income, Week | Month | Year).
public struct PillPicker<Value: Hashable>: View {
    let options: [Value]
    @Binding var selection: Value
    let title: (Value) -> String

    public init(_ options: [Value], selection: Binding<Value>, title: @escaping (Value) -> String) {
        self.options = options
        _selection = selection
        self.title = title
    }

    public var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.self) { option in
                let isSelected = option == selection
                Button {
                    selection = option
                } label: {
                    Text(title(option))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isSelected ? Theme.onBrand : .secondary)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background(isSelected ? Theme.brand : .clear, in: .capsule)
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Theme.card, in: .capsule)
        .sensoryFeedback(.selection, trigger: selection)
        .animation(.snappy(duration: 0.2), value: selection)
    }
}

// MARK: - Change badge

/// "+12.5%" / "-4%" pill, colored by whether the change is good.
public struct ChangeBadge: View {
    let change: Double
    let positiveIsGood: Bool

    public init(_ change: Double, positiveIsGood: Bool = true) {
        self.change = change
        self.positiveIsGood = positiveIsGood
    }

    public var body: some View {
        let isGood = (change >= 0) == positiveIsGood
        Label {
            Text(abs(change), format: .percent.precision(.fractionLength(0 ... 1)))
        } icon: {
            Image(systemName: change >= 0 ? "arrow.up.right" : "arrow.down.right")
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(isGood ? Theme.income : Theme.expense)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background((isGood ? Theme.income : Theme.expense).opacity(0.12), in: .capsule)
        .accessibilityLabel(Text("\(change >= 0 ? "Up" : "Down") \(abs(change), format: .percent.precision(.fractionLength(0)))"))
    }
}

// MARK: - Inline error

public struct ErrorBanner: View {
    let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var body: some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.footnote.weight(.medium))
            .foregroundStyle(Theme.expense)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.expense.opacity(0.1), in: .rect(cornerRadius: Theme.smallRadius))
            .accessibilityAddTraits(.isStaticText)
    }
}
