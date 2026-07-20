using static RuSwitcher.Win.Native.Win32;

namespace RuSwitcher.Win.Core;

/// <summary>
/// Scancode + layout -> character via ToUnicodeEx — the Windows analog of the macOS
/// <c>DynamicKeyMapping</c> (Carbon UCKeyTranslate). Layout-driven, no hardcoded tables.
/// </summary>
internal static class KeyMapper
{
    /// <summary>The character a key would produce right now, in the active layout.</summary>
    public static char? Translate(uint vkCode, uint scanCode)
    {
        IntPtr hkl = GetKeyboardLayout(GetWindowThreadProcessId(GetForegroundWindow(), out _));
        return TranslateIn(new TypedKey(vkCode, scanCode, Shift: false, Caps: false), hkl);
    }

    /// <summary>Reproduce one key's character in a specific layout, honoring Shift/Caps.</summary>
    public static char? TranslateIn(TypedKey key, IntPtr hkl)
    {
        var state = new byte[256];
        if (key.Shift) state[0x10] = 0x80;               // VK_SHIFT down
        if (key.Caps) state[0x14] = 0x01;                // VK_CAPITAL toggled

        var buf = new char[8];
        // wFlags bit 2 (0x4): do not change the keyboard state (avoids clobbering real dead-key
        // state). Dead-key edge cases are deferred, mirroring the macOS NoDeadKeys approach.
        int n = ToUnicodeEx(key.VkCode, key.ScanCode, state, buf, buf.Length, 0x4, hkl);
        return n >= 1 ? buf[0] : null;
    }

    /// <summary>Convert a buffered word into the string it would be in <paramref name="targetHkl"/>.
    /// The Windows analog of <c>DynamicKeyMapping.convertKeys</c>.</summary>
    public static string ConvertWord(IReadOnlyList<TypedKey> keys, IntPtr targetHkl)
    {
        var sb = new System.Text.StringBuilder(keys.Count);
        foreach (var k in keys)
        {
            char? c = TranslateIn(k, targetHkl);
            if (c is { } ch) sb.Append(ch);
        }
        return sb.ToString();
    }
}
