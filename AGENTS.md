# Engineering expectations

- Build the first working demo described in README.md and docs/BRIEF.md; the user will monitor this project's own T3 thread.
- Use software engineering techniques: a concise implementation plan, small modules, clear state and ownership, meaningful tests, and honest verification.
- Follow YAGNI. Prefer minimalism, simplicity, modularity, and readable one-liners where they help. Avoid clever compression or abstractions for speculative providers/features.
- Commit short, concise messages along the way and push the code. The user explicitly authorized the public repository and publishing downloadable IPA releases.
- Keep the README accurate. Publish the first demo IPA and SHA-256 checksum through GitHub Releases, using GitHub Actions or a verified local macOS build. Also provide build artifacts when practical.
- Do not add keys, OAuth tokens, account data, Mac credentials, or captured screen images to the repository or release. Use Keychain for app secrets, ignored local configuration for development, and private secret-entry tools when needed.
- Verify current official Apple and OpenAI APIs. Do not assume Codex subscription authentication is interchangeable with provider API-key access. Implement only supported auth flows; document actual limitations and ask the user directly when necessary.
- Do not modify the separate LectureClip project. Do not send progress back to the originating thread. The user will continue here directly; no parent-agent monitoring or report-back is requested.

