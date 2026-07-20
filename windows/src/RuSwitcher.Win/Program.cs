using RuSwitcher.Win.Core;
using RuSwitcher.Win.Native;
using RuSwitcher.Win.Tray;
using static RuSwitcher.Win.Native.Win32;

// RuSwitcher for Windows — stage 1 MVP (manual trigger).
// Type a word in the wrong layout, press the trigger (Pause/Break), and the last word is
// converted in place (delete + retype in the opposite layout) and the layout is switched.
// Mirrors the macOS engine: LL hook (CGEventTap) → keystroke buffer (KeyboardMonitor) →
// ToUnicodeEx map (UCKeyTranslate) → SendInput retype (TextConverter) → layout switch (TIS).
// Clipboard-free, zero dependencies.

const uint VK_PAUSE = 0x13; // trigger (Pause/Break) — a dedicated key that doesn't disturb typing

string logDir = Path.Combine(
    Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "RuSwitcher");
Directory.CreateDirectory(logDir);
string logPath = Path.Combine(logDir, "debug.log");
void Log(string line) => File.AppendAllText(logPath, $"{DateTime.Now:HH:mm:ss.fff} {line}{Environment.NewLine}");

var buffer = new KeystrokeBuffer();
bool enabled = true;

using var tray = new TrayIcon();
tray.EnabledChanged += on => { enabled = on; Log($"enabled = {on}"); };
tray.QuitRequested += () => Log("quit requested");
tray.Show("RuSwitcher");

using var hook = new KeyboardHook();
hook.KeyDown += (vk, sc) =>
{
    if (!enabled) return;

    if (vk == VK_PAUSE)
    {
        bool acted = Converter.ConvertLastWord(buffer);
        Log($"trigger: converted={acted}");
        return;
    }

    if (KeystrokeBuffer.IsWordBoundary(vk))
    {
        buffer.Reset();
        return;
    }

    if (KeystrokeBuffer.IsTypingKey(vk))
    {
        bool shift = (GetKeyState(VK_SHIFT) & 0x8000) != 0;
        bool caps = (GetKeyState(VK_CAPITAL) & 0x0001) != 0;
        buffer.Append(new TypedKey(vk, sc, shift, caps));
    }
    // Modifiers and other keys: leave the buffer as-is.
};
hook.Install();
Log("RuSwitcher.Win MVP started — hook + tray up");

// Message loop: required for both the LL hook callbacks and the tray window.
while (GetMessageW(out MSG msg, IntPtr.Zero, 0, 0) > 0)
{
    TranslateMessage(ref msg);
    DispatchMessageW(ref msg);
}
