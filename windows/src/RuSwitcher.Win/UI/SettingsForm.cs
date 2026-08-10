using System.Drawing;
using System.Windows.Forms;
using RuSwitcher.Win.Core;

namespace RuSwitcher.Win.UI;

/// <summary>Settings window (WinForms) — the Windows counterpart of the macOS settings window.
/// Edits Settings.Current live (saved on each change). Trigger changes are surfaced via
/// <see cref="TriggerChanged"/> so the running detector is updated immediately.</summary>
internal sealed class SettingsForm : Form
{
    public event Action<TriggerKind>? TriggerChanged;
    /// <summary>Raised when the layout-switch hotkey changes (so the running detector updates).</summary>
    public event Action? SwitchChanged;

    public SettingsForm()
    {
        var s = Settings.Current;

        Text = "RuSwitcher — Settings";
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = false;
        MinimizeBox = false;
        StartPosition = FormStartPosition.CenterScreen;
        ClientSize = new Size(380, 300);

        var lblTrigger = new Label { Text = "Trigger:", Left = 16, Top = 20, AutoSize = true };
        var cmbTrigger = new ComboBox { Left = 120, Top = 16, Width = 240, DropDownStyle = ComboBoxStyle.DropDownList };
        cmbTrigger.Items.AddRange(new object[] { "Double-tap Ctrl", "Double-tap Shift", "Pause/Break key" });
        cmbTrigger.SelectedIndex = (int)s.Trigger;
        cmbTrigger.SelectedIndexChanged += (_, _) =>
        {
            var t = (TriggerKind)cmbTrigger.SelectedIndex;
            s.Trigger = t; s.Save();
            TriggerChanged?.Invoke(t);
        };

        var chkWhole = MakeCheck("Convert the whole line (not just the last word)", 56, s.ConvertWholeLine,
            v => { s.ConvertWholeLine = v; s.Save(); });
        var chkSmart = MakeCheck("Smart selection conversion (keep correct words)", 88, s.SmartConversion,
            v => { s.SmartConversion = v; s.Save(); });
        var chkSound = MakeCheck("Play a sound on layout switch", 120, s.SoundOnSwitch,
            v => { s.SoundOnSwitch = v; s.Save(); });
        var chkStart = MakeCheck("Launch at startup", 152, AutoStart.IsEnabled(),
            v => AutoStart.SetEnabled(v));

        var lblSwitch = new Label { Text = "Layout-switch hotkey:", Left = 16, Top = 192, AutoSize = true };
        var cmbSwitch = new ComboBox { Left = 160, Top = 188, Width = 200, DropDownStyle = ComboBoxStyle.DropDownList };
        cmbSwitch.Items.AddRange(new object[] { "Off", "Double-tap Ctrl", "Double-tap Shift", "Pause/Break key" });
        cmbSwitch.SelectedIndex = s.SwitchTriggerEnabled ? (int)s.SwitchTrigger + 1 : 0;
        cmbSwitch.SelectedIndexChanged += (_, _) =>
        {
            int i = cmbSwitch.SelectedIndex;
            s.SwitchTriggerEnabled = i > 0;
            if (i > 0) s.SwitchTrigger = (TriggerKind)(i - 1);
            s.Save();
            SwitchChanged?.Invoke();
        };

        var link = new LinkLabel { Text = "github.com/rashn/RuSwitcher", Left = 16, Top = 236, AutoSize = true };
        link.LinkClicked += (_, _) => OpenUrl("https://github.com/rashn/RuSwitcher");

        var btnClose = new Button { Text = "Close", Left = 270, Top = 260, Width = 90, DialogResult = DialogResult.OK };
        AcceptButton = btnClose;

        Controls.AddRange(new Control[] { lblTrigger, cmbTrigger, chkWhole, chkSmart, chkSound, chkStart, lblSwitch, cmbSwitch, link, btnClose });
    }

    private static CheckBox MakeCheck(string text, int top, bool value, Action<bool> onChange)
    {
        var cb = new CheckBox { Text = text, Left = 16, Top = top, Width = 350, Checked = value };
        cb.CheckedChanged += (_, _) => onChange(cb.Checked);
        return cb;
    }

    private static void OpenUrl(string url)
    {
        try { System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(url) { UseShellExecute = true }); }
        catch { /* ignore */ }
    }
}
