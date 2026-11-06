# Version 0.1.1 verification

Verified 2026-11-06 on the authorized Mac with Xcode 27.2 / iPhoneOS 27.2.

- Native arm64 Release build passed; app version 0.1.1, build 2.
- All 12 iPhone simulator XCTest tests passed. New coverage includes bytewise UTF-8/CRLF SSE framing, multiline event data, failure/incomplete events, premature EOF, stream size bounds, and redacted HTTP error details.
- Responses requests now send `stream: true`, retain `store: false`, and omit `max_output_tokens`. Feedback is accepted only after `response.completed`.
- IPA payload, native source hashes and SHA-256 verified before publishing.
- Tests use synthetic streaming events. No authenticated request to the user's Codex Broker was made; this release is ready for that integration test. Neither Codex Broker nor the companion was modified.
- Physical capture/provisioning limitations below still apply. No new physical-device verification is claimed.

# First demo verification

Release: `v0.1.0` (unsigned, requires signing). Verification performed 2026-11-06.

## Passed

- Native arm64 Release build with Xcode 27.2 (27B52), iPhoneOS 27.2 SDK, deployment target iOS 27.0, on an authorized local Mac in a separate ScreenSage workspace.
- Device binary links the real ScreenCaptureKit framework. The simulator-only unavailable implementation is not the device capture implementation.
- Seven XCTest unit tests on iPhone 18 Pro / iOS 27.2 simulator: bounded sampling/order, contact sheet rendering with mixed dimensions, HTTPS URL validation, both custom wire formats, completed response/error parsing, stop/reset behavior, and editable presets/notification excerpts. Zero failures.
- Seven companion tests: input bounds, disabling tools, image/thread wiring, failed turns, cancellation, login cleanup, HTTP authorization and Origin rejection. Zero failures. These use fakes/synthetic data.
- Actual `codex-cli 0.166.0` app-server initialization and config read in an isolated unsigned-in home. A turn against a local synthetic Responses server completed. Its outgoing request contained image input and **no model-facing tools**. No real account credentials or live inference were used.
- App launches and main interface visually inspected on iPhone and iPad simulators. No screen-sharing inference is claimed from this check.
- IPA packaging and SHA-256 checked; contains only the unsigned app payload. No credentials, account data or captured screen images included.

## Not verified

- Physical full-display cross-app capture, background duration, rotation on hardware, lock/unlock and system revoke behavior, battery/memory over extended sessions.
- SideStore/free-account provisioning and capture availability on iPhone 17 Pro Max/iOS 27 or iPad Air M2/iPadOS 27.
- Real Codex device-code sign-in, account eligibility, token refresh, account model access or authenticated image inference.
- A real custom provider/proxy (no URL, model or key supplied).
- Actual background notification delivery/tap routing on a physical device. Code supports short excerpts and opening detail from notification payload, including after process restart; permission and Focus affect delivery.

## Build infrastructure limits

T3 agent device access was disabled. Apple does not include ScreenCaptureKit in the tested iOS simulator SDK; simulator capture explicitly reports unavailable.

[GitHub Actions run](https://github.com/NotRllyRn/screensage/actions/runs/42172440401) passed companion tests but its native job failed the required-SDK check because the hosted runner had no iOS 27 SDK. The release IPA therefore comes from the local Mac, not that failed Actions job. The workflow can produce IPA/test artifacts once its runner offers the required SDK.

See [physical-device checklist](DEVICE-TESTS.md) and [companion setup](../companion/README.md). These remaining integration checks need user device access and a configured connection; the release does not label them as passed.
