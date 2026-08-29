using System.Windows.Forms;
using static Nabira.Win.Native.Win32;

namespace Nabira.Win.Core;

internal static class PlainTextPaste
{
    /// <summary>Temporarily exposes only Unicode text while the user's real Ctrl+Shift+V reaches
    /// the focused app, then restores every clipboard format if nothing else changed it.</summary>
    public static void Prepare(SynchronizationContext ui)
    {
        try
        {
            IDataObject? original = Clipboard.GetDataObject();
            if (original == null || !original.GetDataPresent(DataFormats.UnicodeText)) return;
            string? text = original.GetData(DataFormats.UnicodeText) as string;
            if (text == null) return;

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

            Clipboard.SetText(text, TextDataFormat.UnicodeText);
            uint temporarySequence = GetClipboardSequenceNumber();
            _ = Task.Delay(350).ContinueWith(_ => ui.Post(__ =>
            {
                try
                {
                    if (GetClipboardSequenceNumber() == temporarySequence)
                        Clipboard.SetDataObject(snapshot, copy: true);
                }
                catch { }
            }, null), TaskScheduler.Default);
        }
        catch { }
    }
}
