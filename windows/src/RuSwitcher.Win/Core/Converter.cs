using static RuSwitcher.Win.Native.Win32;

namespace RuSwitcher.Win.Core;

/// <summary>
/// Orchestrates a manual conversion of the last typed word: take the buffer, render it in
/// the opposite layout, delete + reinsert, then switch the layout — the Windows counterpart
/// of <c>AppDelegate.onAltTap</c>. MVP: converts the current word (before a space).
/// </summary>
internal static class Converter
{
    /// <summary>Convert the buffered word into the opposite layout. Returns true if it acted.</summary>
    public static bool ConvertLastWord(KeystrokeBuffer buffer)
    {
        if (buffer.IsEmpty) return false;

        IntPtr? opposite = LayoutSwitcher.Opposite();
        if (opposite is not { } targetHkl) return false;

        string converted = KeyMapper.ConvertWord(buffer.CurrentWord, targetHkl);
        if (converted.Length == 0) return false;

        TextInjector.Replace(backspaces: buffer.CurrentWord.Count, text: converted);
        LayoutSwitcher.SwitchTo(targetHkl);
        buffer.Reset();
        return true;
    }
}
