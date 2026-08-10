using RuSwitcher.Win.Core;
using RuSwitcher.Win.Native;
using RuSwitcher.Win.Tray;
using static RuSwitcher.Win.Native.Win32;

namespace RuSwitcher.Win;

// RuSwitcher for Windows — manual-trigger conversion, mirroring the macOS engine:
// LL hook → keystroke buffer → ToUnicodeEx map → SendInput retype → layout switch. Clipboard-free
// for typed words; a clipboard round-trip is used only for converting an existing selection.
// The trigger defaults to a double-tap of Ctrl (works on all keyboards incl. laptops, doesn't
// disturb typing — the Windows counterpart of the macOS Option double-tap), selectable in the tray.
internal static class Program
{
    [STAThread]  // required for WinForms clipboard / dialogs
    private static void Main()
    {
        string logDir = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "RuSwitcher");
        Directory.CreateDirectory(logDir);
        string logPath = Path.Combine(logDir, "debug.log");
        void Log(string line) => File.AppendAllText(logPath, $"{DateTime.Now:HH:mm:ss.fff} {line}{Environment.NewLine}");

        var settings = Settings.Load();
        var buffer = new KeystrokeBuffer();
        bool enabled = true;

        using var tray = new TrayIcon(settings.Trigger);
        var detector = new TriggerDetector(settings.Trigger);

        // Hook thread: only post a message — the real (possibly slow, clipboard-touching)
        // conversion runs on the message loop so the LL hook callback stays fast.
        detector.Triggered += () => { if (enabled) tray.PostTrigger(); };

        tray.TriggerActivated += () =>
        {
            if (!enabled) return;
            // Trigger again with nothing typed since = reverse the last conversion (toggle);
            // else convert the typed word; else (no typed word) convert the current selection.
            bool acted;
            if (Converter.CanReconvert && buffer.IsEmpty) acted = Converter.Reconvert();
            else if (!buffer.IsEmpty) acted = Converter.ConvertLastWord(buffer);
            else acted = Converter.ConvertSelection();
            Log($"trigger: acted={acted}");
        };
        tray.EnabledChanged += on => { enabled = on; Log($"enabled = {on}"); };
        tray.TriggerChanged += kind =>
        {
            settings.Trigger = kind;
            settings.Save();
            detector.Kind = kind;
            Log($"trigger set: {kind}");
        };
        tray.QuitRequested += () => Log("quit requested");
        tray.Show("RuSwitcher");

        using var hook = new KeyboardHook();
        hook.KeyDown += (vk, sc) =>
        {
            if (!enabled) return;

            detector.OnKeyDown(vk);

            if (KeystrokeBuffer.IsWordBoundary(vk))
            {
                buffer.Reset();
                return;
            }

            if (KeystrokeBuffer.IsTypingKey(vk))
            {
                Converter.ClearReconvert();  // typing changed the word — the pending undo no longer applies
                bool shift = (GetKeyState(VK_SHIFT) & 0x8000) != 0;
                bool caps = (GetKeyState(VK_CAPITAL) & 0x0001) != 0;
                buffer.Append(new TypedKey(vk, sc, shift, caps));
            }
            // Modifiers and other keys: leave the buffer as-is.
        };
        hook.KeyUp += (vk, sc) =>
        {
            if (enabled) detector.OnKeyUp(vk);
        };
        hook.Install();
        Log($"RuSwitcher.Win started — hook + tray up, trigger={settings.Trigger}");

        // Message loop: required for both the LL hook callbacks and the tray window.
        while (GetMessageW(out MSG msg, IntPtr.Zero, 0, 0) > 0)
        {
            TranslateMessage(ref msg);
            DispatchMessageW(ref msg);
        }
    }
}
