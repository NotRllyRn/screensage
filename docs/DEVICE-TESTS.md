# Physical-device acceptance checklist

Not run for the first release. Simulator tests cannot establish these results. Use synthetic/non-sensitive apps first.

- SideStore/free-account signing: IPA installs on iPhone 17 Pro Max/iOS 27 and iPad Air M2/iPadOS 27; OS accepts screen-capture background mode. Record any provisioning failure. This is not promised to work before testing.
- Connection: custom HTTPS `/v1` endpoint/key/model can identify the synthetic blue test image. Verify both supported wire formats with an appropriate server. Wrong key/model, 429, timeout, redirect, and lost network show errors without retries or accumulating work.
- Codex: companion sign-in completes through OpenAI; model list appears; synthetic vision check completes. Sign-out stops subsequent authenticated analysis. Restart companion and verify managed credentials refresh.
- Consent: no capture before Start and system approval; cancel picker; revoke system sharing; verify visible system capture indication. Camera/microphone permission should not be requested.
- Cross-app: open a non-sensitive app for at least five minutes. Six chronologically labeled images produce useful feedback approximately once per minute, subject to actual frame availability and network latency. Static/protected screens may not produce usable frames.
- Rotate phone/tablet, split view and change apps. Check that text is legible and orientation is correct. Dense text may need larger tiles in a later revision.
- Ask after one frame, during busy inference, and after network failure. Verify bounded context does not imply perfect memory.
- Pause and Stop during picker/start/upload; repeatedly resume. No stale callbacks should restart capture or append cancelled answers. Pause requires new system approval. Stop clears images and feedback. Already-uploaded data cannot be recalled.
- Lock/unlock, system stop and background suspension: capture status should update on return; no hidden restart. Inspect actual elapsed time between frames.
- Notifications: allow/deny, Focus enabled, foreground/background. Only concrete ALERT responses produce short reasons, at most once per two minutes. Tap to open detailed evidence and correction, including after app termination. Verify lock-screen preview settings.
- Memory/battery: monitor a 30-minute session with a slow/unreachable provider. No growing image queue; only six recent frames, one in-flight sheet and 20 text answers. Note energy cost of continuous system capture even though processing samples only every ten seconds.
