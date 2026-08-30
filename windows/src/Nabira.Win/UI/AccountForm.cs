using System.Drawing;
using System.Windows.Forms;
using Nabira.Win.Core;

namespace Nabira.Win.UI;

internal sealed class AccountForm : Form
{
    private readonly AccountAccessManager _manager;
    private readonly Label _status;
    private readonly Label _detail;
    private readonly ProgressStrip _trial;
    private readonly CardPanel _authCard;
    private readonly Panel _loginPanel;
    private readonly Panel _registerPanel;
    private readonly Button _loginTab;
    private readonly Button _registerTab;
    private readonly Button _signOut;

    public AccountForm(AccountAccessManager manager)
    {
        _manager = manager;
        Text = L10n.T("account.title");
        StartPosition = FormStartPosition.CenterScreen;
        ClientSize = new Size(940, 610);
        MinimumSize = new Size(860, 590);
        BackColor = NabiraTheme.Cloud;
        Font = NabiraTheme.Font(9.5f);
        AutoScaleMode = AutoScaleMode.Dpi;
        try { Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath); } catch { }

        var brandPanel = BuildBrandPanel();
        var content = new Panel { Name = "accountContent", BackColor = NabiraTheme.Cloud };
        Controls.Add(NabiraTheme.SplitShell(brandPanel, content, 330));

        content.Controls.Add(NabiraTheme.Label("Аккаунт Nabira", 44, 34, 440, 42, 22, FontStyle.Bold));
        content.Controls.Add(NabiraTheme.Label(
            "Управляйте пробным периодом, входом и подпиской.",
            46, 78, 460, 24, 9.5f, color: NabiraTheme.Muted));

        var accessCard = new CardPanel { Left = 44, Top = 120, Width = 500, Height = 118 };
        _status = NabiraTheme.Label("", 22, 18, 450, 28, 11.5f, FontStyle.Bold);
        _detail = NabiraTheme.Label("", 22, 49, 450, 38, 9, color: NabiraTheme.Muted);
        _trial = new ProgressStrip { Left = 22, Top = 93, Width = 456, Maximum = 7 };
        accessCard.Controls.AddRange(new Control[] { _status, _detail, _trial });
        content.Controls.Add(accessCard);

        _authCard = new CardPanel { Left = 44, Top = 258, Width = 500, Height = 286 };
        _loginTab = NabiraTheme.PrimaryButton(L10n.T("account.login"), 22, 18, 220, 38);
        _registerTab = NabiraTheme.SecondaryButton(L10n.T("account.register"), 256, 18, 220, 38);
        _loginTab.Click += (_, _) => ShowMode(register: false);
        _registerTab.Click += (_, _) => ShowMode(register: true);

        _loginPanel = BuildLoginPanel();
        _registerPanel = BuildRegisterPanel();
        _authCard.Controls.AddRange(new Control[] { _loginTab, _registerTab, _loginPanel, _registerPanel });
        content.Controls.Add(_authCard);
        ShowMode(register: false);

        _signOut = NabiraTheme.SecondaryButton(L10n.T("account.signout"), 44, 270, 180, 42);
        _signOut.Visible = false;
        _signOut.Click += async (_, _) => await RunAsync(_manager.SignOutAsync);
        content.Controls.Add(_signOut);

        var site = new LinkLabel
        {
            Text = L10n.T("account.open.site"),
            Left = 44,
            Top = 564,
            AutoSize = true,
            Font = NabiraTheme.Font(9.5f, FontStyle.Bold),
            LinkColor = NabiraTheme.Accent,
            ActiveLinkColor = NabiraTheme.Cyan,
        };
        site.LinkClicked += (_, _) => OpenSite();
        content.Controls.Add(site);

