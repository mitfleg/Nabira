using static RuSwitcher.Win.Native.Win32;

namespace RuSwitcher.Win.Core;

/// <summary>
/// Scancode + active layout -> character, via ToUnicodeEx — the Windows analog of the
/// macOS <c>DynamicKeyMapping</c> (Carbon UCKeyTranslate). Layout-driven, no hardcoded tables.
/// </summary>
internal static class KeyMapper
{
    /// <summary>The character the key would produce in the current layout, or null.</summary>
    public static char? Translate(uint vkCode, uint scanCode)
    {
        var state = new byte[256];
        GetKeyboardState(state);

        var buf = new char[8];
        IntPtr hkl = GetKeyboardLayout(0);
        int n = ToUnicodeEx(vkCode, scanCode, state, buf, buf.Length, 0, hkl);
        return n >= 1 ? buf[0] : null;
    }
}
