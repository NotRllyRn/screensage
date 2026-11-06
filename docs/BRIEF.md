# ScreenSage: first demo handoff

## Original product request (verbatim)

> Is it possible to create an app that runs in the background kind of similar to this app, where it, uh, periodically takes screenshots of my entire screen, from a different app while it's in the background while it's running, and basically after like, uh, uh, after like every like, maybe 10 seconds it takes a screenshot. So it takes the 6 screenshots per minute and then puts it into like a contact sheet and then sends it off to like an AI model so that it could like basically watch what I am doing as I progress and interrupt me if it thinks that I am doing something incorrect or basically just like a monitoring tool that like understands exactly what I am doing as soon as I Ask it. Basically just look into the permissions of iOS apps and see if that's possible.

## Original implementation/thread request (verbatim, spacing normalized)

> The way that it would be connecting to another vision capable model is by using, um, a login to like Codex, or like clot API or something like that, or like Grock, or Muse, or one, or Google, whatever. Basically, for now, just do codex, because that's all I have access to. So basically this app, it's gonna let you, when you open the app, also, it's gonna ask you to like log into a Codex account or set up an HTTP reverse HTTP proxy, basically like a custom model connection to like a custom provider server. I'm running I'm running an HTTP proxy to open AI, but it's basically just another provider with like its own key. And like you can basically connect it to any provider you want. Uh, if you have the right key and the right uh, address. So also, so allow those 2 options for now for this, like, test demo of the app. And then, yeah, just have it work like that. So the, how you're gonna do this is actually you're gonna start a new T3 thread and another thread, create a new project under the code, directory, and initialize it as a, um, so basically initialize a new repository under code, and put it on GitHub as public. Um, and then start a new T3 thread on GPT6 Astra Medium, and give them all the, give it all the context that it needs, my original prompts and what you think should be done. Give it to it for it to start, um, implementing the whole thing. And after you start that T3 thread, don't monitor it and don't tell it to respond back to you. Just have it run and then I'll monitor it. monitor it and continue off from there. But I just want you to start it. I
>
> . Also tell it that it should use GitHub actions to create the IPA file or create the IPA file itself locally and then upload it as a released file on the GitHub so that I can go ahead and download it and test it. So tell it to create its 1st demo app, and then I'll monitor it and then go ahead and test the app. And then continue working on it from there. Name it something appropriate. Make the read me file. Also tell it to, um, use software engineering techniques and then also tell it to follow Yagni principles and prefer one-liner solutions. Also tell it to prefer minimalism, simplicity, and modularity, and to keep things simple and concise, tell it to. Commit short and concise messages along the way and push its code as well.

## Relevant prior context

The user has been testing a separate native app, LectureClip, using SideStore with a free Apple account. Their devices are an iPhone 17 Pro Max on iOS 27 and an iPad Air M2 on iPadOS 27. The development server is Linux; native iOS builds require macOS/Xcode or GitHub Actions. A previously authorized Mac has Xcode 27.2 and iPhone/iPad simulators, but T3 agent device access was previously unavailable. Do not claim simulator tests establish physical cross-app capture behavior.

LectureClip records/transcribes lectures, exports matching audio/text clips, supports background recording shortcuts, and has local text summaries. It is a separate project and should not be modified or copied wholesale. Its Qwen3 1.7B model is text-only and cannot analyze screenshots. ScreenSage is a new app with remote vision-provider connections, not another transcription feature.

## Research already performed, to verify against current SDK/docs

- Apple documentation fetched during the originating conversation explicitly lists ScreenCaptureKit as available on iOS/iPadOS 27, says it replaces ReplayKit for streaming/mirroring, and says a broadcast extension is no longer necessary.
- Apple's iOS sample uses the system `SCContentSharingPicker` to choose full-display versus in-app capture. It declares `screen-capture` in `UIBackgroundModes` to continue full-display capture when backgrounded. Audio mode is for microphone capture, not a fake keep-alive requirement for screen-only monitoring.
- The framework overview specifies `NSScreenCaptureUsageDescription`. Frame delivery uses `SCStream` output. `minimumFrameInterval` can throttle delivery, but do not promise an exact timer under all device conditions.
- No Photos, camera, or microphone permission is needed merely to process screen frames in private app storage. Request only permissions for implemented features.
- Ordinary background refresh cannot implement reliable ten-second sampling. Capture must be part of an explicit authorized screen-sharing session with visible status and a stop control.
- Feedback while another app is foregrounded should use authorized notifications. Focus/settings may delay them. Do not promise an arbitrary global overlay, forced foregrounding, or control of other apps.
- Protected content may be excluded. Test stop/revoke, lock/unlock, app switching, background duration, memory, and battery on real hardware. The first demo can clearly mark what remains untested.
- A sheet sent once per minute has up to roughly one minute of observation delay plus inference/network latency. Screenshots do not expose another app's internal state or capture every action. Preserve legibility and timestamps; avoid shrinking dense notes until unreadable.
- App Store guidelines 2.5.14 and 5.1.2 require recording consent/indication and explicit disclosure/permission for sharing personal data with third-party AI.

