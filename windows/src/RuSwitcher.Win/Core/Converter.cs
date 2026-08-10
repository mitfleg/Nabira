using System.Windows.Forms;
using static RuSwitcher.Win.Native.Win32;

namespace RuSwitcher.Win.Core;

/// <summary>
/// Orchestrates a manual conversion of the last typed word: take the buffer, render it in the
/// opposite layout, delete + reinsert, then switch the layout — the Windows counterpart of the
/// macOS <c>AppDelegate.onAltTap</c>. A second trigger with no typing in between reverses it
/// (reconvert/undo, toggling back and forth) — the counterpart of <c>onAltReconvert</c>.
/// </summary>
internal static class Converter
{
    // Last conversion, for reconvert. "_a" is what's currently on screen; "_b" is the alternative.
    // Each side carries its layout so reconvert also restores the right keyboard layout.
    private static string _aText = "";
    private static string _bText = "";
    private static IntPtr _aHkl;
    private static IntPtr _bHkl;

    /// <summary>True if the last conversion can be reversed (nothing typed since).</summary>
    public static bool CanReconvert => _aText.Length > 0;

    /// <summary>Any real typing invalidates a pending reconvert (the word on screen changed).</summary>
    public static void ClearReconvert() { _aText = ""; _bText = ""; }

    /// <summary>Convert the buffered word into the opposite layout. Returns true if it acted.</summary>
    public static bool ConvertLastWord(KeystrokeBuffer buffer)
    {
        if (buffer.IsEmpty) return false;

        IntPtr sourceHkl = LayoutSwitcher.Current();
        if (LayoutSwitcher.Opposite() is not { } targetHkl) return false;

        string converted = KeyMapper.ConvertWord(buffer.CurrentWord, targetHkl);
        if (converted.Length == 0) return false;
        string original = KeyMapper.ConvertWord(buffer.CurrentWord, sourceHkl);  // as it was typed

        TextInjector.Replace(backspaces: buffer.CurrentWord.Count, text: converted);
        LayoutSwitcher.SwitchTo(targetHkl);

        _aText = converted; _aHkl = targetHkl;   // now on screen
        _bText = original;  _bHkl = sourceHkl;    // the alternative (undo target)
        buffer.Reset();
        return true;
    }

    /// <summary>Reverse the last conversion (and toggle for a repeated trigger).</summary>
    public static bool Reconvert()
    {
        if (_aText.Length == 0) return false;

        TextInjector.Replace(backspaces: _aText.Length, text: _bText);
        LayoutSwitcher.SwitchTo(_bHkl);

        (_aText, _bText) = (_bText, _aText);   // toggle: a third trigger redoes the conversion
        (_aHkl, _bHkl) = (_bHkl, _aHkl);
        return true;
    }

    /// <summary>Convert the current selection via a clipboard round-trip (the counterpart of the
    /// macOS <c>convertViaClipboard</c>): Ctrl+C → convert the text char-by-char in the opposite
    /// layout → Ctrl+V, restoring the user's clipboard afterwards. One-way flip by the current
    /// layout (smart per-word conversion is a later parity step). No selection / no-op → false.
    /// MUST run on the message loop (STA), never inside the hook callback.</summary>
    public static bool ConvertSelection()
    {
        IntPtr sourceHkl = LayoutSwitcher.Current();
        if (LayoutSwitcher.Opposite() is not { } targetHkl) return false;

        string? saved = SafeGetText();
        SafeClear();
        TextInjector.SendCtrl(VK_C);
        Thread.Sleep(60);                       // let the focused app place the selection on the clipboard
        string sel = SafeGetText() ?? "";
        if (sel.Length == 0) { RestoreClipboard(saved); return false; }   // nothing selected

        string converted = KeyMapper.ConvertText(sel, sourceHkl, targetHkl);
        if (converted == sel) { RestoreClipboard(saved); return false; }  // no-op

        SafeSetText(converted);
        TextInjector.SendCtrl(VK_V);
        Thread.Sleep(60);                       // let the paste happen before we restore the clipboard
        RestoreClipboard(saved);
        return true;
    }

    // Clipboard is shared + can be briefly locked by other apps — retry, never throw.
    private static string? SafeGetText()
    {
        try { return Clipboard.ContainsText() ? Clipboard.GetText() : null; } catch { return null; }
    }
    private static void SafeSetText(string s)
    {
        for (int i = 0; i < 6; i++) { try { Clipboard.SetText(s); return; } catch { Thread.Sleep(15); } }
    }
    private static void SafeClear()
    {
        for (int i = 0; i < 6; i++) { try { Clipboard.Clear(); return; } catch { Thread.Sleep(15); } }
    }
    private static void RestoreClipboard(string? saved)
    {
        if (string.IsNullOrEmpty(saved)) SafeClear(); else SafeSetText(saved);
    }
}
