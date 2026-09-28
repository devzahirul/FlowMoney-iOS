public import Domain
public import SwiftUI
import DesignSystem

/// Screen 10 — searchable category grid.
public struct CategoryPickerView: View {
    let kind: TransactionKind
    @Binding var selection: CategoryID?
    @State private var query = ""
    @Environment(\.dismiss) private var dismiss

    public init(kind: TransactionKind, selection: Binding<CategoryID?>) {
        self.kind = kind
        _selection = selection
    }

    private var categories: [Domain.Category] {
        let all = CategoryCatalog.categories(for: kind)
        guard !query.isEmpty else { return all }
        return all.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 12)], spacing: 16) {
                    ForEach(categories) { category in
                        Button {
                            selection = category.id
                            dismiss()
                        } label: {
                            VStack(spacing: 8) {
                                IconBadge(category.symbol, color: category.color, size: 52)
                                    .overlay {
                                        if selection == category.id {
                                            RoundedRectangle(cornerRadius: 16).stroke(Theme.brand, lineWidth: 2.5)
                                        }
                                    }
                                Text(category.name)
                                    .font(.caption.weight(.medium))
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                                    .foregroundStyle(.primary)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selection == category.id ? .isSelected : [])
                        .accessibilityIdentifier("category.\(category.id.rawValue)")
                    }
                }
                .padding(16)
            }
            .background(Theme.background)
            .overlay {
                if categories.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search categories")
            .navigationTitle("Select Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
