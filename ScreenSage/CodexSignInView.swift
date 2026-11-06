import SwiftUI

struct CodexSignInView: View {
    let connection: Connection
    @State private var status = "Enter your companion URL and connection key first."
    @State private var code = ""
    @State private var signInURL: URL?
    @State private var busy = false
    @State private var work: Task<Void, Never>?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button("Continue with ChatGPT") { perform("login/start") }.disabled(busy)
            if !code.isEmpty { Text("One-time code: \(code)").font(.headline).textSelection(.enabled) }
            if let signInURL { Link("Open OpenAI sign-in", destination: signInURL) }
            Button("Check sign-in & models") { perform("account") }.disabled(busy)
            Button("Sign out of companion", role: .destructive) { perform("logout") }.disabled(busy)
            Text(status).font(.caption).textSelection(.enabled)
            if busy { ProgressView() }
        }.onDisappear { work?.cancel() }
    }
    private func perform(_ path: String) {
        Diagnostics.shared.record("companion.action", ["login": path == "login/start" ? 1 : 0, "account": path == "account" ? 1 : 0, "logout": path == "logout" ? 1 : 0])
        busy = true
        work = Task { @MainActor in
            defer { busy = false }
            do {
                guard !connection.key.isEmpty else { throw AppError.message("Enter the companion connection key first.") }
                var request = URLRequest(url: try connection.endpoint(path)); request.httpMethod = "POST"; request.timeoutInterval = 30
                request.setValue("Bearer " + connection.key, forHTTPHeaderField: "Authorization")
                let config = URLSessionConfiguration.ephemeral; config.urlCache = nil; config.httpCookieStorage = nil
                let session = URLSession(configuration: config, delegate: NoRedirect(), delegateQueue: nil)
                defer { session.invalidateAndCancel() }
                let (bytes, response) = try await session.bytes(for: request)
                Diagnostics.shared.record("companion.http", ["status": (response as? HTTPURLResponse)?.statusCode ?? 0])
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw AppError.message("Companion request failed. Check URL/key and companion status.") }
                var data = Data()
                for try await byte in bytes {
                    guard data.count < 100_000 else { throw AppError.message("Companion response too large.") }
                    data.append(byte)
                }
                try Task.checkCancellation()
                let result = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
                if path == "login/start" {
                    guard let raw = result["verificationUrl"] as? String, let url = URL(string: raw), url.scheme == "https",
                          ["auth.openai.com", "chatgpt.com"].contains(url.host ?? ""), url.user == nil, url.password == nil,
                          let userCode = result["userCode"] as? String else { throw AppError.message("Companion returned an invalid OpenAI sign-in response.") }
                    code = String(userCode.prefix(40)); signInURL = url
                    status = "Complete sign-in in your browser, then tap Check sign-in. Your account may require device-code sign-in to be enabled."
                } else {
                    status = (result["status"] as? String ?? "Unknown status")
                    if let models = result["models"] as? [String], !models.isEmpty { status += "\nAvailable vision models: " + models.joined(separator: ", ") }
                    if path == "logout" || result["signedIn"] as? Bool == true { code = ""; signInURL = nil }
                }
                Diagnostics.shared.record("companion.action_complete")
            } catch { Diagnostics.shared.error("companion.error", error); if !Task.isCancelled { status = error.localizedDescription } }
        }
    }
}
