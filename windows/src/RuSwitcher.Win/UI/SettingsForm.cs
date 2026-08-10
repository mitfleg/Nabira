using System.Drawing;
using System.Windows.Forms;
using RuSwitcher.Win.Core;

namespace RuSwitcher.Win.UI;

/// <summary>Settings window (WinForms) — the Windows counterpart of the macOS settings window.
/// Edits Settings.Current live (saved on each change). Trigger changes are surfaced via
/// <see cref="TriggerChanged"/>/<see cref="SwitchChanged"/> so the running detectors update at once.</summary>
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
        ClientSize = new Size(400, 360);

        int y = 16;

        var lblTrigger = new Label { Text = "Trigger:", Left = 16, Top = y + 4, AutoSize = true };
        var cmbTrigger = new ComboBox { Left = 150, Top = y, Width = 234, DropDownStyle = ComboBoxStyle.DropDownList };
        cmbTrigger.Items.AddRange(new object[] { "Double-tap Ctrl", "Double-tap Shift", "Pause/Break key" });
        cmbTrigger.SelectedIndex = (int)s.Trigger;
        cmbTrigger.SelectedIndexChanged += (_, _) =>
        {
            var t = (TriggerKind)cmbTrigger.SelectedIndex;
            s.Trigger = t; s.Save();
            TriggerChanged?.Invoke(t);
        };
        y += 34;

        var chkWhole = MakeCheck("Convert the whole line (not just the last word)", ref y, s.ConvertWholeLine,
            v => { s.ConvertWholeLine = v; s.Save(); });
        var chkSmart = MakeCheck("Smart selection conversion (keep correct words)", ref y, s.SmartConversion,
            v => { s.SmartConversion = v; s.Save(); });
        var chkAuto = MakeCheck("Auto-convert as you type (beta)", ref y, s.AutoConvert,
            v => { s.AutoConvert = v; s.Save(); });
        var chkSound = MakeCheck("Play a sound on layout switch", ref y, s.SoundOnSwitch,
            v => { s.SoundOnSwitch = v; s.Save(); });
        var chkStart = MakeCheck("Launch at startup", ref y, AutoStart.IsEnabled(),
            v => AutoStart.SetEnabled(v));
        var chkPerApp = MakeCheck("Remember the layout per application", ref y, s.PerAppLayout,
            v => { s.PerAppLayout = v; s.Save(); });

        y += 6;
        var lblSwitch = new Label { Text = "Layout-switch hotkey:", Left = 16, Top = y + 4, AutoSize = true };
        var cmbSwitch = new ComboBox { Left = 180, Top = y, Width = 204, DropDownStyle = ComboBoxStyle.DropDownList };
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
        y += 40;

        var btnExceptions = new Button { Text = "Exceptions…", Left = 16, Top = y, Width = 110 };
        btnExceptions.Click += (_, _) => { using var ex = new ExceptionsForm(); ex.ShowDialog(this); };

        var link = new LinkLabel { Text = "github.com/rashn/RuSwitcher", Left = 140, Top = y + 4, AutoSize = true };
        link.LinkClicked += (_, _) => OpenUrl("https://github.com/rashn/RuSwitcher");
        y += 40;

        var btnClose = new Button { Text = "Close", Left = 294, Top = y, Width = 90, DialogResult = DialogResult.OK };
        AcceptButton = btnClose;
        ClientSize = new Size(400, y + 40);

        Controls.AddRange(new Control[]
        {
            lblTrigger, cmbTrigger, chkWhole, chkSmart, chkAuto, chkSound, chkStart, chkPerApp,
            lblSwitch, cmbSwitch, btnExceptions, link, btnClose,
        });
    }

    private CheckBox MakeCheck(string text, ref int top, bool value, Action<bool> onChange)
    {
        var cb = new CheckBox { Text = text, Left = 16, Top = top, Width = 368, Checked = value };
        cb.CheckedChanged += (_, _) => onChange(cb.Checked);
        top += 26;
        return cb;
    }

    private static void OpenUrl(string url)
    {
        try { System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(url) { UseShellExecute = true }); }
        catch { /* ignore */ }
    }
}
