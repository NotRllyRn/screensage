import Foundation
import SwiftUI
import UserNotifications

// Only compile-time event names and numeric fields are accepted. Never pass
// server bodies, URLs, prompts, model answers, account data or keys into logs.
final class Diagnostics: @unchecked Sendable {
    static let shared = Diagnostics()
    private let queue = DispatchQueue(label: "ScreenSage.diagnostics")
    private let file: URL
    private var entries: [String] = []
    private var writeFailed = false
    static let limit = 1000

    init(directory: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Diagnostics")) {
        file = directory.appendingPathComponent("events.txt")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var excluded = directory; var values = URLResourceValues(); values.isExcludedFromBackup = true
            try excluded.setResourceValues(values)
            let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            if size <= 512_000, let text = try? String(contentsOf: file, encoding: .utf8) {
                entries = Array(text.split(separator: "\n").suffix(Self.limit).map(String.init))
            }
        } catch { writeFailed = true }
    }
    func record(_ name: StaticString, _ fields: [String: Int] = [:]) {
        let event = String(describing: name)
        let values = fields.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
        let row = "\(Date().formatted(.iso8601)) \(event) \(values)"
        queue.async {
            self.entries.append(row)
            self.entries = Array(self.entries.suffix(Self.limit))
            do {
                try Data(self.entries.joined(separator: "\n").utf8).write(to: self.file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                self.writeFailed = false
            } catch { self.writeFailed = true }
        }
    }
    func error(_ name: StaticString, _ error: Error) {
        // Numeric error only: NSError descriptions/userInfo can contain secrets.
        let value = error as NSError
        let domain = value.domain == NSURLErrorDomain ? 1 : value.domain == NSCocoaErrorDomain ? 2 : error is AppError ? 3 : 0
        record(name, ["domain_category": domain, "code": value.code, "cancelled": error is CancellationError ? 1 : 0])
    }
    func report() -> String {
        queue.sync {
            let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
            let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
            return """
            ScreenSage diagnostics · \(version) (\(build))
            Prepared: \(Date().formatted(.iso8601))
            OS: \(ProcessInfo.processInfo.operatingSystemVersionString)
            Recent events: \(entries.count)/\(Self.limit); persistence_write_failed=\(writeFailed ? 1 : 0)
            Logs span launches, rotate at 1,000 events, and start with version 0.1.2.
            No screenshots, keys, URLs, account data, prompts, context names or model answers are included.
            Numeric errors: domain_category 1=URL loading, 2=Cocoa/JSON, 3=app validation, 0=other.
            Request stages: 0=validation, 1=connecting, 2=HTTP, 3=stream, 4=JSON, 5=parsed.
            Stream terminal_status: 0=missing, 1=completed, 2=failed, 3=incomplete, 4=error.
            These logs are operational diagnostics, not an OS crash report.

            \(entries.joined(separator: "\n"))
            """
        }
    }
    func export() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ScreenSageDiagnostics")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("ScreenSage-diagnostics.txt")
        try Data(report().utf8).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        return url
    }
    func clear() {
        queue.sync { entries = []; writeFailed = false; try? FileManager.default.removeItem(at: file) }
        try? FileManager.default.removeItem(at: FileManager.default.temporaryDirectory.appendingPathComponent("ScreenSageDiagnostics"))
    }
}

struct DiagnosticsView: View {
    @ObservedObject var session: Session
    @Environment(\.dismiss) private var dismiss
    @State private var file: URL?
    @State private var status = "Reproduce the issue, then prepare and share the text file here. Recent logs persist across app launches."
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(status)
                    Button("Prepare diagnostics", systemImage: "doc.text.magnifyingglass") {
                        Task {
                            await session.recordDiagnosticSnapshot()
                            do { file = try Diagnostics.shared.export(); status = "Diagnostics prepared with recent events and current app state." }
                            catch { status = "Could not create the diagnostics file. Try again." }
                        }
                    }
                    if let file { ShareLink("Share diagnostics text file", item: file) }
                }
                Section {
                    Text("Includes app/OS version, capture lifecycle, frame counts, request sizes and timing, HTTP status, streaming event counts, parsing results, cancellation and notification status. Excludes screen images, credentials, server addresses, prompts and answers.").font(.caption)
                    Button("Clear diagnostic history", role: .destructive) { Diagnostics.shared.clear(); file = nil; status = "Diagnostic history cleared." }
                }
            }.navigationTitle("Diagnostics").toolbar { Button("Done") { dismiss() } }
        }
    }
}