        _manager.Changed += UpdateSnapshot;
        UpdateSnapshot(_manager.Snapshot);
        FormClosed += (_, _) => _manager.Changed -= UpdateSnapshot;
    }

    private static GradientPanel BuildBrandPanel()
    {
        var panel = new GradientPanel { Name = "accountSidebar" };
        panel.Controls.Add(NabiraTheme.Label("A│Я", 44, 56, 100, 55, 24, FontStyle.Bold, Color.White));
        panel.Controls.Add(NabiraTheme.Label("Nabira", 44, 146, 240, 50, 25, FontStyle.Bold, Color.White));
        panel.Controls.Add(NabiraTheme.Label("Печатайте мысль,\nа не раскладку.", 44, 204, 240, 76,
            13, FontStyle.Bold, Color.FromArgb(232, 243, 255)));
        panel.Controls.Add(NabiraTheme.Label("7 дней полного доступа", 44, 474, 240, 28,
            10, FontStyle.Bold, Color.White));
        panel.Controls.Add(NabiraTheme.Label("Без привязки карты. Регистрация\nпонадобится после пробного периода.",
            44, 508, 250, 52, 9, color: Color.FromArgb(220, 240, 255)));
        return panel;
    }

    private Panel BuildLoginPanel()
    {
        var panel = new Panel { Left = 22, Top = 70, Width = 454, Height = 198, BackColor = Color.Transparent };
        var email = Field(panel, L10n.T("account.email"), 0, 0, false);
        var password = Field(panel, L10n.T("account.password"), 0, 68, true);
        var submit = NabiraTheme.PrimaryButton(L10n.T("account.login"), 0, 144, 454, 42);
        submit.Click += async (_, _) => await RunAsync(() => _manager.SignInAsync(email.Text, password.Text));
        panel.Controls.Add(submit);
        return panel;
    }

    private Panel BuildRegisterPanel()
    {
        var panel = new Panel { Left = 22, Top = 70, Width = 454, Height = 210, BackColor = Color.Transparent };
        var email = Field(panel, L10n.T("account.email"), 0, 0, false, 214);
        var password = Field(panel, L10n.T("account.password"), 230, 0, true, 224);
        var confirmation = Field(panel, L10n.T("account.password.confirm"), 0, 68, true, 454);
        var submit = NabiraTheme.PrimaryButton(L10n.T("account.register"), 0, 144, 454, 42);
        submit.Click += async (_, _) => await RunAsync(async () =>
        {
            string registered = await _manager.RegisterAsync(email.Text, password.Text, confirmation.Text);
            MessageBox.Show(L10n.T("account.verify.sent", registered), Text,
                MessageBoxButtons.OK, MessageBoxIcon.Information);
            ShowMode(register: false);
        });
        panel.Controls.Add(submit);
        return panel;
    }

    private static TextBox Field(Control parent, string label, int left, int top, bool password,
        int width = 454)
    {
        parent.Controls.Add(NabiraTheme.Label(label, left, top, width, 21, 8.5f, FontStyle.Bold,
            NabiraTheme.Muted));
        var box = NabiraTheme.TextBox(left, top + 23, width, password);
        parent.Controls.Add(box);
        return box;
    }

    private void ShowMode(bool register)
    {
        _loginPanel.Visible = !register;
        _registerPanel.Visible = register;
        StyleTab(_loginTab, !register);
        StyleTab(_registerTab, register);
    }

    private static void StyleTab(Button button, bool active)
    {
        button.BackColor = active ? NabiraTheme.Accent : NabiraTheme.AccentSoft;
        button.ForeColor = active ? Color.White : NabiraTheme.Accent;
    }

    private async Task RunAsync(Func<Task> operation)
    {
        Enabled = false;
        try { await operation(); }
        catch (Exception ex) { MessageBox.Show(ex.Message, Text, MessageBoxButtons.OK, MessageBoxIcon.Warning); }
        finally { Enabled = true; UpdateSnapshot(_manager.Snapshot); }
    }

    private void UpdateSnapshot(AccountSnapshot snapshot)
    {
        if (IsDisposed) return;
        if (InvokeRequired) { BeginInvoke(new Action(() => UpdateSnapshot(snapshot))); return; }

        _status.Text = snapshot.HasAccess
            ? snapshot.TrialActive ? L10n.T("account.trial.active", snapshot.TrialDaysRemaining) : L10n.T("account.subscription.active")
            : L10n.T("account.access.required");
        _status.ForeColor = snapshot.HasAccess ? NabiraTheme.Success : NabiraTheme.Danger;
        _detail.Text = snapshot.Error ?? (snapshot.Authenticated
            ? snapshot.Email! : L10n.T("account.trial.detail"));
        _trial.Value = Math.Clamp(snapshot.TrialDaysRemaining, 0, 7);
        _authCard.Visible = !snapshot.Authenticated;
        _signOut.Visible = snapshot.Authenticated;
    }

    private static void OpenSite()
    {
        try
        {
            System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(
                "https://nabira.site/account")
            { UseShellExecute = true });
        }
        catch { }
    }
}
