using System.Text.Json;
using System.Text.Json.Serialization;

namespace RuSwitcher.Win.Core;

/// <summary>Способ вызова конверсии. Двойной тап модификатора работает на всех клавиатурах
/// (в т.ч. ноутбуках) и не мешает набору — как Option-double-tap в macOS-версии.</summary>
public enum TriggerKind
{
    CtrlDoubleTap = 0,   // двойной тап Ctrl (по умолчанию)
    ShiftDoubleTap = 1,  // двойной тап Shift
    PauseBreak = 2,      // выделенная клавиша Pause/Break
}

/// <summary>Настройки Windows-версии: JSON в %LocalAppData%\RuSwitcher\settings.json.</summary>
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

    /// <summary>Process-wide settings instance (loaded once). Core classes read this directly,
    /// mirroring the macOS SettingsManager.shared singleton.</summary>
    public static Settings Current { get; } = Load();

    private static readonly JsonSerializerOptions Json = new()
    {
        WriteIndented = true,
        Converters = { new JsonStringEnumConverter() },
    };

    private static string Dir =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "RuSwitcher");
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
            File.WriteAllText(FilePath, JsonSerializer.Serialize(this, Json));
        }
        catch { /* не критично */ }
    }
}
