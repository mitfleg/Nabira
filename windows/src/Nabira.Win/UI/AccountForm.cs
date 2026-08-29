using System.Drawing;
using System.Windows.Forms;
using Nabira.Win.Core;

namespace Nabira.Win.UI;

internal sealed class AccountForm : Form
{
    private readonly AccountAccessManager _manager;
    private readonly Label _status;
    private readonly Label _detail;
    private readonly TabControl _tabs;
    private readonly Button _signOut;
    private readonly ProgressBar _trial;

    public AccountForm(AccountAccessManager manager)
    {
        _manager = manager;
        Text = L10n.T("account.title");
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = false;
        MinimizeBox = false;
        StartPosition = FormStartPosition.CenterScreen;
        ClientSize = new Size(500, 500);
        BackColor = Color.FromArgb(246, 248, 253);

        var brand = new Label
        {
            Text = "Nabira", Left = 24, Top = 20, AutoSize = true,
            Font = new Font(Font.FontFamily, 18, FontStyle.Bold), ForeColor = Color.FromArgb(17, 22, 42),
        };
        _status = new Label { Left = 24, Top = 64, Width = 450, Height = 32, Font = new Font(Font, FontStyle.Bold) };
        _detail = new Label { Left = 24, Top = 96, Width = 450, Height = 44, ForeColor = Color.DimGray };
        _trial = new ProgressBar { Left = 24, Top = 140, Width = 450, Height = 8, Maximum = 7 };

        _tabs = new TabControl { Left = 24, Top = 172, Width = 450, Height = 260 };
        _tabs.TabPages.Add(LoginPage());
        _tabs.TabPages.Add(RegisterPage());

        _signOut = new Button { Text = L10n.T("account.signout"), Left = 24, Top = 450, Width = 140, Visible = false };
        _signOut.Click += async (_, _) => await RunAsync(_manager.SignOutAsync);
        var site = new LinkLabel { Text = L10n.T("account.open.site"), Left = 282, Top = 456, AutoSize = true };
        site.LinkClicked += (_, _) => OpenSite();

        Controls.AddRange(new Control[] { brand, _status, _detail, _trial, _tabs, _signOut, site });
        _manager.Changed += UpdateSnapshot;
        UpdateSnapshot(_manager.Snapshot);
        FormClosed += (_, _) => _manager.Changed -= UpdateSnapshot;
    }

    private TabPage LoginPage()
    {
        var page = new TabPage(L10n.T("account.login"));
        var email = Field(page, L10n.T("account.email"), 18, 20, false);
        var password = Field(page, L10n.T("account.password"), 18, 88, true);
        var submit = new Button { Text = L10n.T("account.login"), Left = 18, Top = 158, Width = 180, Height = 34 };
        submit.Click += async (_, _) => await RunAsync(() => _manager.SignInAsync(email.Text, password.Text));
        page.Controls.Add(submit);
        return page;
    }

    private TabPage RegisterPage()
    {
        var page = new TabPage(L10n.T("account.register"));
        var email = Field(page, L10n.T("account.email"), 18, 10, false);
        var password = Field(page, L10n.T("account.password"), 18, 72, true);
        var confirmation = Field(page, L10n.T("account.password.confirm"), 18, 134, true);
        var submit = new Button { Text = L10n.T("account.register"), Left = 18, Top = 196, Width = 180, Height = 34 };
        submit.Click += async (_, _) => await RunAsync(async () =>
        {
            string registered = await _manager.RegisterAsync(email.Text, password.Text, confirmation.Text);
            MessageBox.Show(L10n.T("account.verify.sent", registered), Text,
                MessageBoxButtons.OK, MessageBoxIcon.Information);
            _tabs.SelectedIndex = 0;
        });
        page.Controls.Add(submit);
        return page;
    }

    private static TextBox Field(Control parent, string label, int left, int top, bool password)
    {
        parent.Controls.Add(new Label { Text = label, Left = left, Top = top, Width = 390 });
        var box = new TextBox { Left = left, Top = top + 22, Width = 390, UseSystemPasswordChar = password };
        parent.Controls.Add(box);
        return box;
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
        _detail.Text = snapshot.Error ?? (snapshot.Authenticated
            ? snapshot.Email! : L10n.T("account.trial.detail"));
        _trial.Value = Math.Clamp(snapshot.TrialDaysRemaining, 0, 7);
        _tabs.Visible = !snapshot.Authenticated;
        _signOut.Visible = snapshot.Authenticated;
    }

    private static void OpenSite()
    {
        try { System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(
            "https://nabira.linkurakt.chatgpt.site/account") { UseShellExecute = true }); }
        catch { }
    }
}
