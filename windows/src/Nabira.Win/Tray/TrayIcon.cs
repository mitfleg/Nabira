using Nabira.Win.Core;
using static Nabira.Win.Native.Win32;

namespace Nabira.Win.Tray;

/// <summary>
/// Menu-bar presence — the Windows counterpart of the macOS NSStatusItem. A hidden message
/// window receives tray callbacks; right-click shows a menu: Enable toggle, a Trigger submenu,
/// a whole-line toggle, «Settings…», and Quit. Menu state is read live from Settings.Current
/// so it stays in sync with the settings window.
/// </summary>
internal sealed class TrayIcon : IDisposable
{
    private readonly WndProc _wndProc;
    private IntPtr _hwnd;
    private NOTIFYICONDATA _nid;
    private bool _enabled = true;
    private bool _accessAllowed;
    private string _accountStatus = L10n.T("account.checking");
    private System.Drawing.Icon? _appIcon;
    private UI.TrayMenuForm? _menu;

    public event Action<bool>? EnabledChanged;
    public event Action<TriggerKind>? TriggerChanged;
    public event Action? SettingsRequested;
    public event Action? UpdateRequested;
    public event Action? AccountRequested;
    public event Action? QuitRequested;
    /// <summary>Fired on the message-loop thread when a trigger was posted from the hook.</summary>
    public event Action? TriggerActivated;
    /// <summary>Fired on the message-loop thread when an as-you-type auto-convert was posted from the hook.</summary>
    public event Action? AutoConvertActivated;
    public event Action? ChangeCaseActivated;

    public TrayIcon() => _wndProc = WindowProc;

    public void SetAccessStatus(string status, bool accessAllowed)
    {
        _accountStatus = status;
        _accessAllowed = accessAllowed;
    }

    /// <summary>Called from the LL hook callback: posts a message so the actual (possibly slow,
    /// clipboard-touching) conversion runs on the message loop, NOT inside the hook callback —
    /// keeping the callback fast so Windows never drops the low-level hook (300ms timeout).</summary>
    public void PostTrigger()
    {
        if (_hwnd != IntPtr.Zero) PostMessageW(_hwnd, WM_APP, IntPtr.Zero, IntPtr.Zero);
    }

    /// <summary>Called from the LL hook callback on a word boundary when auto-convert is armed: posts a
    /// message so the dictionary check + retype run on the message loop, never inside the callback.</summary>
    public void PostAutoConvert()
    {
        if (_hwnd != IntPtr.Zero) PostMessageW(_hwnd, WM_AUTOCONVERT, IntPtr.Zero, IntPtr.Zero);
    }

    public void PostChangeCase()
    {
        if (_hwnd != IntPtr.Zero) PostMessageW(_hwnd, WM_CHANGECASE, IntPtr.Zero, IntPtr.Zero);
    }

    public void Show(string tooltip)
    {
        IntPtr hInstance = GetModuleHandleW(null);
        var wc = new WNDCLASS
        {
            lpfnWndProc = _wndProc,
            hInstance = hInstance,
            lpszClassName = "NabiraTrayWindow",
        };
        RegisterClassW(ref wc);

        _hwnd = CreateWindowExW(0, "NabiraTrayWindow", "Nabira",
            0, 0, 0, 0, 0, IntPtr.Zero, IntPtr.Zero, hInstance, IntPtr.Zero);

        try { _appIcon = System.Drawing.Icon.ExtractAssociatedIcon(System.Windows.Forms.Application.ExecutablePath); }
        catch { _appIcon = null; }
        _nid = new NOTIFYICONDATA
        {
            cbSize = (uint)System.Runtime.InteropServices.Marshal.SizeOf<NOTIFYICONDATA>(),
            hWnd = _hwnd,
            uID = 1,
            uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP,
            uCallbackMessage = WM_TRAYICON,
            hIcon = _appIcon?.Handle ?? LoadIconW(IntPtr.Zero, IDI_APPLICATION),
            szTip = tooltip,
        };
        Shell_NotifyIconW(NIM_ADD, ref _nid);
    }

    internal static string TriggerName(TriggerKind t) => t switch
    {
        TriggerKind.CtrlDoubleTap => L10n.T("trigger.ctrl"),
        TriggerKind.ShiftDoubleTap => L10n.T("trigger.shift"),
        TriggerKind.PauseBreak => L10n.T("trigger.pause"),
        _ => "?",
    };

    /// <summary>issue #7 (indicator): human-readable name of a layout from its HKL primary LANGID.</summary>
    private static string LayoutName(IntPtr hkl) => ((int)hkl.ToInt64() & 0x3FF) switch
    {
        0x19 => "Русский",
        0x09 => "Английский",
        0x22 => "Українська",
        0x23 => "Беларуская",
        0x02 => "Български",
        0x0D => "עברית",
        0x08 => "Ελληνικά",
        0x2B => "Հայերեն",
        0x37 => "ქართული",
        _ => "Раскладка",
    };

    private IntPtr WindowProc(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam)
    {
        switch (msg)
        {
            case WM_TRAYICON when ((uint)(lParam.ToInt64() & 0xFFFF)) is WM_RBUTTONUP or WM_LBUTTONUP:
                ShowMenu();
                return IntPtr.Zero;

            case WM_APP:
                TriggerActivated?.Invoke();
                return IntPtr.Zero;

            case WM_AUTOCONVERT:
                AutoConvertActivated?.Invoke();
                return IntPtr.Zero;

            case WM_CHANGECASE:
                ChangeCaseActivated?.Invoke();
                return IntPtr.Zero;

            case WM_DESTROY:
                PostQuitMessage(0);
                return IntPtr.Zero;
        }
        return DefWindowProcW(hWnd, msg, wParam, lParam);
    }

    private void SetTrigger(TriggerKind t)
    {
        if (t == Settings.Current.Trigger) return;
        Settings.Current.Trigger = t;
        Settings.Current.Save();
        TriggerChanged?.Invoke(t);
    }

    private void ShowMenu()
    {
        var s = Settings.Current;
        _menu?.Close();
        var popup = new UI.TrayMenuForm(
            LayoutName(LayoutSwitcher.Current()),
            _accountStatus,
            _accessAllowed,
            _enabled,
            s.Trigger,
            s.ConvertWholeLine,
            s.AutoConvert,
            on => { _enabled = on; EnabledChanged?.Invoke(on); },
            SetTrigger,
            on => { s.ConvertWholeLine = on; s.Save(); },
            on => { s.AutoConvert = on; s.Save(); },
            () => AccountRequested?.Invoke(),
            () => SettingsRequested?.Invoke(),
            () => UpdateRequested?.Invoke(),
            () => { QuitRequested?.Invoke(); PostQuitMessage(0); });
        popup.FormClosed += (_, _) =>
        {
            if (ReferenceEquals(_menu, popup)) _menu = null;
            popup.Dispose();
        };
        _menu = popup;
        GetCursorPos(out POINT pt);
        popup.ShowAt(new System.Drawing.Point(pt.X, pt.Y));
    }

    public void Dispose()
    {
        _menu?.Close();
        _menu = null;
        if (_hwnd != IntPtr.Zero)
        {
            Shell_NotifyIconW(NIM_DELETE, ref _nid);
            DestroyWindow(_hwnd);
            _hwnd = IntPtr.Zero;
        }
        _appIcon?.Dispose();
        _appIcon = null;
    }
}
