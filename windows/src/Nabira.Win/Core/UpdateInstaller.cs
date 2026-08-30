using System.Diagnostics;
using System.Security.Cryptography;
using System.Windows.Forms;

namespace Nabira.Win.Core;

/// <summary>Stages and atomically applies a verified single-file Windows update.</summary>
internal static class UpdateInstaller
{
    private const string ApplyArgument = "--apply-update";

    internal static string StagingDirectory => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "Nabira", "updates");

    internal static bool TryRunApplyMode(string[] args)
    {
        if (args.Length == 0 || args[0] != ApplyArgument) return false;
        try
        {
            if (args.Length != 4 || !int.TryParse(args[2], out int oldPid))
                throw new InvalidOperationException("Некорректные параметры обновления.");
            Apply(args[1], oldPid, args[3]);
        }
        catch (Exception error)
        {
            MessageBox.Show(
                "Не удалось установить обновление Nabira. Старая версия сохранена.\n\n" + error.Message,
                "Nabira — Ошибка обновления", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
        return true;
    }

    internal static void LaunchVerifiedUpdate(
        string stagedExecutable, string expectedSha256, Action requestExit)
    {
        string target = Environment.ProcessPath
            ?? throw new InvalidOperationException("Не удалось определить путь Nabira.exe.");
        var start = new ProcessStartInfo(stagedExecutable) { UseShellExecute = false };
        start.ArgumentList.Add(ApplyArgument);
        start.ArgumentList.Add(target);
        start.ArgumentList.Add(Environment.ProcessId.ToString());
        start.ArgumentList.Add(expectedSha256);
        _ = Process.Start(start)
            ?? throw new InvalidOperationException("Не удалось запустить установщик обновления.");
        requestExit();
    }

    internal static void CleanupStaleDownloads()
    {
        try
        {
            if (!Directory.Exists(StagingDirectory)) return;
            foreach (string path in Directory.EnumerateFiles(StagingDirectory, "Nabira-*.exe"))
            {
                try
                {
                    if (File.GetLastWriteTimeUtc(path) < DateTime.UtcNow.AddDays(-1)) File.Delete(path);
                }
                catch { }
            }
        }
        catch { }
    }

    private static void Apply(string targetArgument, int oldPid, string expectedSha256)
    {
        string target = Path.GetFullPath(targetArgument);
        string staged = Environment.ProcessPath
            ?? throw new InvalidOperationException("Не удалось определить файл обновления.");
        string targetName = Path.GetFileName(target);
        if (!targetName.EndsWith(".exe", StringComparison.OrdinalIgnoreCase) ||
            !targetName.StartsWith("Nabira", StringComparison.OrdinalIgnoreCase) ||
            !File.Exists(target) || !IsSha256(expectedSha256) ||
            !Hash(staged).Equals(expectedSha256, StringComparison.Ordinal))
            throw new InvalidOperationException("Проверка файла обновления не пройдена.");

        try
        {
            using var oldProcess = Process.GetProcessById(oldPid);
            if (!oldProcess.WaitForExit(60_000))
                throw new TimeoutException("Старая версия Nabira не завершилась.");
        }
        catch (ArgumentException)
        {
            // The old process already exited between helper launch and lookup.
        }

        string candidate = target + ".update-" + Guid.NewGuid().ToString("N");
        string backup = target + ".previous";
        File.Copy(staged, candidate, overwrite: false);
        if (!Hash(candidate).Equals(expectedSha256, StringComparison.Ordinal))
        {
            File.Delete(candidate);
            throw new InvalidOperationException("Файл изменился при подготовке установки.");
        }

        try
        {
            if (File.Exists(backup)) File.Delete(backup);
            ReplaceWithRetry(candidate, target, backup);
            var launched = Process.Start(new ProcessStartInfo(target) { UseShellExecute = true })
                ?? throw new InvalidOperationException("Новая версия не запустилась.");
            if (launched.WaitForExit(5_000))
                throw new InvalidOperationException("Новая версия завершилась сразу после запуска.");
            // The update is already successful. An antivirus can briefly keep the backup open;
            // cleanup failure must not roll a healthy version back underneath the running process.
            try { File.Delete(backup); } catch { }
        }
        catch
        {
            TryRestore(target, backup);
            throw;
        }
        finally
        {
            try { if (File.Exists(candidate)) File.Delete(candidate); } catch { }
        }
    }

    private static void ReplaceWithRetry(string candidate, string target, string backup)
    {
        Exception? last = null;
        for (int attempt = 0; attempt < 20; attempt++)
        {
            try
            {
                File.Replace(candidate, target, backup, ignoreMetadataErrors: true);
                return;
            }
            catch (IOException error)
            {
                last = error;
                Thread.Sleep(250);
            }
        }
        throw new IOException("Windows не разрешил заменить Nabira.exe.", last);
    }

    private static void TryRestore(string target, string backup)
    {
        try
        {
            if (!File.Exists(backup)) return;
            if (File.Exists(target)) File.Delete(target);
            File.Move(backup, target);
            _ = Process.Start(new ProcessStartInfo(target) { UseShellExecute = true });
        }
        catch { }
    }

    internal static string Hash(string path)
    {
        using var stream = File.OpenRead(path);
        return Convert.ToHexString(SHA256.HashData(stream)).ToLowerInvariant();
    }

    private static bool IsSha256(string value) =>
        value.Length == 64 && value.All(character => character is >= '0' and <= '9' or >= 'a' and <= 'f');
}
