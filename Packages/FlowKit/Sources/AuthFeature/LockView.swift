public import Domain
public import SwiftUI
import DesignSystem

/// Screen 29 (lock state) — shown over the app when App Lock is on. Prompts automatically on appear.
public struct LockView: View {
    let biometry: BiometryKind
    let unlock: @MainActor () async -> Void

    public init(biometry: BiometryKind, unlock: @escaping @MainActor () async -> Void) {
        self.biometry = biometry
        self.unlock = unlock
    }

    public var body: some View {
        VStack(spacing: 20) {
            Spacer()
            BrandMark(size: 80)
            Text("FlowMoney is locked").font(.title2.bold())
            Text("Your financial data is protected.")
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                Task { await unlock() }
            } label: {
                Label("Unlock with \(biometry.title)", systemImage: symbol)
            }
            .buttonStyle(.primary)
            .accessibilityIdentifier("lock.unlock")
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
        .task { await unlock() }
    }

    private var symbol: String {
        switch biometry {
        case .faceID: "faceid"
        case .touchID: "touchid"
        case .opticID: "opticid"
        case .none: "lock.open.fill"
        }
    }
}
