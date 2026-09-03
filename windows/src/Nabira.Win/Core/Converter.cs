using System.Windows.Forms;
using static Nabira.Win.Native.Win32;

namespace Nabira.Win.Core;

/// <summary>
/// Orchestrates a manual conversion of the last typed word: take the buffer, render it in the
/// opposite layout, delete + reinsert, then switch the layout — the Windows counterpart of the
/// macOS <c>AppDelegate.onAltTap</c>. A second trigger with no typing in between reverses it
/// (reconvert/undo, toggling back and forth) — the counterpart of <c>onAltReconvert</c>.
/// </summary>
internal static class Converter
{
    internal sealed record SageTextEdit(
        string Original,
        IntPtr ForegroundWindow,
        IntPtr SourceLayout,
        IntPtr TargetLayout,
        bool ExplicitSelection);
    // Last conversion, for reconvert. "_a" is what's currently on screen; "_b" is the alternative.
    // Each side carries its layout so reconvert also restores the right keyboard layout.
    private static string _aText = "";
    private static string _bText = "";
    private static IntPtr _aHkl;
    private static IntPtr _bHkl;
    private static bool _lastWasAuto;   // last conversion came from as-you-type auto (learn-from-undo)
    private static string? _caseWord;
    private static string _caseOnScreen = "";
    private static int _caseIndex;

    /// <summary>True if the last conversion can be reversed (nothing typed since).</summary>
    public static bool CanReconvert => _aText.Length > 0;

    /// <summary>Any real typing invalidates a pending reconvert (the word on screen changed).</summary>
    public static void ClearReconvert()
    {
        _aText = ""; _bText = ""; _lastWasAuto = false;
        _caseWord = null; _caseOnScreen = ""; _caseIndex = 0;
    }

    /// <summary>Record an auto-conversion so the trigger can reverse it — and so reversing it teaches
    /// an exception (learn-from-undo). <paramref name="onScreen"/> is what's now shown; the
    /// <paramref name="alternative"/> is the original typed word restored on undo.</summary>
    public static void NoteAutoConversion(string onScreen, string alternative, IntPtr onScreenHkl, IntPtr altHkl)
    {
        _aText = onScreen; _aHkl = onScreenHkl;
        _bText = alternative; _bHkl = altHkl;
        _lastWasAuto = true;
    }

    // Trailing keys whose char in the CURRENT layout is sentence punctuation are kept literally,
    // not converted — otherwise «ghbdtn,» would become «приветб» (the comma key is «б» in ЙЦУКЕН).
    // issue #15. The ambiguous ю/б/ж tails (e.g. «зуб» = "pe,") are left to the user, as on macOS.
    private static readonly HashSet<char> TrailingPunct = new() { ',', '.', '!', '?', ';', ':', ')' };

    /// <summary>Convert the buffered word into the opposite layout. Returns true if it acted.</summary>
    public static bool ConvertLastWord(KeystrokeBuffer buffer)
    {
        if (buffer.IsEmpty) return false;

        IntPtr sourceHkl = LayoutSwitcher.Current();
        if (LayoutSwitcher.Opposite() is not { } targetHkl) return false;

        // Split off trailing real punctuation (kept as typed).
        var keys = buffer.CurrentWord;
        int coreCount = keys.Count;
        var suffix = new System.Text.StringBuilder();
        while (coreCount > 0 &&
               KeyMapper.TranslateIn(keys[coreCount - 1], sourceHkl) is { } pc && TrailingPunct.Contains(pc))
        {
            suffix.Insert(0, pc);
            coreCount--;
        }
        if (coreCount == 0) return false;   // nothing but punctuation

        var core = new List<TypedKey>(coreCount);
        for (int i = 0; i < coreCount; i++) core.Add(keys[i]);
        string suf = suffix.ToString();

        string convertedCore = KeyMapper.ConvertWord(core, targetHkl);
        if (convertedCore.Length == 0) return false;
        string originalCore = KeyMapper.ConvertWord(core, sourceHkl);  // as it was typed

        string converted = convertedCore + suf;
        string original = originalCore + suf;

        TextInjector.Replace(backspaces: coreCount + suf.Length, text: converted);
        LayoutSwitcher.SwitchTo(targetHkl);

        _aText = converted; _aHkl = targetHkl;   // now on screen
        _bText = original;  _bHkl = sourceHkl;    // the alternative (undo target)
        _lastWasAuto = false;                     // a manual convert isn't subject to learn-from-undo
        buffer.Reset();
        return true;
    }