Sources:

- https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-on-ios
- https://developer.apple.com/documentation/screencapturekit
- https://developer.apple.com/documentation/screencapturekit/scstreamconfiguration/minimumframeinterval
- https://developer.apple.com/documentation/xcode/configuring-background-execution-modes
- https://developer.apple.com/documentation/usernotifications/asking-permission-to-use-notifications
- https://developer.apple.com/app-store/review/guidelines/

## Two provider paths, no speculative provider zoo

1. **Codex/ChatGPT sign-in:** investigate and implement an officially supported connection with vision input. OpenAI docs fetched during setup describe Sign in with ChatGPT and Codex app-server browser/device-code auth, but this does not by itself establish that a standalone iOS app can use the user's subscription directly. Verify client registration, allowed use, billing, available image-capable models, and whether a user-controlled Mac/server companion is needed. The fetched app-server docs distinguish local/open-source use from commercial/hosted services; review current terms and supported architecture. Do not scrape tokens, invent OAuth client credentials, fake success, or ship a button that claims working sign-in without an actual path. If registration/access is required, ask the user in this thread and continue the independently implementable proxy mode.
2. **Custom provider/proxy:** user supplies base URL, API key, and vision-model name. The existing proxy is described as an OpenAI-compatible provider with its own key. Clarify Responses vs Chat Completions support if necessary; support a small explicit protocol choice if useful rather than assuming every provider shares one schema. Validate URL/path joining, image input, authentication, connectivity, HTTP failures, rate limits, timeouts, and cancellation. Prefer HTTPS. If the user needs plain HTTP on a trusted development LAN, make the setting and ATS/local-network requirements explicit and scoped; never quietly downgrade transport.

Relevant official OpenAI references:

- https://developers.openai.com/siwc
- https://developers.openai.com/cookbook/articles/sign-in-with-chatgpt
- https://learn.chatgpt.com/docs/app-server#auth-endpoints

No provider URL, API key, or account authorization has been supplied for this new app. Request secrets privately when integration testing needs them. Do not reuse the coding agent's own account/session tokens as app credentials.

## Suggested small implementation plan

1. Verify SDK/capture/auth feasibility; record a short architecture and concrete plan.
2. Implement SwiftUI onboarding/provider configuration and a test-connection action, with Keychain credentials and clear status.
3. Implement authorized screen capture, roughly ten-second sampling, bounded six-frame contact sheets, start/pause/stop, and explicit capture/upload consent.
4. Implement one-in-flight analysis, bounded pending work/history, goal-aware feedback, notification cooldowns, and Ask using the latest available context. Separate capture from networking so slow inference does not accumulate unbounded frames.
5. Implement the supported Codex connection path and custom provider path; clearly explain any companion or account-registration requirement. Do not execute commands or grant filesystem/tool access merely to analyze screenshots.
6. Test batching/order/rotation/timestamps, provider wire formats and error handling, lifecycle/cancellation, and notifications. Use synthetic images for automated tests. Add a manual physical-device checklist and redacted diagnostics export if useful.
7. Build a first demo IPA, verify packaging and checksums, publish it as a GitHub Release, update the README with exact setup/testing limitations, and push concise commits. Use Actions if its available Xcode SDK supports iOS 27 APIs; otherwise use an authorized Mac, and explain the build provenance. A green compile alone is not proof of cross-app capture or real model authentication.

Keep the first demo minimal and useful. Do not add extra providers, a subscription system, multi-user hosting, or a large local vision model before the basic end-to-end experience works.

## Handoff ownership

This is an independent top-level T3 thread on GPT-6 Astra with medium reasoning effort. The user will monitor and continue here. Do not report progress back to the originating LectureClip thread or ask it to supervise. Ask necessary implementation questions directly to the user here; continue authorized independent work while waiting.
