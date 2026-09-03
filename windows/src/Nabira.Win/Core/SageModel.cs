using System.Net.Http;
using System.Security.Cryptography;

namespace Nabira.Win.Core;

internal readonly record struct SageDownloadProgress(int CompletedFiles, int TotalFiles, string CurrentFile);

/// <summary>
/// Optional SAGE FredT5 95M model pack. Merely constructing this class performs no network
/// request: downloading starts only from <see cref="InstallAsync"/>, which is called by the
/// explicit «Скачать и подключить» button in Settings.
/// </summary>
internal static class SageModel
{
    internal const string Version = "sage-fredt5-95m-fp16-v1";
    internal const long DownloadSizeBytes = 262_896_057;
    internal const string BaseUrl = "https://nabira.site/downloads/models/sage-fredt5-95m-fp16/v1";

    private sealed record Asset(string Name, long Size, string Sha256);

    private static readonly Asset[] Assets =
    {
        new("encoder_model.onnx", 97_863_391, "0181db616a7336b163d5796b8c3975756234357233e1595722b34831483b747a"),
        new("decoder_model.onnx", 162_149_131, "142f189f6a4483b15bab972ce6ea80db9846350b68051dd0852b40341962f96e"),
        new("vocab.json", 1_612_610, "a7be5387908a52936262a09514bf0a9327ff17981097b6b2225c67120fd905a5"),
        new("merges.txt", 1_270_925, "bd05ba8658a199897510cd84cd98ec1424c812259db6e03319c33a5bfcac2b90"),
    };

    private static string Root => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "Nabira", "Models", "SageFredT5-95M");

    internal static string DirectoryPath => Path.Combine(Root, Version);
    internal static string EncoderPath => Path.Combine(DirectoryPath, "encoder_model.onnx");
    internal static string DecoderPath => Path.Combine(DirectoryPath, "decoder_model.onnx");
    internal static string VocabPath => Path.Combine(DirectoryPath, "vocab.json");
    internal static string MergesPath => Path.Combine(DirectoryPath, "merges.txt");

    internal static bool IsInstalled => Assets.All(asset =>
    {
        var file = new FileInfo(Path.Combine(DirectoryPath, asset.Name));
        return file.Exists && file.Length == asset.Size;
    });

    internal static async Task InstallAsync(
        IProgress<SageDownloadProgress>? progress = null,
        CancellationToken cancellationToken = default)
    {
        if (IsInstalled) return;

        Directory.CreateDirectory(Root);
        string staging = Path.Combine(Root, ".download-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(staging);

        try
        {
            using var http = new HttpClient { Timeout = TimeSpan.FromMinutes(20) };
            http.DefaultRequestHeaders.UserAgent.ParseAdd("Nabira/1.0");
            for (int index = 0; index < Assets.Length; index++)
            {
                Asset asset = Assets[index];
                progress?.Report(new SageDownloadProgress(index, Assets.Length, asset.Name));
                string destination = Path.Combine(staging, asset.Name);
                using HttpResponseMessage response = await http.GetAsync(
                    $"{BaseUrl}/{asset.Name}", HttpCompletionOption.ResponseHeadersRead, cancellationToken);
                response.EnsureSuccessStatusCode();
                await using (Stream source = await response.Content.ReadAsStreamAsync(cancellationToken))
                await using (var target = new FileStream(destination, FileMode.CreateNew, FileAccess.Write,
                    FileShare.None, 1024 * 1024, FileOptions.Asynchronous | FileOptions.SequentialScan))
                {
                    await source.CopyToAsync(target, 1024 * 1024, cancellationToken);
                    await target.FlushAsync(cancellationToken);
                }

                var info = new FileInfo(destination);
                if (info.Length != asset.Size)
                    throw new InvalidDataException($"Неверный размер файла модели: {asset.Name}");
                string actualHash = await Sha256Async(destination, cancellationToken);
                if (!actualHash.Equals(asset.Sha256, StringComparison.OrdinalIgnoreCase))
                    throw new InvalidDataException($"Не пройдена проверка файла модели: {asset.Name}");
            }

            progress?.Report(new SageDownloadProgress(Assets.Length, Assets.Length, "Готово"));
            if (Directory.Exists(DirectoryPath)) Directory.Delete(DirectoryPath, recursive: true);
            Directory.Move(staging, DirectoryPath);
        }
        catch
        {
            try { if (Directory.Exists(staging)) Directory.Delete(staging, recursive: true); } catch { }
            throw;
        }
    }

    internal static async Task<bool> VerifyAsync(CancellationToken cancellationToken = default)
    {
        if (!IsInstalled) return false;
        foreach (Asset asset in Assets)
        {
            string actualHash = await Sha256Async(Path.Combine(DirectoryPath, asset.Name), cancellationToken);
            if (!actualHash.Equals(asset.Sha256, StringComparison.OrdinalIgnoreCase)) return false;
        }
        return true;
    }

    internal static void Remove()
    {
        SageCorrectionService.Reset();
        if (Directory.Exists(DirectoryPath)) Directory.Delete(DirectoryPath, recursive: true);
    }

    private static async Task<string> Sha256Async(string path, CancellationToken cancellationToken)
    {
        await using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read,
            1024 * 1024, FileOptions.Asynchronous | FileOptions.SequentialScan);
        byte[] hash = await SHA256.HashDataAsync(stream, cancellationToken);
        return Convert.ToHexString(hash).ToLowerInvariant();
    }
}
