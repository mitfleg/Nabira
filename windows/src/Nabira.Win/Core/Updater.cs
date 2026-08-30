using System.Net.Http;
using System.Reflection;
using System.Windows.Forms;

namespace Nabira.Win.Core;

/// <summary>Checks, downloads, verifies, and installs signed Nabira releases.</summary>
internal static class Updater
{
    private const string StableFeedUrl = "https://nabira.site/downloads/windows-version.json";
    private const string BetaFeedUrl = "https://nabira.site/downloads/windows-version-beta.json";
    private const long MaximumDownloadBytes = 250L * 1024 * 1024;
    private static int _busy;

    public static Version Current =>
        Assembly.GetExecutingAssembly().GetName().Version ?? new Version(0, 0, 0);

    public static void StartAutomaticChecks(SynchronizationContext ui, Action requestExit)
    {
        _ = Task.Run(async () =>
        {
            await Task.Delay(5000);
            while (true)
            {
                if (ShouldAutoCheck()) await CheckAsync(silent: true, ui, requestExit);
                await Task.Delay(TimeSpan.FromHours(6));
            }
        });
    }

    public static void CheckNow(SynchronizationContext ui, Action requestExit) =>
        _ = CheckAsync(silent: false, ui, requestExit);

    private static bool ShouldAutoCheck()
    {
        var settings = Settings.Current;
        if (!settings.CheckUpdatesEnabled) return false;
        if (settings.LastUpdateCheckTicks == 0) return true;
        var last = new DateTime(settings.LastUpdateCheckTicks, DateTimeKind.Utc);
        return DateTime.UtcNow - last >= TimeSpan.FromHours(24);
    }

    private static async Task CheckAsync(
        bool silent, SynchronizationContext ui, Action requestExit)
    {
        if (Interlocked.Exchange(ref _busy, 1) == 1) return;
        try
        {
            NabiraUpdateInfo? stable;
            try
            {
                stable = await FetchAsync(StableFeedUrl, UpdateChannel.Stable)
                    .ConfigureAwait(false);
            }
            catch
            {
                if (!silent) Show(ui, L10n.T("upd.error"), MessageBoxIcon.Warning);
                return;
            }
            if (stable == null)
            {
                if (!silent) Show(ui, L10n.T("upd.integrity"), MessageBoxIcon.Error);
                return;
            }

            NabiraUpdateInfo feed = stable;
            if (Settings.Current.BetaChannelEnabled)
            {
                // Beta is opt-in and optional. A missing, unreachable or invalid beta feed must
                // never prevent the client from receiving stable security updates.
                try
                {
                    var beta = await FetchAsync(BetaFeedUrl, UpdateChannel.Beta)
                        .ConfigureAwait(false);
                    feed = SelectLatest(stable, beta);
                }
                catch { /* keep the verified stable feed */ }
            }

            ui.Post(_ =>
            {
                Settings.Current.LastUpdateCheckTicks = DateTime.UtcNow.Ticks;
                Settings.Current.Save();
            }, null);
            if (!Version.TryParse(feed.Version, out var latest)) return;

            if (latest > Current)
            {
                if (silent && Settings.Current.SkippedVersion == feed.Version) return;
                var completion = new TaskCompletionSource(
                    TaskCreationOptions.RunContinuationsAsynchronously);
                ui.Post(async _ =>
                {
                    try { await PromptAndInstallAsync(feed, requestExit); }
                    finally { completion.SetResult(); }
                }, null);
                await completion.Task.ConfigureAwait(false);
            }
            else if (!silent)
            {
                Show(ui, L10n.T("upd.uptodate", Current.ToString(3)), MessageBoxIcon.Information);
            }
        }
        finally { Interlocked.Exchange(ref _busy, 0); }
    }

