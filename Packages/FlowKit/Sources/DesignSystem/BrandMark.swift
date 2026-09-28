public import SwiftUI

/// The FlowMoney logo: a leaf on the brand gradient. Drawn in code so it scales crisply at any size.
public struct BrandMark: View {
    var size: CGFloat

    public init(size: CGFloat = 72) {
        self.size = size
    }

    public var body: some View {
        Image(systemName: "leaf.fill")
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Theme.heroGradient, in: .rect(cornerRadius: size * 0.28))
            .shadow(color: Theme.brand.opacity(0.35), radius: size * 0.15, y: size * 0.08)
            .accessibilityHidden(true)
    }
}

/// "FlowMoney" in the two-tone wordmark.
public struct Wordmark: View {
    public init() {}

    public var body: some View {
        (Text("Flow").foregroundStyle(Color.primary) + Text("Money").foregroundStyle(Theme.brand))
            .font(.system(.largeTitle, design: .rounded, weight: .bold))
            .accessibilityLabel("FlowMoney")
    }
}