    /// <summary>Reverse the last conversion (and toggle for a repeated trigger).</summary>
    public static bool Reconvert()
    {
        if (_aText.Length == 0) return false;

        // Learn-from-undo: reversing an auto-conversion means the user rejected it — remember never to
        // auto-convert that typed word again (mirrors the macOS learn-from-undo).
        if (_lastWasAuto && Settings.Current.AdaptiveLearning)
        {
            string word = LetterCoreLower(_bText);   // _bText is the original typed word being restored
            var never = Settings.Current.NeverConvert;
            if (word.Length >= 2 && !never.Contains(word))
            {
                never.Add(word);
                Settings.Current.Save();
            }
            _lastWasAuto = false;   // only teach once
        }

        TextInjector.Replace(backspaces: _aText.Length, text: _bText);
        LayoutSwitcher.SwitchTo(_bHkl);

        (_aText, _bText) = (_bText, _aText);   // toggle: a third trigger redoes the conversion
        (_aHkl, _bHkl) = (_bHkl, _aHkl);
        return true;
    }

    public static bool CycleLastWord(KeystrokeBuffer buffer)
    {
        if (buffer.IsEmpty) return false;
        string original = KeyMapper.ConvertWord(buffer.CurrentWord, LayoutSwitcher.Current());
        return CycleCaseBuffer(original, buffer.CurrentWord.Count);
    }

    public static bool CycleCaseSelection()
    {
        _caseWord = null;
        IDataObject? saved = SnapshotClipboard();
        SafeClear();
        TextInjector.SendCtrl(VK_C);
        Thread.Sleep(60);
        string selected = SafeGetText() ?? "";
        if (selected.Length == 0 || !selected.Any(char.IsLetter)) { RestoreClipboard(saved); return false; }
        string changed = NextCase(selected);
        if (changed == selected) { RestoreClipboard(saved); return false; }
        SafeSetText(changed);
        TextInjector.SendCtrl(VK_V);
        Thread.Sleep(60);
        RestoreClipboard(saved);
        return true;
    }

    public static bool CycleCaseLine()
    {
        TextInjector.SendShift(VK_HOME);
        Thread.Sleep(40);
        bool ok = CycleCaseSelection();
        if (!ok) TextInjector.SendKey(VK_END);
        return ok;
    }

    private static bool CycleCaseBuffer(string original, int originalKeyCount)
    {
        if (string.IsNullOrEmpty(original) || !original.Any(char.IsLetter)) return false;
        if (!string.Equals(_caseWord, original, StringComparison.Ordinal))
        {
            _caseWord = original;
            _caseOnScreen = original;
            _caseIndex = CaseVariant(original, 0) == original ? 1 : 0;
        }
        else _caseIndex = (_caseIndex + 1) % 3;

        string changed = CaseVariant(original, _caseIndex);
        int attempts = 0;
        while (changed == _caseOnScreen && attempts++ < 3)
        {
            _caseIndex = (_caseIndex + 1) % 3;
            changed = CaseVariant(original, _caseIndex);
        }
        if (changed == _caseOnScreen) return false;
        int backspaces = _caseOnScreen == original ? originalKeyCount : _caseOnScreen.Length;
        TextInjector.Replace(backspaces, changed);
        _caseOnScreen = changed;
        return true;
    }