    private static async Task PromptAndInstallAsync(NabiraUpdateInfo feed, Action requestExit)
    {
        string body = L10n.T("upd.available.body", feed.Version, Current.ToString(3));
        if (!string.IsNullOrWhiteSpace(feed.Notes)) body += "\n\n" + feed.Notes;
        body += "\n\n" + L10n.T("upd.install");
        string title = feed.Channel == UpdateChannel.Beta
            ? L10n.T("upd.beta.title")
            : L10n.T("upd.available.title");
        var answer = MessageBox.Show(body, title,
            MessageBoxButtons.YesNo, MessageBoxIcon.Information);
        if (answer != DialogResult.Yes)
        {
            Settings.Current.SkippedVersion = feed.Version;
            Settings.Current.Save();
            return;
        }

        try
        {
            string staged = await DownloadAsync(feed);
            UpdateInstaller.LaunchVerifiedUpdate(staged, feed.Sha256, requestExit);
        }
        catch (Exception error)
        {
            MessageBox.Show(L10n.T("upd.install.error") + "\n\n" + error.Message,
                L10n.T("app.name"), MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }

    private static async Task<string> DownloadAsync(NabiraUpdateInfo feed)
    {
        Directory.CreateDirectory(UpdateInstaller.StagingDirectory);
        string destination = Path.Combine(UpdateInstaller.StagingDirectory,
            $"Nabira-{feed.Version}-{Guid.NewGuid():N}.exe");
        try
        {
            using var http = Client(TimeSpan.FromMinutes(10));
            using var response = await http.GetAsync(
                feed.Url, HttpCompletionOption.ResponseHeadersRead).ConfigureAwait(false);
            response.EnsureSuccessStatusCode();
            if (response.Content.Headers.ContentLength is long length &&
                (length <= 0 || length > MaximumDownloadBytes))
                throw new InvalidDataException("Некорректный размер обновления.");

            await using var source = await response.Content.ReadAsStreamAsync().ConfigureAwait(false);
            await using var output = new FileStream(destination, FileMode.CreateNew, FileAccess.Write,
                FileShare.None, 128 * 1024, FileOptions.Asynchronous | FileOptions.SequentialScan);
            var buffer = new byte[128 * 1024];
            long total = 0;
            while (true)
            {
                int read = await source.ReadAsync(buffer).ConfigureAwait(false);
                if (read == 0) break;
                total += read;
                if (total > MaximumDownloadBytes)
                    throw new InvalidDataException("Обновление превышает допустимый размер.");
                await output.WriteAsync(buffer.AsMemory(0, read)).ConfigureAwait(false);
            }
            await output.FlushAsync().ConfigureAwait(false);
            output.Close();
            if (!UpdateInstaller.Hash(destination).Equals(feed.Sha256, StringComparison.Ordinal))
                throw new InvalidDataException("Контрольная сумма обновления не совпала.");
            return destination;
        }
        catch
        {
            try { if (File.Exists(destination)) File.Delete(destination); } catch { }
            throw;
        }
    }

    private static HttpClient Client(TimeSpan timeout)
    {
        var client = new HttpClient { Timeout = timeout };
        client.DefaultRequestHeaders.UserAgent.ParseAdd("Nabira-Win-Updater");
        return client;
    }

    private static async Task<NabiraUpdateInfo?> FetchAsync(
        string url, UpdateChannel expectedChannel)
    {
        using var http = Client(TimeSpan.FromSeconds(15));
        string json = await http.GetStringAsync(url).ConfigureAwait(false);
        return UpdateManifest.TryVerify(json, expectedChannel, out var info) ? info : null;
    }

    internal static NabiraUpdateInfo SelectLatest(
        NabiraUpdateInfo stable, NabiraUpdateInfo? beta)
    {
        if (beta == null || !Version.TryParse(beta.Version, out var betaVersion) ||
            !Version.TryParse(stable.Version, out var stableVersion))
            return stable;
        return betaVersion > stableVersion ? beta : stable;
    }

    private static void Show(SynchronizationContext ui, string text, MessageBoxIcon icon) =>
        ui.Post(_ => MessageBox.Show(text, L10n.T("app.name"), MessageBoxButtons.OK, icon), null);
}
