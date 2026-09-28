public import LedgerUI
public import SwiftUI
import DesignSystem
import Domain
import Observation

@MainActor
@Observable
final class ExportModel {
    var format = ExportFormat.pdf
    var range = ExportRange.thisMonth
    private(set) var fileURL: URL?
    private(set) var isExporting = false
    var errorMessage: String?
    private let context: LedgerContext

    init(context: LedgerContext) {
        self.context = context
    }

    func export() async {
        isExporting = true
        fileURL = nil
        defer { isExporting = false }
        let snapshot = await context.repository.currentSnapshot()
        let (format, range, now, calendar) = (format, range, context.now(), context.calendar)
        do {
            // PDF layout of a year of transactions takes noticeable time — keep it off the main thread.
            fileURL = try await Task.detached(priority: .userInitiated) {
                try ReportExporter.export(format: format, range: range, snapshot: snapshot, now: now, calendar: calendar)
            }.value
        } catch {
            errorMessage = "Couldn't create the report: \(error.localizedDescription)"
        }
    }
}

/// Screen 30 — export a PDF report or CSV and share it.
public struct ExportView: View {
    @State private var model: ExportModel

    public init(context: LedgerContext) {
        _model = State(initialValue: ExportModel(context: context))
    }

    public var body: some View {
        Form {
            Section("Choose format") {
                ForEach(ExportFormat.allCases) { format in
                    Button {
                        model.format = format
                    } label: {
                        HStack(spacing: 12) {
                            IconBadge(
                                format == .pdf ? "doc.richtext.fill" : "tablecells.fill",
                                color: format == .pdf ? Theme.expense : Theme.income,
                                size: 36
                            )
                            VStack(alignment: .leading) {
                                Text(format.rawValue).font(.body.weight(.medium)).foregroundStyle(.primary)
                                Text(format.detail).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if model.format == format {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.brand)
                            }
                        }
                    }
                    .accessibilityAddTraits(model.format == format ? .isSelected : [])
                }
            }
            Section("Date range") {
                Picker("Range", selection: $model.range) {
                    ForEach(ExportRange.allCases) { Text($0.rawValue).tag($0) }
                }
            }
            Section {
                if let url = model.fileURL {
                    ShareLink(item: url) {
                        Label("Share \(model.format.rawValue)", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.primary)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                } else {
                    Button {
                        Task { await model.export() }
                    } label: {
                        if model.isExporting {
                            ProgressView().tint(.white)
                        } else {
                            Text("Export Report")
                        }
                    }
                    .buttonStyle(.primary)
                    .disabled(model.isExporting)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                    .accessibilityIdentifier("export.run")
                }
            } footer: {
                Text("Reports are created on your iPhone and shared only where you choose.")
            }
        }
        .navigationTitle("Export Report")
        .onChange(of: model.format) { model.fileURL.map { try? FileManager.default.removeItem(at: $0) } }
        .onChange(of: model.range) { model.fileURL.map { try? FileManager.default.removeItem(at: $0) } }
        .errorAlert($model.errorMessage)
    }
}
