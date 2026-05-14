import SwiftUI

/// Sheet shown before exporting — lets the user choose transition style and quality.
struct CompilationOptionsView: View {
    @Binding var transition: TransitionStyle
    @Binding var quality: ExportQuality
    let clipCount: Int
    let onExport: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Transition", selection: $transition) {
                        ForEach(TransitionStyle.allCases) { style in
                            Text(style.rawValue).tag(style)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Transition between clips")
                } footer: {
                    Text(transition == .crossFade
                         ? "Clips dissolve smoothly into each other."
                         : "Hard cut between every clip.")
                }

                Section {
                    Picker("Quality", selection: $quality) {
                        ForEach(ExportQuality.allCases) { q in
                            Text(q.rawValue).tag(q)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Export quality")
                } footer: {
                    Text(quality == .p4K
                         ? "Largest file size. Best for saving as a master copy."
                         : "Good quality, smaller file. Best for sharing.")
                }

                Section {
                    HStack {
                        Image(systemName: "film.stack")
                            .foregroundStyle(.secondary)
                        Text("\(clipCount) clip\(clipCount == 1 ? "" : "s")")
                        Spacer()
                        Image(systemName: "arrow.right")
                            .foregroundStyle(.secondary)
                        Text("1 video")
                    }
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
                } header: {
                    Text("Summary")
                }
            }
            .navigationTitle("Export Options")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Export") {
                        dismiss()
                        onExport()
                    }
                    .bold()
                }
            }
        }
        .presentationDetents([.medium])
    }
}
