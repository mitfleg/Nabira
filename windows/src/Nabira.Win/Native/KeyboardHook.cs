using System.Runtime.InteropServices;
using static Nabira.Win.Native.Win32;

namespace Nabira.Win.Native;

/// <summary>
/// Low-level keyboard hook (WH_KEYBOARD_LL) — the Windows counterpart of the macOS CGEventTap.
/// Raises <see cref="KeyDown"/> for every real key press (our own injected events, tagged with
/// <see cref="InjectedMarker"/>, are filtered out — the event-marker trick from the macOS app).
/// </summary>
internal sealed class KeyboardHook : IDisposable
{
    // The delegate MUST be held in a field: if it is collected, the native callback points at
    // freed memory and the process crashes. (Classic P/Invoke hook pitfall.)
    private readonly LowLevelKeyboardProc _proc;
    private IntPtr _hook;
    private readonly HashSet<uint> _suppressedKeyUps = new();

    /// <summary>(vkCode, scanCode) of a real key press. Return true to keep the key away from
    /// the focused application. Nabira uses this only for a captured word-boundary key.</summary>
    public event Func<uint, uint, bool>? KeyDown;

    /// <summary>(vkCode, scanCode) of a real key release — needed for modifier double-tap.</summary>
    public event Action<uint, uint>? KeyUp;

    public KeyboardHook() => _proc = HookCallback;

    public void Install()
    {
        _hook = SetWindowsHookExW(WH_KEYBOARD_LL, _proc, GetModuleHandleW(null), 0);
        if (_hook == IntPtr.Zero)
            throw new InvalidOperationException($"SetWindowsHookEx failed (error {Marshal.GetLastWin32Error()})");
    }

    private IntPtr HookCallback(int nCode, IntPtr wParam, IntPtr lParam)
    {
        if (nCode == HC_ACTION)
        {
            int msg = (int)wParam;
            if (msg == WM_KEYDOWN || msg == WM_SYSKEYDOWN)
            {
                var data = Marshal.PtrToStructure<KBDLLHOOKSTRUCT>(lParam);
                // Ignore our own injected retype events (self-event marker).
                if (data.dwExtraInfo != InjectedMarker)
                {
                    bool suppress = KeyDown?.Invoke(data.vkCode, data.scanCode) == true;
                    if (suppress)
                    {
                        _suppressedKeyUps.Add(data.vkCode);
                        return (IntPtr)1;
                    }

                    // If a held key starts repeating and a later key-down is not captured,
                    // its final key-up must reach the focused application as well.
                    _suppressedKeyUps.Remove(data.vkCode);
                }
            }
            else if (msg == WM_KEYUP || msg == WM_SYSKEYUP)
            {
                var data = Marshal.PtrToStructure<KBDLLHOOKSTRUCT>(lParam);
                if (data.dwExtraInfo != InjectedMarker)
                {
                    KeyUp?.Invoke(data.vkCode, data.scanCode);
                    if (_suppressedKeyUps.Remove(data.vkCode))
                        return (IntPtr)1;
                }
            }
        }
        return CallNextHookEx(_hook, nCode, wParam, lParam);
    }

    public void Dispose()
    {
        if (_hook != IntPtr.Zero)
        {
            UnhookWindowsHookEx(_hook);
            _hook = IntPtr.Zero;
        }
    }
}
