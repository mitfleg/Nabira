using System.Security.Cryptography;
using System.Text;
using Microsoft.Win32;

namespace Nabira.Win.Core;

internal static class DeviceIdentity
{
    public static string Identifier()
    {
        string? machineGuid = null;
        try
        {
            using var localMachine = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, RegistryView.Registry64);
            using var key = localMachine.OpenSubKey(@"SOFTWARE\Microsoft\Cryptography", writable: false);
            machineGuid = key?.GetValue("MachineGuid") as string;
        }
        catch { }
        if (string.IsNullOrWhiteSpace(machineGuid))
            throw new InvalidOperationException(L10n.T("account.device.error"));

        byte[] digest = SHA256.HashData(Encoding.UTF8.GetBytes(
            "nabira-device-v1:" + machineGuid.Trim().ToLowerInvariant()));
        return Convert.ToHexString(digest).ToLowerInvariant();
    }
}
