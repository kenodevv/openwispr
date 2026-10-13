# OpenWispr

Hold a key, speak, release. Your words land in whatever you were typing, cleaned up the way you meant them. An open-source dictation app for **macOS** and **Windows**, inspired by Wispr Flow. OpenWispr is an independent project and not affiliated with Wispr.

- **Speech-to-text runs on your machine.** NVIDIA Parakeet TDT v3 (25 European languages incl. German and English), via Core ML on Apple Silicon and ONNX Runtime on Windows. Nothing is uploaded; it works offline and costs nothing.
- **Cleanup by the engine of your choice.** Claude (best quality), a local LLM through Ollama (free), or plain rules (free, instant). The cleanup step removes fillers ("ähm", "uh"), resolves self-corrections ("Monday, no, Tuesday"), adds punctuation, formats lists, and matches the tone of the app you are in: casual in Slack, proper in Mail, prompt-ready in a terminal.
- **Works everywhere.** Text is pasted into the focused field with your clipboard restored afterwards. Personal dictionary, voice snippets, command mode (select text, hold the key with Ctrl/Shift, say "make this formal"), history with stats.

## Install

### macOS (Apple Silicon, macOS 15+)

```bash
brew install xcodegen
git clone https://github.com/kenodevv/openwispr && cd openwispr/mac
make run
```

The first start walks you through Microphone and Accessibility permissions (Accessibility is what lets the app see the Fn key and paste text) and downloads the speech model (~480 MB, once). Set System Settings → Keyboard → "Press 🌐 key to" → **Do Nothing**, otherwise macOS opens the emoji picker. You can also pick any other shortcut in the settings.

Signing: builds are ad-hoc signed by default, which works locally. To keep permissions across rebuilds, create `mac/Local.mk` with your `CODE_SIGN_IDENTITY` and `DEVELOPMENT_TEAM` (see the Makefile). A notarized download will follow once there is a Developer ID.

### Windows (10 / 11, x64)

Download the latest build from the Actions artifacts (release downloads coming) or build it yourself:

```powershell
git clone https://github.com/kenodevv/openwispr; cd openwispr\windows
dotnet publish OpenWispr.Windows -c Release -r win-x64 -o publish
.\publish\OpenWispr.exe
```

No special permissions are needed. The default hold-to-talk key is **Ctrl + Win** (Right Ctrl, Right Alt and F13 are alternatives). The speech model (~600 MB) downloads on first start.

## Using it

| Action | macOS | Windows |
|---|---|---|
| Dictate | hold **Fn**, speak, release | hold **Ctrl + Win**, speak, release |
| Hands-free | tap Fn once, stops after 1.5 s of silence | tap the hotkey once |
| Command mode | select text, hold **Ctrl + Fn**, say what to do | select text, hold **hotkey + Shift** |
| Settings, history, diagnostics | menu bar icon | tray icon |

## Cleanup engines and cost

| Engine | Quality | Latency | Cost |
|---|---|---|---|
| Claude Haiku 5.5 (default) | very good | ~1 s | ≈ 0.015 ¢ per dictation |
| Claude Sonnet 5.5 / Opus 5.5 | best | 2–7 s | ≈ 0.3 / 0.6 ¢ per dictation |
| Ollama (e.g. `qwen3:4b`) | good | 1–3 s on Apple Silicon | free |
| Rules only | basic (fillers, capitalization, dictionary) | instant | free |

Claude needs an API key from [console.anthropic.com](https://console.anthropic.com). On macOS it is stored in the Keychain, on Windows encrypted with DPAPI. Only the transcript text plus app name, window title and up to 500 characters before the cursor are sent; password fields are detected and skipped.

## Repository layout

```
mac/        SwiftUI app (XcodeGen project.yml, Makefile, unit + Parakeet integration tests)
windows/    .NET 8 solution: OpenWispr.Core (shared logic, tests, builds anywhere),
            OpenWispr.Windows (WPF app)
shared/     prompts used by both apps
.github/    CI: macOS build + tests, Windows build + tests, secret scanning
```

Contributions welcome. MIT licensed.
