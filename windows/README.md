# RuSwitcher for Windows

**Status: planned.** This directory is reserved for the Windows version.

The design is settled (see [`../shared/docs/`](../shared/docs/)): a tray application
built on the same philosophy as the macOS original — zero external dependencies,
no telemetry, local dictionaries, keycode-based conversion.

| macOS mechanism | Windows counterpart |
|---|---|
| CGEventTap | `SetWindowsHookEx(WH_KEYBOARD_LL)` |
| CGEvent keyboardSetUnicodeString | `SendInput` + `KEYEVENTF_UNICODE` |
| Carbon `UCKeyTranslate` | `ToUnicodeEx` |
| TIS layout switching | `WM_INPUTLANGCHANGEREQUEST` |
| NSSpellChecker | `ISpellChecker` (Windows 8+) |
| NSStatusItem | `Shell_NotifyIcon` |

Release artifacts will use their own tags (`win-vX.Y.Z`) and their own update feed
(`windows/version.json`). The repository-root `version.json` is the **macOS** update
feed and must stay where it is.
