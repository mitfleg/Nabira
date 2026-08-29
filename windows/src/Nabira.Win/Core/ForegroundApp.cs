using System.Diagnostics;
using static Nabira.Win.Native.Win32;

namespace Nabira.Win.Core;

internal static class ForegroundApp
{
    private static readonly HashSet<string> Protected = new(StringComparer.OrdinalIgnoreCase)
    {
        "1password", "bitwarden", "keepassxc"
    };

    public static string? ProcessName()
    {
        try
        {
            IntPtr hwnd = GetForegroundWindow();
            if (hwnd == IntPtr.Zero) return null;
            GetWindowThreadProcessId(hwnd, out uint pid);
            if (pid == 0) return null;
            using var process = Process.GetProcessById((int)pid);
            return process.ProcessName.ToLowerInvariant();
        }
        catch { return null; }
    }

    public static bool IsAutomaticCorrectionDenied()
    {
        string? process = ProcessName();
        if (process == null) return true;
        if (Protected.Contains(process)) return true;
        return Settings.Current.ExcludedApps.Contains(process, StringComparer.OrdinalIgnoreCase);
    }
}
