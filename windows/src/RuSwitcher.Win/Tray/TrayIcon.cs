using static RuSwitcher.Win.Native.Win32;

namespace RuSwitcher.Win.Tray;

/// <summary>
/// Menu-bar presence — the Windows counterpart of the macOS NSStatusItem. A hidden message
/// window receives tray callbacks; right-click shows a menu (Enable toggle, Quit).
/// </summary>
internal sealed class TrayIcon : IDisposable
{
    private const uint ID_ENABLE = 1;
    private const uint ID_QUIT = 2;

    // WndProc must be kept alive in a field (same GC pitfall as the hook delegate).
    private readonly WndProc _wndProc;
    private IntPtr _hwnd;
    private NOTIFYICONDATA _nid;
    private bool _enabled = true;

    public event Action<bool>? EnabledChanged;
    public event Action? QuitRequested;

    public TrayIcon() => _wndProc = WindowProc;

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

    private IntPtr WindowProc(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam)
    {
        switch (msg)
        {
            case WM_TRAYICON when (uint)lParam is WM_RBUTTONUP or WM_LBUTTONUP:
                ShowMenu();
                return IntPtr.Zero;

            case WM_COMMAND:
                uint cmd = (uint)(wParam.ToInt64() & 0xFFFF);
                if (cmd == ID_ENABLE) { _enabled = !_enabled; EnabledChanged?.Invoke(_enabled); }
                else if (cmd == ID_QUIT) { QuitRequested?.Invoke(); PostQuitMessage(0); }
                return IntPtr.Zero;

            case WM_DESTROY:
                PostQuitMessage(0);
                return IntPtr.Zero;
        }
        return DefWindowProcW(hWnd, msg, wParam, lParam);
    }

    private void ShowMenu()
    {
        IntPtr menu = CreatePopupMenu();
        AppendMenuW(menu, MF_STRING | (_enabled ? MF_CHECKED : MF_UNCHECKED), ID_ENABLE, "Enable RuSwitcher");
        AppendMenuW(menu, MF_SEPARATOR, 0, null);
        AppendMenuW(menu, MF_STRING, ID_QUIT, "Quit");

        GetCursorPos(out POINT pt);
        SetForegroundWindow(_hwnd); // so the menu dismisses correctly on outside click
        TrackPopupMenu(menu, TPM_RIGHTBUTTON, pt.X, pt.Y, 0, _hwnd, IntPtr.Zero);
        DestroyMenu(menu);
    }

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
