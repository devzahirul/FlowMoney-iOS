public import SwiftUI

/// Rounded text field with a leading icon, used on the auth screens.
public struct FormField: View {
    let title: String
    @Binding var text: String
    let symbol: String?

    public init(_ title: String, text: Binding<String>, symbol: String? = nil) {
        self.title = title
        _text = text
        self.symbol = symbol
    }

    public var body: some View {
        HStack(spacing: 10) {
            if let symbol {
                Image(systemName: symbol).foregroundStyle(.secondary).frame(width: 22).accessibilityHidden(true)
            }
            TextField(title, text: $text)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 52)
        .background(Theme.card, in: .rect(cornerRadius: 14))
    }
}

/// Password field with a show/hide toggle.
public struct SecureFormField: View {
    let title: String
    @Binding var text: String
    @State private var isRevealed = false

    public init(_ title: String, text: Binding<String>) {
        self.title = title
        _text = text
    }

    public var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock").foregroundStyle(.secondary).frame(width: 22).accessibilityHidden(true)
            Group {
                if isRevealed {
                    TextField(title, text: $text)
                } else {
                    SecureField(title, text: $text)
                }
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            Button {
                isRevealed.toggle()
            } label: {
                Image(systemName: isRevealed ? "eye.slash" : "eye").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isRevealed ? "Hide password" : "Show password")
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 52)
        .background(Theme.card, in: .rect(cornerRadius: 14))
    }
}
