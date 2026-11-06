import SwiftUI

@main
struct ScreenSageApp: App {
    @StateObject private var session = Session()
    var body: some Scene { WindowGroup { ContentView(session: session) } }
}
struct ContentView: View {
    @ObservedObject var session: Session
    @State private var settings = false
    @State private var contexts = false
    @State private var diagnostics = false
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label("Your task, with screen context", systemImage: "rectangle.inset.filled.and.person.filled")
                        .font(.headline)
                    Text("ScreenSage samples your full screen about every 10 seconds and sends six timestamped images to your chosen AI. Feedback can lag a minute or more and may be wrong.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Button("Context: " + session.currentPreset.name) { contexts = true }.disabled(session.active || session.busy || session.transitioning)
                    TextField("What are you working on?", text: $session.goal, axis: .vertical)
                        .lineLimit(2...4).disabled(session.active)
                        .onChange(of: session.goal) { _, value in session.goal = String(value.prefix(2000)) }
                }
                Section("Capture & sharing") {
                    Text(session.captureStatus).accessibilityIdentifier("captureStatus")
                    Text("Recent frames: \(session.frameCount)/6")
                    if let date = session.lastFrame { Text("Last frame: \(date.formatted(date: .omitted, time: .standard))").font(.caption) }
                    Toggle("I agree to send screen content to this provider", isOn: $session.consent)
                        .disabled(session.active)
                    Text("Full-screen sharing can include messages, account details and other private content. Your provider’s retention policy applies. Stop before opening sensitive apps.").font(.caption)
                    HStack {
                        Button("Start", systemImage: "record.circle") { session.start() }
                            .disabled(session.active || session.busy || session.transitioning || !session.consent)
                        Spacer()
                        Button("Pause", systemImage: "pause") { session.stop(paused: true) }.disabled(!session.active || session.transitioning)
                        Spacer()
                        Button("Stop", systemImage: "stop.fill", role: .destructive) { session.stop() }.disabled(session.transitioning)
                    }.buttonStyle(.bordered)
                    Text(session.uploadStatus).font(.caption).textSelection(.enabled)
                    if session.busy { ProgressView("Waiting for provider") }
                }
                Section("Ask about recent screens") {
                    TextField("Your question", text: $session.question, axis: .vertical).lineLimit(1...4)
                        .onChange(of: session.question) { _, value in session.question = String(value.prefix(2000)) }
                    Button("Ask", systemImage: "questionmark.bubble") { session.ask() }
                        .disabled(!session.active || session.frameCount == 0 || session.busy)
                }
                Section("Feedback") {
                    if session.history.isEmpty { Text("Analysis appears after six frames, or tap Ask after the first frame.").foregroundStyle(.secondary) }
                    ForEach(session.history.reversed()) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.date.formatted(date: .omitted, time: .standard)).font(.caption).foregroundStyle(.secondary)
                            Text(item.text).textSelection(.enabled)
                            Button("Details") { session.selectedFeedback = item }
                        }
                    }
                }
                Section {
                    Button("Enable feedback notifications") { Task { await session.enableNotifications() } }
                    Text(session.notificationStatus).font(.caption)
                    Text("Alert previews show a short reason and may reveal task details on your lock screen. Tap an alert for the explanation and suggested correction. You can hide notification previews in iOS Settings.").font(.caption)
                    Text("Pause ends capture and clears images. Stop also clears recent feedback. No screenshot is saved to Photos or app storage.").font(.caption)
                }
            }
            .navigationTitle("ScreenSage")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Diagnostics", systemImage: "stethoscope") { diagnostics = true } }
                ToolbarItem(placement: .topBarTrailing) { Button("Connection", systemImage: "network") { settings = true }.disabled(session.active || session.busy || session.transitioning) }
            }
            .sheet(isPresented: $diagnostics) { DiagnosticsView(session: session) }
            .sheet(isPresented: $settings) { ConnectionView(session: session) }
            .sheet(isPresented: $contexts) { PresetsView(session: session) }
            .sheet(item: $session.selectedFeedback) { FeedbackDetail(feedback: $0) }
        }
        .onChange(of: scenePhase) { _, phase in Diagnostics.shared.record("app.scene", ["active": phase == .active ? 1 : 0, "background": phase == .background ? 1 : 0]) }
        .onChange(of: session.connection.address) { _, _ in session.consent = false }
        .onChange(of: session.connection.kind) { _, _ in session.consent = false }
    }
}
struct ConnectionView: View {
    @ObservedObject var session: Session
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section("Connection") {
                    Picker("Mode", selection: $session.connection.kind) { ForEach(ConnectionKind.allCases, id: \.self) { Text($0.rawValue) } }
                    TextField(session.connection.kind == .custom ? "HTTPS base URL, including /v1" : "HTTPS companion URL", text: $session.connection.address)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField(session.connection.kind == .custom ? "Provider API key" : "Companion connection key", text: $session.connection.key)
                    TextField("Vision model identifier", text: $session.connection.model).textInputAutocapitalization(.never).autocorrectionDisabled()
                    if session.connection.kind == .custom {
                        Picker("API format", selection: $session.connection.wire) { ForEach(WireProtocol.allCases, id: \.self) { Text($0.rawValue) } }
                        Text("Use a base URL such as https://your-provider.example/v1. HTTPS is required; plain HTTP is not enabled in this demo.").font(.caption)
                    } else {
                        CodexSignInView(connection: session.connection)
                        Text("Your companion runs Codex app-server. Continue with ChatGPT below, then choose a model from Check sign-in. The companion holds Codex credentials; this phone holds only its connection key.")
                        Link("Codex companion setup", destination: URL(string: "https://github.com/NotRllyRn/screensage/blob/main/companion/README.md")!)
                        Text("Requires your own running companion and Codex account access. Each analysis creates a temporary Codex thread with bounded recent context; it is not saved to your Codex chat history.").font(.caption)
                    }
                }.disabled(session.busy)
                Section {
                    Button("Save connection") { session.save() }.disabled(session.busy)
                    Button("Test vision connection") { session.testConnection() }.disabled(session.busy)
                    Text("The test sends only a generated blue image; it does not start capture.").font(.caption)
                    Text(session.uploadStatus).font(.caption).textSelection(.enabled)
                    if session.busy { ProgressView() }
                }
            }.navigationTitle("Connection").toolbar { Button("Done") { dismiss() } }
        }
    }
}
