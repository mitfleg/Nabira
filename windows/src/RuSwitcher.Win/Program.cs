using RuSwitcher.Win.Core;
using RuSwitcher.Win.Native;
using static RuSwitcher.Win.Native.Win32;

// RuSwitcher for Windows — stage 1 vertical slice.
// Proves the load-bearing primitives work: the low-level keyboard hook captures every
// key, and ToUnicodeEx maps it to a character in the active layout. Everything downstream
// (tray, buffer, retype via SendInput, layout switch) builds on exactly these two.
// It only LOGS for now — no injection, nothing intercepted.

string logDir = Path.Combine(
    Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "RuSwitcher");
Directory.CreateDirectory(logDir);
string logPath = Path.Combine(logDir, "debug.log");

void Log(string line) => File.AppendAllText(logPath, $"{DateTime.Now:HH:mm:ss.fff} {line}{Environment.NewLine}");

using var hook = new KeyboardHook();
hook.KeyDown += (vk, sc) =>
{
    char? ch = KeyMapper.Translate(vk, sc);
    Log($"keydown vk={vk} sc={sc} char='{(ch is { } c ? c.ToString() : "")}'");
};
hook.Install();
Log("RuSwitcher.Win started — keyboard hook installed");

// A message loop is required for low-level hook callbacks to be delivered.
while (GetMessageW(out MSG msg, IntPtr.Zero, 0, 0) > 0)
{
    TranslateMessage(ref msg);
    DispatchMessageW(ref msg);
}
