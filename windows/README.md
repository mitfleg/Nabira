# Nabira for Windows

[![Windows build](https://github.com/mitfleg/Nabira/actions/workflows/windows-build.yml/badge.svg)](https://github.com/mitfleg/Nabira/actions/workflows/windows-build.yml)

**Status: beta.** A tray application built on the same philosophy as the macOS original —
zero external dependencies, no telemetry, local dictionaries, keycode-based conversion.

## Current beta features

The keyboard-conversion engine is usable for testing. Account sign-in, the seven-day trial,
subscription enforcement, and some newer macOS writing-assistance features are not yet ported.
Future Windows session tokens must be stored with Windows Credential Manager or DPAPI; the plain
`settings.json` file remains reserved for non-secret preferences and user dictionaries.

- **Manual trigger** — double-tap Ctrl (default), double-tap Shift, or the Pause/Break key.
  Converts the last typed word, the current selection, or the whole line into the other layout,
  and switches the keyboard. Trigger it again with nothing typed since to reverse (toggle).
- **Whole-line conversion** (issue #24) — convert the entire current line, not just the last word.
- **Smart selection conversion** (issue #22) — keeps words that are already correct, flips only the
  gibberish (dictionary-driven).
- **Trailing punctuation** kept literally (issue #15) — `ghbdtn,` → `привет,`.
- **As-you-type auto conversion** (beta, off by default) — flips a word right after Space when the
  dictionary is confident it was typed in the wrong layout. Precision over recall; reversing an
  auto-conversion with the trigger teaches a "never convert" exception (learn-from-undo).
- **Exception lists** — never-convert / always-convert, editable in Settings → Exceptions.
- **Layout-switch hotkey** (issue #14) — a separate hotkey that only switches the layout.
- **Per-app layout memory** — remembers and restores each application's last-used layout.
- **Layout sound** (issue #7) and a **layout indicator** in the tray menu.
- **Launch at startup**, **auto-update check**, and a settings window.
- **Localized UI** — English and Russian (more languages to follow; falls back to English).

## Engine mapping

| macOS mechanism | Windows counterpart |
|---|---|
| CGEventTap | `SetWindowsHookEx(WH_KEYBOARD_LL)` |
| CGEvent keyboardSetUnicodeString | `SendInput` + `KEYEVENTF_UNICODE` |
| Carbon `UCKeyTranslate` | `ToUnicodeEx` |
| TIS layout switching | `WM_INPUTLANGCHANGEREQUEST` |
| NSSpellChecker | `ISpellChecker` (Windows 8+) |
| NSStatusItem | `Shell_NotifyIcon` |
| per-app frontmost observer | `SetWinEventHook(EVENT_SYSTEM_FOREGROUND)` |

## Build & test

Requires the .NET 8 SDK. On Windows:

```
dotnet build   windows/src/Nabira.Win/Nabira.Win.csproj -c Release
dotnet test    windows/tests/Nabira.Win.Tests/Nabira.Win.Tests.csproj -c Release
dotnet publish windows/src/Nabira.Win/Nabira.Win.csproj -c Release -r win-x64 `
  --self-contained true -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true
```

The project sets `EnableWindowsTargeting`, so it also **compiles** on macOS/Linux (a fast
compile-check); the real build/test/exe come from the `windows-build` CI on a Windows runner. The
P/Invoke code cannot *run* off Windows.

## Distribution

- **Release track:** push a `win-vX.Y.Z` tag → the `windows-release` workflow builds, tests, publishes
  the single-file exe (x64 + arm64), compiles the Inno Setup installer, computes SHA-256, and creates
  a GitHub release (pre-release for `0.x`). Code signing runs automatically **if** the
  `WINDOWS_CERT_PFX_BASE64` + `WINDOWS_CERT_PASSWORD` secrets are set; otherwise it ships unsigned.
- **Update feed:** `windows/version.json` (separate from the repository-root `version.json`, which is
  the **macOS** feed and must stay where it is). The app checks it once a day and offers to open the
  download page.
- **Installer:** [`installer/Nabira.iss`](installer/Nabira.iss) (Inno Setup, per-user).
- **winget:** manifest templates in [`winget/`](winget/) — see its README for the submission steps.

The Windows version is versioned **separately** from macOS (`win-vX.Y.Z`).
