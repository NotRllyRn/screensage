# ScreenSage

A proposed iPhone and iPad screen-aware assistant: start an explicitly approved screen-capture session, work in another app, and receive contextual AI feedback or ask about your recent activity.

**Status:** project brief and repository initialized. The first demo is not implemented or released yet. This README describes the requested behavior, not completed features.

## First demo

- Native SwiftUI app for iPhone and iPad, initially targeting iOS/iPadOS 27.
- User-started full-display capture that continues while another app is foregrounded.
- Approximately one frame every ten seconds; six timestamped images form a contact sheet for analysis about once per minute.
- A user-specified task or goal, bounded recent context, a readable activity/feedback history, and an Ask action using recent screen context.
- Relevant notifications for potential mistakes; clear start, pause, stop, and capture/upload status.
- Two connection choices: supported Codex/ChatGPT sign-in, and a custom OpenAI-compatible provider/proxy configured with URL, key, and vision-model identifier.
- A downloadable unsigned IPA on GitHub Releases for SideStore testing, with a checksum and installation instructions. Automated build artifacts should also be available.

The app observes and advises. It does not control other apps, promise perfect understanding, or capture silently. Capture authorization and consent to send screen content to the selected provider are separate. Screen contents and credentials must never be committed or included in diagnostic logs.

## Implementation direction

Keep capture, image batching, provider connections, analysis coordination, notification delivery, and SwiftUI presentation separate. Use the smallest useful design: one bounded inference request at a time, bounded image retention, explicit cancellation, actionable failures, and secure credential storage. Prefer simple readable solutions and concise commits.

Apple's current documentation describes ScreenCaptureKit on iOS 27 with full-display capture, the system sharing picker, and the `screen-capture` background mode. Verify these APIs against the installed SDK and a physical device. Ordinary background timers are not a substitute for an active authorized capture session.

Codex sign-in is an integration requirement, not an assumption that a ChatGPT subscription is an arbitrary API key. Verify supported official authentication and vision input. If an authenticated user-controlled companion service is required, explain and implement the smallest supported approach; do not fake a native sign-in flow or use undocumented token extraction. Keep custom-provider mode independently usable.

## Development and release

The implementation thread should create a short architecture and implementation plan, build the demo, run meaningful tests, and publish its first tested release. Use GitHub Actions with an appropriate Xcode 27 SDK, or build on an authorized Mac and upload the IPA. Distinguish simulator checks from real cross-app capture, authentication, background delivery, and physical-device tests. Never claim an untested integration works.

The full user requests, acceptance criteria, references, and handoff are in [docs/BRIEF.md](docs/BRIEF.md). Engineering expectations are in [AGENTS.md](AGENTS.md).

## References

- [Apple: Capturing screen content on iOS](https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-on-ios)
- [Apple: ScreenCaptureKit](https://developer.apple.com/documentation/screencapturekit)
- [Apple: Background execution modes](https://developer.apple.com/documentation/xcode/configuring-background-execution-modes)
- [OpenAI: Sign in with ChatGPT](https://developers.openai.com/siwc)
- [OpenAI: Codex app-server authentication](https://learn.chatgpt.com/docs/app-server#auth-endpoints)

