# ScreenSage

A native iPhone/iPad screen-context assistant for iOS/iPadOS 27. Explicitly start full-screen sharing, work in another app, and ask your chosen vision model about recent activity.

**Current demo:** [v0.1.2](https://github.com/NotRllyRn/screensage/releases/tag/v0.1.2), built and unit-tested. Physical background capture, SideStore provisioning and authenticated provider responses are still unverified.

## What it does

- System-approved ScreenCaptureKit full-display capture with the `screen-capture` background mode.
- Processes at most one available frame every ten seconds; six timestamped images form a 1440×3000 contact sheet. Actual frame delivery is not an exact timer.
- Named, editable monitoring contexts (default plus custom profiles such as Studying), a task/goal, on-demand Ask after the first frame, and up to 20 feedback entries. The latest four short answers provide bounded recent context.
- One inference request at a time. Busy automatic batches are skipped, never queued indefinitely.
- Explicit upload consent, capture/upload status, Start/Pause/Stop, and optional short-excerpt notifications for possible mistakes with a two-minute cooldown.
- Credentials and connection settings in Keychain; screen images stay in memory. Pause ends capture and clears images. Stop also clears feedback and cancels requests. Content already received by a provider cannot be recalled.

This observes and advises; it does not control apps or promise perfect understanding. Protected content can be blank, small text can be unreadable, events between samples are missed, and feedback can lag a minute or more. Provider retention policies apply to uploaded content.

## Choose a connection

**Codex · ChatGPT sign-in:** run the small [Codex companion](companion/README.md) on your own computer/server, reachable over HTTPS. Enter its URL and connection key in the app, tap Continue with ChatGPT, complete OpenAI's device-code sign-in, then check account/models. The companion runs official Codex app-server with images and temporary threads; ScreenSage shows the answers and thread IDs. It does not reuse coding-agent tokens or treat a subscription as an API key. Each analysis uses a fresh ephemeral thread plus bounded recent text context, not an ever-growing saved Codex conversation.

**Custom provider:** enter your OpenAI-compatible HTTPS base URL (including `/v1` if required), provider API key and vision model. Select Chat Completions or Responses. Responses uses streaming SSE (`stream: true`, `store: false`) without `max_output_tokens`, for Codex Broker compatibility. It waits for `response.completed` before displaying feedback. Chat Completions continues to use non-streaming JSON. Plain HTTP and automatic redirects are intentionally unsupported in this demo. No provider URL or key is bundled.

Tap **Context: Default** to edit the default monitoring instructions or create named presets such as Studying. Describe what you are doing, what to watch for, when to interrupt, and the correction you want. Alert notifications show a short reason; tapping opens evidence, explanation and suggested action. Excerpts can reveal task details on the lock screen; iOS notification-preview settings control visibility.

Both options offer **Test vision connection**, which sends only a generated blue image. Then enter a goal, agree to screen-content uploads, tap Start and approve the system picker. Pause ends system sharing; Start asks for approval again. Avoid sensitive apps while sharing.

## Diagnostics

Tap **Diagnostics** at the top left → **Prepare diagnostics** → **Share diagnostics text file**. Reproduce the issue first so the recent events are included. You can send the exported `.txt` file with a bug report.

The local rotating log keeps up to 1,000 events across launches, starting in version 0.1.2. It records app/OS version, lifecycle, frame counts/dimensions, request sizes and duration, HTTP status, streaming event counts, completion/parsing results, numeric errors and notification status. It excludes screenshots, keys, URLs, account details, prompts, preset names and model answers. Clear history from the same screen. These operational logs do not replace OS crash reports or reveal events from older app versions.

Responses text is assembled from deltas and completed items, with no duplicate text; successful completion is required before feedback. Codex Broker's leading usage notice is excluded from the answer so `ALERT:` classification works.

## Install and verify

Download the unsigned IPA and SHA256SUMS from [GitHub Releases](https://github.com/NotRllyRn/screensage/releases). Verify with `shasum -a 256 -c SHA256SUMS`, then import the IPA into SideStore and sign with your own account. An unsigned IPA cannot install directly. **Free-account signing and full-display background capture on the target devices have not been verified.** See the [device checklist](docs/DEVICE-TESTS.md).

## Build and tests

Requires macOS, Xcode 27.x and XcodeGen. Linux can run companion tests but cannot build iOS apps.

```sh
./scripts/mac-build.sh
# Choose an available iOS 27 simulator:
xcodebuild -project ScreenSage.xcodeproj -scheme ScreenSage \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
  -derivedDataPath build/simulator CODE_SIGNING_ALLOWED=NO test
```

The script produces `build/ScreenSage-unsigned.ipa` and `build/SHA256SUMS`. ScreenCaptureKit is absent from the tested simulator SDK: simulator builds show an explicit unavailable message, while physical-device builds use the real framework. Tests use synthetic images and mocked protocol responses; they do not establish actual background capture or authenticated model quality.

[GitHub Actions](.github/workflows/build.yml) runs companion tests and attempts a native build/test artifact on a runner with an iOS 27 SDK. It fails explicitly if that SDK is unavailable. The first release uses an authorized local Mac, with exact verification recorded in [docs/VERIFICATION.md](docs/VERIFICATION.md).

See [architecture](docs/ARCHITECTURE.md), [original brief](docs/BRIEF.md), and [engineering expectations](AGENTS.md).

## Official references

- [Apple: Capturing screen content on iOS](https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-on-ios)
- [Codex app-server: authentication, threads and images](https://learn.chatgpt.com/docs/app-server)
- [Sign in with ChatGPT](https://developers.openai.com/siwc)