    internal static string NextCase(string value)
    {
        var letters = value.Where(char.IsLetter).ToArray();
        if (letters.Length == 0) return value;
        if (letters.All(char.IsLower)) return value.ToUpperInvariant();
        if (letters.All(char.IsUpper))
        {
            string title = System.Globalization.CultureInfo.CurrentCulture.TextInfo.ToTitleCase(value.ToLower());
            return title == value ? value.ToLowerInvariant() : title;
        }
        return value.ToLowerInvariant();
    }

    private static string CaseVariant(string value, int index) => (index % 3) switch
    {
        0 => value.ToUpperInvariant(),
        1 => value.ToLowerInvariant(),
        _ => System.Globalization.CultureInfo.CurrentCulture.TextInfo.ToTitleCase(value.ToLower()),
    };

    /// <summary>Convert the current selection via a clipboard round-trip (the counterpart of the
    /// macOS <c>convertViaClipboard</c>): Ctrl+C → convert the text char-by-char in the opposite
    /// layout → Ctrl+V, restoring the user's clipboard afterwards. One-way flip by the current
    /// layout (smart per-word conversion is a later parity step). No selection / no-op → false.
    /// MUST run on the message loop (STA), never inside the hook callback.</summary>
    public static bool ConvertSelection(bool smart, bool quickProbe = false)
    {
        IntPtr sourceHkl = LayoutSwitcher.Current();
        if (LayoutSwitcher.Opposite() is not { } targetHkl) return false;

        IDataObject? saved = SnapshotClipboard();
        string sel = "";
        int attempts = quickProbe ? 1 : 3;
        for (int attempt = 0; attempt < attempts; attempt++)
        {
            SafeClear();
            TextInjector.SendCtrl(VK_C);
            Thread.Sleep(attempt == 0 ? 70 : 120); // Electron/WebView can publish the copy later
            sel = SafeGetText() ?? "";
            if (sel.Length > 0) break;
            if (attempt + 1 < attempts) Thread.Sleep(40);
        }
        if (sel.Length == 0) { RestoreClipboard(saved); return false; }   // nothing selected

        string converted = smart
            ? SmartConvert.Selection(sel, sourceHkl, targetHkl)
            : KeyMapper.ConvertText(sel, sourceHkl, targetHkl);
        if (converted == sel) { RestoreClipboard(saved); return false; }  // no-op

        SafeSetText(converted);
        TextInjector.SendCtrl(VK_V);
        Thread.Sleep(60);                       // let the paste happen before we restore the clipboard
        RestoreClipboard(saved);

        LayoutSwitcher.SwitchTo(targetHkl);
        _aText = converted; _aHkl = targetHkl;
        _bText = sel;       _bHkl = sourceHkl;
        _lastWasAuto = false;
        return true;
    }

    /// <summary>issue #24: convert the whole current line — select it with Shift+Home, then run
    /// the selection conversion. Works in normal apps and terminals that support Shift+Home
    /// selection. On a no-op, collapse the selection (End) so the line isn't left highlighted.</summary>
    public static bool ConvertLine(bool smart)
    {
        TextInjector.SendShift(VK_HOME);   // select from cursor to line start
        Thread.Sleep(40);
        bool ok = ConvertSelection(smart);
        if (!ok) TextInjector.SendKey(VK_END);   // drop the selection (go to line end)
        return ok;
    }

