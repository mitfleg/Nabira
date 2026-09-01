# Nabira for Windows

[![Windows build](https://github.com/mitfleg/Nabira/actions/workflows/windows-build.yml/badge.svg)](https://github.com/mitfleg/Nabira/actions/workflows/windows-build.yml)

Стабильное приложение для панели задач с локальной обработкой текста, без телеметрии
и внешних словарных сервисов. Сборка CI создаёт самостоятельный `Nabira.exe` для Windows x64.

## Возможности

Windows-клиент поддерживает вход и регистрацию, серверный семидневный пробный период и проверку
доступа. Токены хранятся в Windows Credential Manager; `settings.json` содержит только обычные
настройки и пользовательские словари.

- **Manual trigger** — double-tap Ctrl (default), double-tap Shift, or the Pause/Break key.
  Converts the last typed word, the current selection, or the whole line into the other layout,
  and switches the keyboard. Trigger it again with nothing typed since to reverse (toggle).
- **Whole-line conversion** (issue #24) — convert the entire current line, not just the last word.
- **Smart selection conversion** (issue #22) — keeps words that are already correct, flips only the
  gibberish (dictionary-driven).
- **Trailing punctuation** kept literally (issue #15) — `ghbdtn,` → `привет,`.
- **Автоконверсия после пробела** — физический пробел перехватывается, а исправленное слово и новый
  пробел отправляются одним пакетом. Это исключает дубли и пропавший текст в Parallels.
- **Разговорные выражения** — повторяющийся смех (`ахахах`, `hahaha`) сохраняется без исправлений.
- **Exception lists** — never-convert / always-convert, editable in Settings → Exceptions.
- **Layout-switch hotkey** (issue #14) — a separate hotkey that only switches the layout.
- **Per-app layout memory** — remembers and restores each application's last-used layout.
- **Layout sound** (issue #7) and a **layout indicator** in the tray menu.
- **Launch at startup**, **signed one-click updates with automatic restart**, and a settings window.
- **Русский интерфейс** — окна настроек, аккаунта, исключений, меню и установщик.

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
  a GitHub release (pre-release for `0.x`). The preferred trusted signer is SignPath Foundation;
  a conventional `WINDOWS_CERT_PFX_BASE64` + `WINDOWS_CERT_PASSWORD` certificate remains supported
  as a fallback. Stable releases fail closed when neither trusted signer is configured. See the
  repository [Code signing policy](../CODE_SIGNING_POLICY.md).
- **Update feed:** `windows/version.json` (separate from the repository-root `version.json`, which is
  the **macOS** feed and must stay where it is). The app checks it once a day, verifies the offline
  release signature, downloads the x64 EXE from `nabira.site`, verifies SHA-256, replaces the
  installed or portable executable atomically, restarts it, and rolls back if startup fails.
- **Installer:** [`installer/Nabira.iss`](installer/Nabira.iss) (Inno Setup, per-user).
- **winget:** manifest templates in [`winget/`](winget/) — see its README for the submission steps.

The Windows version is versioned **separately** from macOS (`win-vX.Y.Z`).
