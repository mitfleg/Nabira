using System.Runtime.InteropServices;
using static RuSwitcher.Win.Native.Win32;

namespace RuSwitcher.Win.Core;

/// <summary>
/// Deletes the typed word and reinserts the converted text via SendInput +
/// KEYEVENTF_UNICODE — the clipboard-free retype engine, the Windows counterpart of the
/// macOS <c>TextConverter</c> buffer engine. Our events carry <see cref="InjectedMarker"/>
/// so the hook ignores them.
/// </summary>
internal static class TextInjector
{
    public static void Replace(int backspaces, string text)
    {
        var inputs = new List<INPUT>(backspaces * 2 + text.Length * 2);

        for (int i = 0; i < backspaces; i++)
        {
            inputs.Add(Key(VK_BACK, '\0', dwFlags: 0));
            inputs.Add(Key(VK_BACK, '\0', dwFlags: KEYEVENTF_KEYUP));
        }
        foreach (char c in text)
        {
            inputs.Add(Key(0, c, dwFlags: KEYEVENTF_UNICODE));
            inputs.Add(Key(0, c, dwFlags: KEYEVENTF_UNICODE | KEYEVENTF_KEYUP));
        }

        var arr = inputs.ToArray();
        SendInput((uint)arr.Length, arr, Marshal.SizeOf<INPUT>());
    }

    /// <summary>Send Ctrl+<paramref name="vk"/> (e.g. Ctrl+C / Ctrl+V). Carries the injected
    /// marker so our own hook ignores it (won't be mistaken for a trigger).</summary>
    public static void SendCtrl(ushort vk)
    {
        var inputs = new[]
        {
            Key(VK_CONTROL, '\0', dwFlags: 0),
            Key(vk, '\0', dwFlags: 0),
            Key(vk, '\0', dwFlags: KEYEVENTF_KEYUP),
            Key(VK_CONTROL, '\0', dwFlags: KEYEVENTF_KEYUP),
        };
        SendInput((uint)inputs.Length, inputs, Marshal.SizeOf<INPUT>());
    }

    private static INPUT Key(ushort vk, char scanChar, uint dwFlags) => new()
    {
        type = INPUT_KEYBOARD,
        U = new InputUnion
        {
            ki = new KEYBDINPUT
            {
                wVk = vk,
                wScan = scanChar,
                dwFlags = dwFlags,
                time = 0,
                dwExtraInfo = InjectedMarker,
            }
        }
    };
}
