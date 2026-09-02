using Nabira.Win.Core;
using Nabira.Win.Native;
using Nabira.Win.Tray;
using static Nabira.Win.Native.Win32;

namespace Nabira.Win;

// Nabira for Windows — manual-trigger conversion, mirroring the macOS engine:
// LL hook → keystroke buffer → ToUnicodeEx map → SendInput retype → layout switch. Clipboard-free
// for typed words; a clipboard round-trip is used only for converting an existing selection.
// The trigger defaults to a double-tap of Ctrl (works on all keyboards incl. laptops, doesn't
// disturb typing — the Windows counterpart of the macOS Option double-tap), selectable in the tray.
internal static class Program
{
    [STAThread]  // required for WinForms clipboard / dialogs
    private static void Main(string[] args)
    {
        System.Windows.Forms.Application.EnableVisualStyles();
        System.Windows.Forms.Application.SetCompatibleTextRenderingDefault(false);
        if (UpdateInstaller.TryRunApplyMode(args)) return;
        UpdateInstaller.CleanupStaleDownloads();
        string logDir = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Nabira");
        Directory.CreateDirectory(logDir);
        string logPath = Path.Combine(logDir, "debug.log");
        void Log(string line) => File.AppendAllText(logPath, $"{DateTime.Now:HH:mm:ss.fff} {line}{Environment.NewLine}");

        // Capture crashes to the log instead of dying silently (a tester can then send debug.log).
        AppDomain.CurrentDomain.UnhandledException += (_, e) =>
        { try { Log("FATAL: " + (e.ExceptionObject as Exception)?.ToString()); } catch { /* ignore */ } };
        System.Windows.Forms.Application.ThreadException += (_, e) =>
        { try { Log("THREAD-EX: " + e.Exception); } catch { /* ignore */ } };

        var settings = Settings.Current;
        var buffer = new KeystrokeBuffer();
        bool userEnabled = true;
        var pendingAutomatic = new Queue<CompletedWord>(); // captured Space/Enter snapshots for the message loop

        // Force a WindowsFormsSynchronizationContext before starting network/account work.
        using var uiAnchor = new System.Windows.Forms.Control();
        _ = uiAnchor.Handle;
        var ui = SynchronizationContext.Current ?? new SynchronizationContext();
        using var access = new AccountAccessManager(ui);
        bool EffectiveEnabled() => userEnabled && access.HasAccess;

        // Auto-conversion checks the dictionary on the message loop; warm the COM spell-checker for the
        // actually-installed layout languages now, so the first auto-convert of the session isn't slow.
        if (settings.AutoConvert && Dict.Available)
        {
            try
            {
                foreach (var hkl in LayoutSwitcher.Installed())
                    Dict.IsValidWord("test", SmartConvert.LangTag(hkl));
            }
            catch { /* ignore */ }
        }

        using var tray = new TrayIcon();
        var detector = new TriggerDetector(settings.Trigger);

        // Hook thread: only post a message — the real (possibly slow, clipboard-touching)
        // conversion runs on the message loop so the LL hook callback stays fast.
        detector.Triggered += () => { if (EffectiveEnabled()) tray.PostTrigger(); };

        // issue #14: a separate hotkey that only switches the layout (fast → safe in-callback).
        var switchDetector = new TriggerDetector(settings.SwitchTrigger);
        switchDetector.Triggered += () =>
        {
            if (EffectiveEnabled() && settings.SwitchTriggerEnabled && LayoutSwitcher.Opposite() is { } opp)
                LayoutSwitcher.SwitchTo(opp);
        };

        var caseDetector = new TriggerDetector(settings.CaseTrigger);
        caseDetector.Triggered += () =>
        {
            if (EffectiveEnabled() && settings.CaseTriggerEnabled) tray.PostChangeCase();
        };

        tray.TriggerActivated += () =>
        {
            if (!EffectiveEnabled()) return;
            // An explicit user selection always wins over the stale typed-word buffer and
            // whole-line mode. With a buffered fallback one quick clipboard probe is enough;
            // without one, retry slower applications before giving up.
            bool acted;
            bool quickSelectionProbe = !buffer.IsEmpty || Converter.CanReconvert || settings.ConvertWholeLine;
            if (Converter.ConvertSelection(settings.SmartConversion, quickSelectionProbe))
            {
                buffer.Reset();
                acted = true;
            }
            else if (Converter.CanReconvert && buffer.IsEmpty) acted = Converter.Reconvert();
            else if (settings.ConvertWholeLine) { acted = Converter.ConvertLine(settings.SmartConversion); if (acted) buffer.Reset(); }
            else if (!buffer.IsEmpty) acted = Converter.ConvertLastWord(buffer);
            else acted = false;
            Log($"trigger: acted={acted}");
        };
        tray.AutoConvertActivated += () =>
        {
            // The physical boundary was swallowed by the hook. One pipeline now injects correction
            // and exactly one replacement Space/Enter as a single, ordered SendInput batch.
            if (pendingAutomatic.TryDequeue(out var word))
            {
                try { WritingAssistant.TryProcessCaptured(word); }
                catch (Exception ex)
                {
                    Log("auto-convert failed: " + ex);
                    TextInjector.SendKey((ushort)word.BoundaryVk);
                }
            }
        };
        tray.ChangeCaseActivated += () =>
        {
            if (!EffectiveEnabled()) return;
            bool acted = settings.ConvertWholeLine
                ? Converter.CycleCaseLine()
                : !buffer.IsEmpty ? Converter.CycleLastWord(buffer) : Converter.CycleCaseSelection();
            Log($"change-case: acted={acted}");
        };
        tray.EnabledChanged += on => { userEnabled = on; Log($"enabled = {on}"); };
        tray.TriggerChanged += kind => { detector.Kind = kind; Log($"trigger set: {kind}"); };  // Settings written by the tray
        tray.SettingsRequested += () =>
        {
            using var form = new UI.SettingsForm();
            form.TriggerChanged += kind => detector.Kind = kind;
            form.SwitchChanged += () => switchDetector.Kind = settings.SwitchTrigger;
            form.CaseChanged += () => caseDetector.Kind = settings.CaseTrigger;
            form.ShowDialog();   // modal; the message loop keeps pumping the hook + tray
        };
        tray.QuitRequested += () => Log("quit requested");
        tray.Show("Nabira");

        UI.AccountForm? accountForm = null;
        void ShowAccount()
        {
            if (accountForm == null || accountForm.IsDisposed)
                accountForm = new UI.AccountForm(access);
            accountForm.Show();
            accountForm.Activate();
        }
        tray.AccountRequested += ShowAccount;
        access.Changed += snapshot =>
        {
            tray.SetAccessStatus(access.MenuTitle, snapshot.HasAccess);
            Log($"access: allowed={snapshot.HasAccess} trial_days={snapshot.TrialDaysRemaining} authenticated={snapshot.Authenticated}");
            if (!snapshot.HasAccess && snapshot.Error == null) ShowAccount();
        };
        tray.SetAccessStatus(L10n.T("account.checking"), false);
        _ = access.RefreshAsync();

        void RequestExit() => ui.Post(_ => PostQuitMessage(0), null);
        tray.UpdateRequested += () => Updater.CheckNow(ui, RequestExit);

        using var hook = new KeyboardHook();
        hook.KeyDown += (vk, sc) =>
        {
            if (!EffectiveEnabled()) return false;

            // Ctrl+Shift+V: temporarily strip formatting from the clipboard while the original
            // shortcut continues to the focused application.
            if (vk == VK_V && (GetAsyncKeyState(VK_CONTROL) & 0x8000) != 0
                && (GetAsyncKeyState(VK_SHIFT) & 0x8000) != 0
                && (GetAsyncKeyState(VK_MENU) & 0x8000) == 0)
            {
                PlainTextPaste.Prepare(ui);
                buffer.Reset();
                Converter.ClearReconvert();
                return false;
            }

            detector.OnKeyDown(vk);
            switchDetector.OnKeyDown(vk);
            caseDetector.OnKeyDown(vk);

            bool commandModifier = (GetAsyncKeyState(VK_CONTROL) & 0x8000) != 0
                || (GetAsyncKeyState(VK_MENU) & 0x8000) != 0
                || (GetAsyncKeyState(0x5B) & 0x8000) != 0
                || (GetAsyncKeyState(0x5C) & 0x8000) != 0;
            if (commandModifier && KeystrokeBuffer.IsTypingKey(vk))
            {
                buffer.Reset();
                Converter.ClearReconvert();
                return false;
            }

            if (vk == KeystrokeBuffer.VK_BACK)
            {
                buffer.RemoveLast();
                Converter.ClearReconvert();
                return false;
            }

            if (KeystrokeBuffer.IsWordBoundary(vk))
            {
                // Capture Space and a bare Enter. Enter must be delayed so a chat application cannot
                // submit the wrong-layout text before the message-loop correction is injected.
                // Modified Enter and Tab keep their application-specific semantics.
                bool hasSubmitModifier = commandModifier
                    || (GetAsyncKeyState(VK_SHIFT) & 0x8000) != 0;
                bool capturedBoundary = vk == KeystrokeBuffer.VK_SPACE
                    || (vk == KeystrokeBuffer.VK_RETURN && !hasSubmitModifier);
                if (capturedBoundary && WritingAssistant.Enabled && !buffer.IsEmpty)
                {
                    pendingAutomatic.Enqueue(new CompletedWord(new List<TypedKey>(buffer.CurrentWord), vk));
                    tray.PostAutoConvert();
                    buffer.Reset();
                    return true;
                }
                buffer.Reset();
                return false;
            }

            if (KeystrokeBuffer.IsTypingKey(vk))
            {
                Converter.ClearReconvert();  // typing changed the word — the pending undo no longer applies
                // GetAsyncKeyState = real hardware state; GetKeyState would be stale on the hook thread.
                bool shift = (GetAsyncKeyState(VK_SHIFT) & 0x8000) != 0;
                bool caps = (GetKeyState(VK_CAPITAL) & 0x0001) != 0;
                buffer.Append(new TypedKey(vk, sc, shift, caps));
            }
            else if (!KeystrokeBuffer.IsModifierKey(vk))
            {
                // Navigation, Delete and application shortcuts move the caret or mutate text.
                // Keeping the old word would make the next correction delete unrelated characters.
                buffer.Reset();
                Converter.ClearReconvert();
            }

            return false;
        };
        hook.KeyUp += (vk, sc) =>
        {
            if (!EffectiveEnabled()) return;
            detector.OnKeyUp(vk);
            switchDetector.OnKeyUp(vk);
            caseDetector.OnKeyUp(vk);
        };
        hook.Install();

        // Per-app layout memory (issue): restores each app's last-used layout on focus. Off by default.
        using var appTracker = new AppLayoutTracker();
        appTracker.Install();

        Updater.StartAutomaticChecks(ui, RequestExit); // daily, including long-running sessions

        Log($"Nabira.Win started — hook + tray up, trigger={settings.Trigger}");

        // Message loop: required for both the LL hook callbacks and the tray window.
        while (GetMessageW(out MSG msg, IntPtr.Zero, 0, 0) > 0)
        {
            TranslateMessage(ref msg);
            DispatchMessageW(ref msg);
        }
    }
}
