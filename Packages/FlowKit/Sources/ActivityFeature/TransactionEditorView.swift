public import Domain
public import LedgerUI
public import SwiftUI
import DesignSystem
import FlowCore

/// Screens 8 & 9 — the fast "add expense / income" flow with an on-screen keypad.
public struct TransactionEditorView: View {
    @State private var model: TransactionEditorModel
    @State private var showsCategories = false
    @State private var confirmsDelete = false
    @State private var didSave = false
    @FocusState private var textFocused: Bool
    @Environment(\.dismiss) private var dismiss

    public init(context: LedgerContext, kind: TransactionKind, editing: UUID? = nil, accountID: UUID? = nil) {
        _model = State(initialValue: TransactionEditorModel(context: context, kind: kind, editing: editing, accountID: accountID))
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 18) {
                        PillPicker(TransactionKind.allCases, selection: $model.kind) { $0 == .expense ? "Expense" : "Income" }
                            .accessibilityIdentifier("editor.kind")
                        amountDisplay
                        fields
                        if let error = model.errorMessage {
                            ErrorBanner(error)
                        }
                        if model.isEditing {
                            Button("Delete Transaction", role: .destructive) { confirmsDelete = true }
                        }
                    }
                    .padding(16)
                }
                .scrollDismissesKeyboard(.interactively)
                if !textFocused {
                    VStack(spacing: 12) {
                        KeypadView(input: $model.keypad)
                        saveButton
                    }
                    .padding(16)
                    .background(.bar)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.snappy, value: textFocused)
            .background(Theme.background)
            .navigationTitle(model.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .keyboard) {
                    HStack {
                        Spacer()
                        Button("Done") { textFocused = false }
                    }
                }
            }
            .sheet(isPresented: $showsCategories) {
                CategoryPickerView(kind: model.kind, selection: $model.categoryID)
            }
            .confirmationDialog("Delete this transaction?", isPresented: $confirmsDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    Task {
                        if await model.delete() {
                            dismiss()
                        }
                    }
                }
            }
            .task { await model.load() }
            .sensoryFeedback(.success, trigger: didSave)
        }
        .environment(\.currency, model.currency)
        .interactiveDismissDisabled(model.amount != nil && !model.isEditing)
    }

    private var amountDisplay: some View {
        VStack(spacing: 4) {
            Text(model.currency.symbol + model.keypad.display)
                .font(.system(size: 52, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(model.kind == .income ? Theme.income : Color.primary)
                .minimumScaleFactor(0.4)
                .lineLimit(1)
                .contentTransition(.numericText())
                .animation(.snappy(duration: 0.15), value: model.keypad.display)
                .accessibilityLabel("Amount \(model.amount.map(model.currency.string) ?? "zero")")
                .accessibilityIdentifier("editor.amount")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private var fields: some View {
        VStack(spacing: 0) {
            Button {
                showsCategories = true
            } label: {
                fieldRow("Category") {
                    if let category = model.categoryID?.category {
                        Label(category.name, systemImage: category.symbol).foregroundStyle(.primary)
                    } else {
                        Text("Choose").foregroundStyle(Theme.brand)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("editor.category")
            Divider().padding(.leading, 16)
            fieldRow("Account") {
                Picker("Account", selection: $model.accountID) {
                    ForEach(model.accounts) { account in
                        Text(account.name).tag(Optional(account.id))
                    }
                }
                .labelsHidden()
                .tint(.primary)
                .fixedSize()
            }
            Divider().padding(.leading, 16)
            fieldRow("Date") {
                DatePicker("Date", selection: $model.date, in: ...Date.distantFuture)
                    .labelsHidden()
            }
            Divider().padding(.leading, 16)
            fieldRow(model.kind == .expense ? "Merchant" : "From") {
                TextField("Optional", text: $model.merchant)
                    .multilineTextAlignment(.trailing)
                    .focused($textFocused)
                    .submitLabel(.done)
                    .accessibilityIdentifier("editor.merchant")
            }
            if textFocused, !model.merchantSuggestions.isEmpty {
                suggestions
            }
            Divider().padding(.leading, 16)
            fieldRow("Note") {
                TextField("Add a note…", text: $model.note)
                    .multilineTextAlignment(.trailing)
                    .focused($textFocused)
                    .submitLabel(.done)
            }
        }
        .card(padding: 0)
    }

    private var suggestions: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(model.merchantSuggestions, id: \.merchant) { suggestion in
                    Button {
                        model.applySuggestion(merchant: suggestion.merchant, category: suggestion.category)
                    } label: {
                        Label(suggestion.merchant, systemImage: suggestion.category.category.symbol)
                            .font(.footnote.weight(.medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Theme.brandSoft, in: .capsule)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
        }
    }

    private func fieldRow(_ title: String, @ViewBuilder value: () -> some View) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer(minLength: 12)
            value()
        }
        .font(.body)
        .padding(.horizontal, 16)
        .frame(minHeight: 52)
        .contentShape(.rect)
    }

    private var saveButton: some View {
        Button {
            Task {
                if await model.save() {
                    didSave = true
                    dismiss()
                }
            }
        } label: {
            Text(model.isEditing ? "Save Changes" : (model.kind == .expense ? "Save Expense" : "Save Income"))
        }
        .buttonStyle(.primary)
        .disabled(!model.canSave)
        .accessibilityIdentifier("editor.save")
    }
}