    /// <summary>
    /// Captures an explicit selection, or selects and captures the complete current line.
    /// The user's clipboard is restored immediately. The selection is intentionally left active
    /// so the asynchronously computed SAGE result can replace exactly this text later.
    /// </summary>
    public static SageTextEdit? CaptureSelectionOrCurrentLine()
    {
        IntPtr window = GetForegroundWindow();
        if (window == IntPtr.Zero) return null;
        IntPtr sourceHkl = LayoutSwitcher.Current();
        if (LayoutSwitcher.Opposite() is not { } targetHkl) return null;

        IDataObject? saved = SnapshotClipboard();
        bool selectionKnown = SelectionProbe.TryHasExplicitSelection(out bool explicitSelection);
        string selected = explicitSelection || !selectionKnown ? CopySelection(attempts: 2) : "";
        if (!explicitSelection && (selectionKnown || selected.Length == 0))
        {
            TextInjector.SendKey(VK_HOME);
            Thread.Sleep(25);
            TextInjector.SendShift(VK_END);
            Thread.Sleep(45);
            selected = CopySelection(attempts: 3);
        }
        else if (!selectionKnown)
        {
            // Fallback for applications without UI Automation: a successful copy is treated as an
            // explicit selection, matching the old behavior and preserving terminal compatibility.
            explicitSelection = selected.Length > 0;
        }
        RestoreClipboard(saved);
        if (selected.Length == 0) return null;
        return new SageTextEdit(selected, window, sourceHkl, targetHkl, explicitSelection);
    }

    /// <summary>Replaces the still-selected captured text. If focus or selection changed while the
    /// model was running, nothing is modified.</summary>
    public static bool ApplySageCorrection(SageTextEdit edit, string replacement)
    {
        if (GetForegroundWindow() != edit.ForegroundWindow) return false;
        IDataObject? saved = SnapshotClipboard();
        string currentSelection = CopySelection(attempts: 2);
        if (!string.Equals(currentSelection, edit.Original, StringComparison.Ordinal))
        {
            RestoreClipboard(saved);
            return false;
        }
        if (string.Equals(replacement, edit.Original, StringComparison.Ordinal))
        {
            RestoreClipboard(saved);
            if (!edit.ExplicitSelection) TextInjector.SendKey(VK_END);
            return true;
        }

        SafeSetText(replacement);
        TextInjector.SendCtrl(VK_V);
        Thread.Sleep(80);
        RestoreClipboard(saved);
        ClearReconvert();
        return true;
    }

    private static string CopySelection(int attempts)
    {
        for (int attempt = 0; attempt < attempts; attempt++)
        {
            SafeClear();
            TextInjector.SendCtrl(VK_C);
            Thread.Sleep(attempt == 0 ? 70 : 120);
            string value = SafeGetText() ?? "";
            if (value.Length > 0) return value;
        }
        return "";
    }

    // Trim non-letters off both ends and lowercase — the key used for the never-convert exception list.
    private static string LetterCoreLower(string s)
    {
        int a = 0, b = s.Length;
        while (a < b && !char.IsLetter(s[a])) a++;
        while (b > a && !char.IsLetter(s[b - 1])) b--;
        return s.Substring(a, b - a).ToLowerInvariant();
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
    /// <summary>Snapshot every clipboard format. Selection probing now runs before the word buffer,
    /// so preserving only text would destroy a copied image/file even when there is no selection.</summary>
    private static IDataObject? SnapshotClipboard()
    {
        for (int attempt = 0; attempt < 6; attempt++)
        {
            try
            {
                IDataObject? original = Clipboard.GetDataObject();
                if (original == null) return null;
                var snapshot = new DataObject();
                foreach (string format in original.GetFormats(autoConvert: false))
                {
                    try
                    {
                        object? value = original.GetData(format, autoConvert: false);
                        if (value != null) snapshot.SetData(format, value);
                    }
                    catch { }
                }
                return snapshot;
            }
            catch { Thread.Sleep(15); }
        }
        return null;
    }

    private static void RestoreClipboard(IDataObject? saved)
    {
        for (int attempt = 0; attempt < 6; attempt++)
        {
            try
            {
                if (saved == null) Clipboard.Clear();
                else Clipboard.SetDataObject(saved, copy: true);
                return;
            }
            catch { Thread.Sleep(15); }
        }
    }
}
