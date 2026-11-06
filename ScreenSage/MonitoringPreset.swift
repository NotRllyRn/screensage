import SwiftUI

struct MonitoringPreset: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var instructions: String
    static let initial = MonitoringPreset(name: "Default", instructions: "Help me make progress on the task I describe. Watch for concrete mistakes, missed steps, or contradictions visible in my recent screens. Interrupt only when a specific correction would be useful now; do not interrupt for ordinary progress or speculation. Explain the evidence, why it matters, and a practical next step. If you cannot read or understand the screen, say so.")
    static func load() -> [MonitoringPreset] {
        guard let data = UserDefaults.standard.data(forKey: "monitoringPresets"),
              let saved = try? JSONDecoder().decode([MonitoringPreset].self, from: data), !saved.isEmpty else { return [initial] }
        return Array(saved.prefix(20))
    }
    static func save(_ presets: [MonitoringPreset]) {
        if let data = try? JSONEncoder().encode(presets) { UserDefaults.standard.set(data, forKey: "monitoringPresets") }
    }
}
struct PresetsView: View {
    @ObservedObject var session: Session
    @Environment(\.dismiss) private var dismiss
    @State private var editing: MonitoringPreset?
    var body: some View {
        NavigationStack {
            List {
                Section("Select or edit monitoring context") {
                    ForEach(session.presets) { preset in
                        HStack {
                            Button { session.selectPreset(preset.id) } label: {
                                Label(preset.name, systemImage: session.selectedPresetID == preset.id ? "checkmark.circle.fill" : "circle")
                            }
                            Spacer()
                            Button("Edit") { editing = preset }.buttonStyle(.borderless)
                        }
                    }.onDelete { offsets in session.deletePresets(offsets) }
                }
                Section {
                    Button("New context", systemImage: "plus") {
                        editing = MonitoringPreset(name: "", instructions: "What I am doing:\n\nWatch for:\n\nInterrupt me when:\n\nExplain what I should change:")
                    }.disabled(session.presets.count >= 20)
                    Text("These instructions are sent with your goal and screen images. They are saved on this device. Stop capture before switching or editing a context.").font(.caption)
                }
            }.navigationTitle("Monitoring contexts")
                .toolbar { Button("Done") { dismiss() } }
                .sheet(item: $editing) { preset in PresetEditor(preset: preset) { session.savePreset($0) } }
        }
    }
}
struct PresetEditor: View {
    @State var preset: MonitoringPreset
    var save: (MonitoringPreset) -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                TextField("Name, e.g. Studying", text: $preset.name)
                    .onChange(of: preset.name) { _, value in preset.name = String(value.prefix(60)) }
                Section("What should ScreenSage watch for?") {
                    TextEditor(text: $preset.instructions).frame(minHeight: 260)
                        .onChange(of: preset.instructions) { _, value in preset.instructions = String(value.prefix(4000)) }
                    Text("Describe your task, when to interrupt, what counts as a mistake, and the kind of correction you want. Up to 4,000 characters.").font(.caption)
                }
            }.navigationTitle("Edit context")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save") { save(preset); dismiss() }.disabled(preset.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || preset.instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
                }
        }
    }
}
struct FeedbackDetail: View {
    let feedback: Feedback
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(feedback.date.formatted()).font(.caption).foregroundStyle(.secondary)
                    Text(feedback.text).textSelection(.enabled)
                    Text("AI advice can be wrong. Check the visible evidence before acting.").font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading).padding()
            }.navigationTitle("Feedback details").toolbar { Button("Done") { dismiss() } }
        }
    }
}
