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

        var settings = Settings.Current;
        var buffer = new KeystrokeBuffer();
        bool enabled = true;

        // Auto-conversion checks the dictionary inside the hook callback; warm the COM spell-checker
        // now (on this thread — LL-hook callbacks are dispatched here) so the first word isn't slow.
        if (settings.AutoConvert && Dict.Available)
        {
            try { Dict.IsValidWord("test", "en"); Dict.IsValidWord("тест", "ru"); } catch { /* ignore */ }
        }

        using var tray = new TrayIcon();
        var detector = new TriggerDetector(settings.Trigger);

        // Hook thread: only post a message — the real (possibly slow, clipboard-touching)
        // conversion runs on the message loop so the LL hook callback stays fast.
        detector.Triggered += () => { if (enabled) tray.PostTrigger(); };

        // issue #14: a separate hotkey that only switches the layout (fast → safe in-callback).
        var switchDetector = new TriggerDetector(settings.SwitchTrigger);
        switchDetector.Triggered += () =>
        {
            if (enabled && settings.SwitchTriggerEnabled && LayoutSwitcher.Opposite() is { } opp)
                LayoutSwitcher.SwitchTo(opp);
        };

        tray.TriggerActivated += () =>
        {
            if (!enabled) return;
            // Trigger again with nothing typed since = reverse the last conversion (toggle);
            // else whole-line mode → convert the line; else convert the typed word; else the selection.
            bool acted;
            if (Converter.CanReconvert && buffer.IsEmpty) acted = Converter.Reconvert();
            else if (settings.ConvertWholeLine) { acted = Converter.ConvertLine(settings.SmartConversion); if (acted) buffer.Reset(); }
            else if (!buffer.IsEmpty) acted = Converter.ConvertLastWord(buffer);
            else acted = Converter.ConvertSelection(settings.SmartConversion);
            Log($"trigger: acted={acted}");
        };
        tray.EnabledChanged += on => { enabled = on; Log($"enabled = {on}"); };
        tray.TriggerChanged += kind => { detector.Kind = kind; Log($"trigger set: {kind}"); };  // Settings written by the tray
        tray.SettingsRequested += () =>
        {
            using var form = new UI.SettingsForm();
            form.TriggerChanged += kind => detector.Kind = kind;
            form.SwitchChanged += () => switchDetector.Kind = settings.SwitchTrigger;
            form.ShowDialog();   // modal; the message loop keeps pumping the hook + tray
        };
        tray.QuitRequested += () => Log("quit requested");
        tray.Show("RuSwitcher");

        // A hidden WinForms control forces a WindowsFormsSynchronizationContext onto this thread, so
        // the background update check can marshal its message box back here (dispatched by our loop).
        using var uiAnchor = new System.Windows.Forms.Control();
        _ = uiAnchor.Handle;   // force handle creation → installs the sync context
        var ui = SynchronizationContext.Current ?? new SynchronizationContext();
        tray.UpdateRequested += () => Updater.CheckNow(ui);

        using var hook = new KeyboardHook();
        hook.KeyDown += (vk, sc) =>
        {
            if (!enabled) return false;

            detector.OnKeyDown(vk);
            switchDetector.OnKeyDown(vk);

            if (KeystrokeBuffer.IsWordBoundary(vk))
            {
                // As-you-type auto conversion (beta): on Space, flip the just-typed word if the
                // dictionary says it was typed in the wrong layout. When it converts it re-emits the
                // space itself, so we swallow the real one (guarantees word→space ordering).
                bool swallow = false;
                if (vk == KeystrokeBuffer.VK_SPACE && settings.AutoConvert && !buffer.IsEmpty)
                    swallow = AutoConverter.TryConvertWord(buffer);
                buffer.Reset();
                return swallow;
            }

            if (KeystrokeBuffer.IsTypingKey(vk))
            {
                Converter.ClearReconvert();  // typing changed the word — the pending undo no longer applies
                bool shift = (GetKeyState(VK_SHIFT) & 0x8000) != 0;
                bool caps = (GetKeyState(VK_CAPITAL) & 0x0001) != 0;
                buffer.Append(new TypedKey(vk, sc, shift, caps));
            }
            // Modifiers and other keys: leave the buffer as-is.
            return false;
        };
        hook.KeyUp += (vk, sc) =>
        {
            if (!enabled) return;
            detector.OnKeyUp(vk);
            switchDetector.OnKeyUp(vk);
        };
        hook.Install();

        // Per-app layout memory (issue): restores each app's last-used layout on focus. Off by default.
        using var appTracker = new AppLayoutTracker();
        appTracker.Install();

        Updater.CheckOnLaunch(ui);   // silent, throttled once-a-day, off the startup path

        Log($"RuSwitcher.Win started — hook + tray up, trigger={settings.Trigger}");

        // Message loop: required for both the LL hook callbacks and the tray window.
        while (GetMessageW(out MSG msg, IntPtr.Zero, 0, 0) > 0)
        {
            TranslateMessage(ref msg);
            DispatchMessageW(ref msg);
        }
    }
}
