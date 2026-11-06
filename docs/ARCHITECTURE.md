# Demo architecture

- SwiftUI owns one main-actor session. ScreenCaptureKit owns the explicit system-approved full-display stream. Pause ends capture; resume asks again.
- Capture delivers at most one resized image per ten seconds. Six timestamped frames make a contact sheet. Keep six recent frames, one latest sheet, one inference request; skip automatic analysis while busy. No screenshot files.
- Provider configuration lives in Keychain, including URL and model. Direct custom mode uses Chat Completions or Responses. Codex mode uses a user-controlled companion with official app-server device-code sign-in and ephemeral image turns, with model-facing tools disabled.
- Stop cancels networking and capture, invalidates callbacks, clears screen/context memory, and removes pending feedback notifications. Network cancellation cannot recall content already received by a provider.
- A bounded feedback history supplies recent task context. Only explicit ALERT responses trigger short-excerpt notifications with a cooldown. Tapping opens detailed feedback. Named local monitoring presets provide editable guidance.

## Verification sources (2026-11-06)

Apple's iOS capture article and installed Xcode 27.2 headers confirm SCContentSharingPicker.present(), SCStream, iOS 27 availability, and the screen-capture background mode. Physical capture/provisioning still needs device verification.

OpenAI's open-source SIWC registration documentation specifies dynamic_agent_client, PKCE, state/nonce, an HTTP 127.0.0.1 callback, and issued client IDs. This differs from commercial partner registration. The alternative direct flow owns OAuth and validates ID tokens; the mobile app never extracts Codex credentials. Responses requires store=false, stream=true, bounded explicit history, and a model available to the account. Images are supported for accepting models. Account access and limits remain subject to the service.

- https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-on-ios
- https://developers.openai.com/siwc/token-sharing-open-source/sign-in
- https://developers.openai.com/siwc/token-sharing-open-source/models-and-inference
- https://developers.openai.com/siwc/token-sharing-open-source/preview-limitations

## Implementation sequence

1. SDK/auth research and architecture.
2. Capture, contact sheets, provider transport, session lifecycle and UI.
3. Companion OAuth/inference and deterministic tests.
4. Native build/tests, unsigned IPA packaging, checksum and public release.

The implemented companion uses app-server managed ChatGPT device-code authentication instead of direct dynamic registration, following the user’s clarified preference. Verified against official app-server docs and the installed CLI protocol. Each analysis is ephemeral with bounded context, and the local synthetic protocol check asserts no tools are exposed.
