using System.Text;
using static RuSwitcher.Win.Native.Win32;

namespace RuSwitcher.Win.Core;

/// <summary>
/// Per-app keyboard-layout memory — the Windows counterpart of the macOS per-app layout feature.
/// Watches foreground-window changes (SetWinEventHook / EVENT_SYSTEM_FOREGROUND): when an app loses
/// focus its current layout is remembered against its process name, and when an app regains focus its
/// remembered layout is restored. Off unless <see cref="Settings.PerAppLayout"/>. Fully defensive.
/// </summary>
internal sealed class AppLayoutTracker : IDisposable
{
    // The callback delegate must be held in a field (else it's collected and the native call crashes).
    private readonly WinEventProc _proc;
    private IntPtr _hook;
    private string? _lastApp;   // process name of the app we last saw focused

    public AppLayoutTracker() => _proc = OnForeground;

    public void Install()
    {
        // SKIPOWNPROCESS: never react to our own tray/settings windows getting focus.
        _hook = SetWinEventHook(EVENT_SYSTEM_FOREGROUND, EVENT_SYSTEM_FOREGROUND, IntPtr.Zero,
            _proc, 0, 0, WINEVENT_OUTOFCONTEXT | WINEVENT_SKIPOWNPROCESS);
    }

    private void OnForeground(IntPtr hHook, uint ev, IntPtr hwnd, int idObj, int idChild, uint thread, uint time)
    {
        try
        {
            if (!Settings.Current.PerAppLayout || hwnd == IntPtr.Zero) return;

            // Remember the layout the *previous* app was using (it just lost focus).
            if (_lastApp is { } prev)
            {
                string prevTag = SmartConvert.LangTag(LayoutSwitcher.Current());
                int prevLangId = LangIdFromTag(prevTag);
                if (prevLangId != 0)
                {
                    Settings.Current.AppLayouts[prev] = prevLangId;
                    Settings.Current.Save();
                }
            }

            string? app = ProcessName(hwnd);
            _lastApp = app;
            if (app == null) return;

            // Restore the layout remembered for the app that just gained focus.
            if (Settings.Current.AppLayouts.TryGetValue(app, out int langId) &&
                InstalledHklForLangId(langId) is { } hkl && hkl != LayoutSwitcher.Current())
            {
                if (hwnd != IntPtr.Zero) PostMessageW(hwnd, WM_INPUTLANGCHANGEREQUEST, IntPtr.Zero, hkl);
            }
        }
        catch { /* never let a shell event crash us */ }
    }

    /// <summary>Lower-cased executable base name (no ".exe") of the process owning a window.</summary>
    private static string? ProcessName(IntPtr hwnd)
    {
        GetWindowThreadProcessId(hwnd, out uint pid);
        if (pid == 0) return null;
        IntPtr h = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, pid);
        if (h == IntPtr.Zero) return null;
        try
        {
            var sb = new StringBuilder(1024);
            uint cap = (uint)sb.Capacity;
            if (!QueryFullProcessImageNameW(h, 0, sb, ref cap)) return null;
            string path = sb.ToString();
            string name = System.IO.Path.GetFileNameWithoutExtension(path);
            return string.IsNullOrEmpty(name) ? null : name.ToLowerInvariant();
        }
        finally { CloseHandle(h); }
    }

    private static IntPtr? InstalledHklForLangId(int langId)
    {
        foreach (var hkl in LayoutSwitcher.Installed())
            if (((int)hkl.ToInt64() & 0x3FF) == langId) return hkl;
        return null;
    }

    private static int LangIdFromTag(string tag) => tag switch
    {
        "ru" => 0x19, "en" => 0x09, "uk" => 0x22, "be" => 0x23, "bg" => 0x02,
        "he" => 0x0D, "el" => 0x08, "hy" => 0x2B, "ka" => 0x37, _ => 0,
    };

    public void Dispose()
    {
        if (_hook != IntPtr.Zero) { UnhookWinEvent(_hook); _hook = IntPtr.Zero; }
    }
}
