using RuSwitcher.Win.Core;
using static RuSwitcher.Win.Native.Win32;

namespace RuSwitcher.Win.Tray;

/// <summary>
/// Menu-bar presence — the Windows counterpart of the macOS NSStatusItem. A hidden message
/// window receives tray callbacks; right-click shows a menu: Enable toggle, a Trigger submenu
/// (so the shortcut is discoverable and selectable), and Quit.
/// </summary>
internal sealed class TrayIcon : IDisposable
{
    private const uint ID_ENABLE = 1;
    private const uint ID_QUIT = 2;
    private const uint ID_TRIG_CTRL = 10;
    private const uint ID_TRIG_SHIFT = 11;
    private const uint ID_TRIG_PAUSE = 12;
    private const uint ID_WHOLELINE = 13;

    private readonly WndProc _wndProc;
    private IntPtr _hwnd;
    private NOTIFYICONDATA _nid;
    private bool _enabled = true;
    private TriggerKind _trigger;
    private bool _wholeLine;

    public event Action<bool>? EnabledChanged;
    public event Action<TriggerKind>? TriggerChanged;
    public event Action<bool>? WholeLineChanged;
    public event Action? QuitRequested;
    /// <summary>Fired on the message-loop thread when a trigger was posted from the hook.</summary>
    public event Action? TriggerActivated;

    /// <summary>Called from the LL hook callback: posts a message so the actual (possibly slow,
    /// clipboard-touching) conversion runs on the message loop, NOT inside the hook callback —
    /// keeping the callback fast so Windows never drops the low-level hook (300ms timeout).</summary>
    public void PostTrigger()
    {
        if (_hwnd != IntPtr.Zero) PostMessageW(_hwnd, WM_APP, IntPtr.Zero, IntPtr.Zero);
    }

    public TrayIcon(TriggerKind trigger, bool wholeLine)
    {
        _trigger = trigger;
        _wholeLine = wholeLine;
        _wndProc = WindowProc;
    }

    public void Show(string tooltip)
    {
        IntPtr hInstance = GetModuleHandleW(null);
        var wc = new WNDCLASS
        {
            lpfnWndProc = _wndProc,
            hInstance = hInstance,
            lpszClassName = "RuSwitcherTrayWindow",
        };
        RegisterClassW(ref wc);

        _hwnd = CreateWindowExW(0, "RuSwitcherTrayWindow", "RuSwitcher",
            0, 0, 0, 0, 0, IntPtr.Zero, IntPtr.Zero, hInstance, IntPtr.Zero);

        _nid = new NOTIFYICONDATA
        {
            cbSize = (uint)System.Runtime.InteropServices.Marshal.SizeOf<NOTIFYICONDATA>(),
            hWnd = _hwnd,
            uID = 1,
            uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP,
            uCallbackMessage = WM_TRAYICON,
            hIcon = LoadIconW(IntPtr.Zero, IDI_APPLICATION),
            szTip = tooltip,
        };
        Shell_NotifyIconW(NIM_ADD, ref _nid);
    }

    private static string TriggerName(TriggerKind t) => t switch
    {
        TriggerKind.CtrlDoubleTap => "Double-tap Ctrl",
        TriggerKind.ShiftDoubleTap => "Double-tap Shift",
        TriggerKind.PauseBreak => "Pause/Break key",
        _ => "?",
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

            case WM_COMMAND:
                uint cmd = (uint)(wParam.ToInt64() & 0xFFFF);
                switch (cmd)
                {
                    case ID_ENABLE: _enabled = !_enabled; EnabledChanged?.Invoke(_enabled); break;
                    case ID_QUIT: QuitRequested?.Invoke(); PostQuitMessage(0); break;
                    case ID_TRIG_CTRL: SetTrigger(TriggerKind.CtrlDoubleTap); break;
                    case ID_TRIG_SHIFT: SetTrigger(TriggerKind.ShiftDoubleTap); break;
                    case ID_TRIG_PAUSE: SetTrigger(TriggerKind.PauseBreak); break;
                    case ID_WHOLELINE: _wholeLine = !_wholeLine; WholeLineChanged?.Invoke(_wholeLine); break;
                }
                return IntPtr.Zero;

            case WM_DESTROY:
                PostQuitMessage(0);
                return IntPtr.Zero;
        }
        return DefWindowProcW(hWnd, msg, wParam, lParam);
    }

    private void SetTrigger(TriggerKind t)
    {
        if (t == _trigger) return;
        _trigger = t;
        TriggerChanged?.Invoke(t);
    }

    private void ShowMenu()
    {
        IntPtr menu = CreatePopupMenu();
        AppendMenuW(menu, MF_STRING | (_enabled ? MF_CHECKED : MF_UNCHECKED), ID_ENABLE, "Enable RuSwitcher");

        IntPtr sub = CreatePopupMenu();
        AppendMenuW(sub, MF_STRING | Check(TriggerKind.CtrlDoubleTap), ID_TRIG_CTRL, TriggerName(TriggerKind.CtrlDoubleTap));
        AppendMenuW(sub, MF_STRING | Check(TriggerKind.ShiftDoubleTap), ID_TRIG_SHIFT, TriggerName(TriggerKind.ShiftDoubleTap));
        AppendMenuW(sub, MF_STRING | Check(TriggerKind.PauseBreak), ID_TRIG_PAUSE, TriggerName(TriggerKind.PauseBreak));
        AppendSubMenuW(menu, MF_STRING | MF_POPUP, sub, $"Trigger: {TriggerName(_trigger)}");

        AppendMenuW(menu, MF_STRING | (_wholeLine ? MF_CHECKED : MF_UNCHECKED), ID_WHOLELINE, "Convert whole line");

        AppendMenuW(menu, MF_SEPARATOR, 0, null);
        AppendMenuW(menu, MF_STRING, ID_QUIT, "Quit");

        GetCursorPos(out POINT pt);
        SetForegroundWindow(_hwnd); // so the menu dismisses correctly on outside click
        TrackPopupMenu(menu, TPM_RIGHTBUTTON, pt.X, pt.Y, 0, _hwnd, IntPtr.Zero);
        DestroyMenu(menu);
    }

    private uint Check(TriggerKind t) => t == _trigger ? MF_CHECKED : MF_UNCHECKED;

    public void Dispose()
    {
        if (_hwnd != IntPtr.Zero)
        {
            Shell_NotifyIconW(NIM_DELETE, ref _nid);
            DestroyWindow(_hwnd);
            _hwnd = IntPtr.Zero;
        }
    }
}
