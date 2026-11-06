# Codex companion

ScreenSage's **Codex · ChatGPT sign-in** option uses the official Codex app-server. This is a small single-user bridge on your own Mac/Linux computer; it must remain reachable from the phone. Custom-provider mode does not require it.

## Setup

1. Install Python 3.11+ and Codex CLI. The protocol was checked with `codex-cli 0.166.0`; use that version for this demo (`npm install -g @openai/codex@0.166.0`). Older/different versions may reject fields or change available tools.
2. In this directory run:

   ```sh
   python3 -m venv .venv
   .venv/bin/pip install -r requirements.txt
   ```

3. Set `SCREENSAGE_CONNECTION_KEY` privately in the companion's environment to a randomly generated password of at least 32 characters. Store it in your password manager. Do not paste it into chat, commit it, or put it in a URL. This key protects your bridge; it is **not** an OpenAI API key.
4. Run `.venv/bin/python server.py`. It listens only on `127.0.0.1:8765`. Use your own HTTPS reverse proxy or private-network HTTPS forwarding to reach it from your phone. Forward to that loopback port, preserve Authorization, disable request/body logging, and allow a 6.1 MB body and 100-second request timeout. Never expose its plain HTTP listener directly. HTTPS certificates must be trusted by iOS.
5. In ScreenSage → Connection choose **Codex · ChatGPT sign-in**. Enter the HTTPS bridge URL (no `/v1`) and connection key.
6. Tap **Continue with ChatGPT**. Open the OpenAI link, enter the displayed one-time code, and approve sign-in. If OpenAI requires it, enable device-code login in your account's security settings. Tap **Check sign-in & models** afterwards. Copy an available vision model identifier into the model field, then Save and Test vision connection.

The app does not accept your ChatGPT password. Codex owns OAuth and refresh. The companion uses a **separate** `~/.screensage/codex` home with owner-only permissions and never reads the coding agent's tokens. Optional `SCREENSAGE_CODEX_HOME` must identify a separate directory. Do not copy an existing `auth.json` into it. Treat the companion host and HTTPS endpoint as trusted: they see screen content and can use the connected account.

## Behavior and limits

- One analysis at a time; competing requests get HTTP 409. Image/prompt sizes and turn time are bounded. Client disconnection cancels the handler; the current turn is interrupted and its process terminated. Reverse proxies may delay disconnect propagation; the turn timeout still applies.
- Each request creates an **ephemeral Codex thread**, sends a text prompt and image input, waits for `turn/completed`, then closes the process. The phone displays its thread ID and keeps the last 20 answers, with only four short answers sent as recent context. This is not a persistent Codex chat browser; temporary threads intentionally avoid indefinite screenshot history.
- Shell, execution, browser, file-viewing, connectors, plugins and delegation features are disabled. Server-initiated tool/permission requests are rejected. The protocol check verifies that this pinned CLI exposes no tools for the test turn. No arbitrary RPC endpoint is exposed.
- This is a personal/open-source app-server integration, not a hosted multi-user subscription gateway. Official docs say app-server authentication is not permitted for commercial or hosted services; those should use approved Sign in with ChatGPT integration.
- Account eligibility, model availability and Codex usage limits still apply. Authentication and real vision inference were **not tested with a user's account** for this release.
- Sign out in the app to remove Codex authorization from the companion. Stop the companion process when finished. Provider-side retention cannot be undone by clearing the app.

## Tests

```sh
.venv/bin/python -m unittest discover -s . -v
# From repository root, with the pinned Codex CLI installed:
companion/.venv/bin/python companion/check_protocol.py
```

The tests use synthetic inputs and a local fake model server. They do not establish real OpenAI authentication or vision quality.

Sources: [app-server authentication and image input](https://learn.chatgpt.com/docs/app-server), [Sign in with ChatGPT alternative](https://developers.openai.com/siwc). The latter also supports direct plan-usage Responses with dynamic registration, but this demo uses Codex app-server as requested.
