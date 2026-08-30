using System.Text.Json;
using System.Text.Json.Serialization;

namespace Nabira.Win.Core;

/// <summary>Способ вызова конверсии. Двойной тап модификатора работает на всех клавиатурах
/// (в т.ч. ноутбуках) и не мешает набору — как Option-double-tap в macOS-версии.</summary>
public enum TriggerKind
{
    CtrlDoubleTap = 0,   // двойной тап Ctrl (по умолчанию)
    ShiftDoubleTap = 1,  // двойной тап Shift
    PauseBreak = 2,      // выделенная клавиша Pause/Break
}

/// <summary>Настройки Windows-версии: JSON в %LocalAppData%\Nabira\settings.json.</summary>
public sealed class Settings
{
    public TriggerKind Trigger { get; set; } = TriggerKind.CtrlDoubleTap;

    /// <summary>issue #24: convert the whole line (Shift+Home selection) instead of the last word.</summary>
    public bool ConvertWholeLine { get; set; } = false;

    /// <summary>issue #22: smart per-word selection conversion (keep valid words). Default on;
    /// off = plain one-way flip.</summary>
    public bool SmartConversion { get; set; } = true;

    /// <summary>issue #7: play a sound when the layout switches. Default off.</summary>
    public bool SoundOnSwitch { get; set; } = false;

    /// <summary>issue #14: a separate hotkey that only switches the layout (no conversion).
    /// Off by default; when on, uses <see cref="SwitchTrigger"/> (kept distinct from Trigger).</summary>
    public bool SwitchTriggerEnabled { get; set; } = false;
    public TriggerKind SwitchTrigger { get; set; } = TriggerKind.ShiftDoubleTap;

    /// <summary>Separate change-case hotkey. Off by default.</summary>
    public bool CaseTriggerEnabled { get; set; } = false;
    public TriggerKind CaseTrigger { get; set; } = TriggerKind.PauseBreak;

    /// <summary>As-you-type auto conversion (beta) — flips a word into the opposite layout right after
    /// a space when the dictionary says it was typed in the wrong layout. Default OFF and conservative
    /// (precision over recall), mirroring the macOS auto-switch. Undoing an auto-conversion with the
    /// trigger teaches an exception (learn-from-undo).</summary>
    public bool AutoConvert { get; set; } = false;

    /// <summary>Conservative offline typo correction for Russian and English.</summary>
    public bool TypoCorrection { get; set; } = true;

    /// <summary>Fix exactly two accidental capitals at the start of a word.</summary>
    public bool FixDoubleCapitals { get; set; } = true;

    /// <summary>Fix common punctuation typed as Russian letters at the end of a word.</summary>
    public bool FixPunctuation { get; set; } = true;

    /// <summary>Offline OpenCorpora-derived unambiguous е→ё correction.</summary>
    public bool Yoficator { get; set; } = false;

    /// <summary>Keep explicit learn-from-undo behaviour enabled.</summary>
    public bool AdaptiveLearning { get; set; } = true;

    /// <summary>Words never auto-converted (typed form, lowercase). Grown by learn-from-undo.</summary>
    public List<string> NeverConvert { get; set; } = new();

    /// <summary>Words always auto-converted — matched on the CONVERTED (target) form, lowercase, so a
    /// correctly typed word doesn't ping-pong. Mirrors the macOS always-convert list.</summary>
    public List<string> AlwaysConvert { get; set; } = new();

    /// <summary>Processes where all automatic writing corrections are disabled.</summary>
    public List<string> ExcludedApps { get; set; } = new()
    {
        "windowsterminal", "cmd", "powershell", "pwsh", "devenv", "code",
        "idea64", "pycharm64", "webstorm64", "rider64", "androidstudio64",
        "1password", "bitwarden", "keepassxc"
    };

    /// <summary>Server-side trial anchor returned by Nabira API.</summary>
    public long TrialStartedAtUnixSeconds { get; set; } = 0;

    /// <summary>issue: per-app layout memory. Maps a process name (e.g. "devenv") to the last layout's
    /// full HKL (low 32 bits, so specific variants like UK vs US English are preserved); restored when
    /// the app regains focus. Off unless <see cref="PerAppLayout"/>.</summary>
    public bool PerAppLayout { get; set; } = false;
    public Dictionary<string, long> AppLayouts { get; set; } = new(StringComparer.OrdinalIgnoreCase);

    /// <summary>Auto-check for updates on launch (once per 24h). Manual check always works.</summary>
    public bool CheckUpdatesEnabled { get; set; } = true;
    /// <summary>Opt in to separately signed pre-release builds. Stable remains the fallback.</summary>
    public bool BetaChannelEnabled { get; set; } = false;
    /// <summary>Last auto-check time (UTC ticks) — throttles to once a day, like the macOS updater.</summary>
    public long LastUpdateCheckTicks { get; set; } = 0;
    /// <summary>A version the user chose to skip (not re-notified while it's the latest).</summary>
    public string SkippedVersion { get; set; } = "";

    /// <summary>Process-wide settings instance (loaded once). Core classes read this directly,
    /// mirroring the macOS SettingsManager.shared singleton.</summary>
    public static Settings Current { get; } = Load();

    private static readonly JsonSerializerOptions Json = new()
    {
        WriteIndented = true,
        Converters = { new JsonStringEnumConverter() },
    };

    private static string Dir =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Nabira");
    private static string FilePath => Path.Combine(Dir, "settings.json");

    public static Settings Load()
    {
        try
        {
            if (File.Exists(FilePath))
                return JsonSerializer.Deserialize<Settings>(File.ReadAllText(FilePath), Json) ?? new Settings();
        }
        catch { /* повреждён/недоступен — дефолты */ }
        return new Settings();
    }

    public void Save()
    {
        try
        {
            Directory.CreateDirectory(Dir);
            // Atomic write: serialize to a temp file, then rename over the target. File.Move with
            // overwrite is an atomic MoveFileEx(REPLACE_EXISTING) on the same volume — and avoids the
            // File.Replace backup-file/attribute/AV quirks that were silently failing every save.
            string json = JsonSerializer.Serialize(this, Json);
            string tmp = FilePath + ".tmp";
            File.WriteAllText(tmp, json);
            File.Move(tmp, FilePath, overwrite: true);
        }
        catch { /* не критично */ }
    }
}
