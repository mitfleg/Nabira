using System.Drawing;
using System.Windows.Forms;
using Nabira.Win.Core;

namespace Nabira.Win.UI;

internal sealed class ExceptionsForm : Form
{
    private readonly TextBox _never;
    private readonly TextBox _always;
    private readonly TextBox _apps;

    public ExceptionsForm()
    {
        var s = Settings.Current;

        Text = L10n.T("exc.title");
        StartPosition = FormStartPosition.CenterParent;
        ClientSize = new Size(920, 520);
        MinimumSize = new Size(820, 480);
        BackColor = NabiraTheme.Cloud;
        Font = NabiraTheme.Font(9.5f);
        AutoScaleMode = AutoScaleMode.Dpi;
        try { Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath); } catch { }

        Controls.Add(NabiraTheme.Label("Исключения", 34, 26, 500, 40, 22, FontStyle.Bold));
        Controls.Add(NabiraTheme.Label(
            "По одному слову или имени приложения на строку. Регистр не учитывается.",
            36, 67, 690, 25, 9.5f, color: NabiraTheme.Muted));

        int cardTop = 112;
        int cardWidth = 270;
        var neverCard = ListCard("Не исправлять", "Слова, которые Nabira должна оставить как есть.",
            34, cardTop, cardWidth, s.NeverConvert, out _never);
        var alwaysCard = ListCard("Всегда исправлять", "Правильные варианты, которым вы доверяете.",
            324, cardTop, cardWidth, s.AlwaysConvert, out _always);
        var appsCard = ListCard("Приложения", "Имена процессов без .exe, например windowsterminal.",
            614, cardTop, cardWidth, s.ExcludedApps, out _apps);
        neverCard.Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Bottom;
        alwaysCard.Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Bottom;
        appsCard.Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right | AnchorStyles.Bottom;
        Controls.AddRange(new Control[] { neverCard, alwaysCard, appsCard });

        var cancel = NabiraTheme.SecondaryButton(L10n.T("exc.cancel"), 684, 460, 96, 40);
        cancel.Anchor = AnchorStyles.Right | AnchorStyles.Bottom;
        cancel.DialogResult = DialogResult.Cancel;
        var save = NabiraTheme.PrimaryButton(L10n.T("exc.save"), 792, 460, 96, 40);
        save.Anchor = AnchorStyles.Right | AnchorStyles.Bottom;
        save.DialogResult = DialogResult.OK;
        save.Click += (_, _) =>
        {
            s.NeverConvert = Parse(_never.Text);
            s.AlwaysConvert = Parse(_always.Text);
            s.ExcludedApps = Parse(_apps.Text);
            s.Save();
        };
        Controls.AddRange(new Control[] { cancel, save });
        AcceptButton = save;
        CancelButton = cancel;
    }

    private static CardPanel ListCard(string title, string detail, int left, int top, int width,
        IEnumerable<string> items, out TextBox box)
    {
        var card = new CardPanel { Left = left, Top = top, Width = width, Height = 326 };
        card.Controls.Add(NabiraTheme.Label(title, 18, 16, width - 36, 26, 11, FontStyle.Bold));
        card.Controls.Add(NabiraTheme.Label(detail, 18, 45, width - 36, 42, 8.5f, color: NabiraTheme.Muted));
        box = NabiraTheme.TextBox(18, 96, width - 36, multiline: true);
        box.Height = 208;
        box.Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right | AnchorStyles.Bottom;
        box.WordWrap = false;
        box.Text = string.Join(Environment.NewLine, items);
        card.Controls.Add(box);
        return card;
    }

    private static List<string> Parse(string text) =>
        text.Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries)
            .Select(word => word.Trim().ToLowerInvariant())
            .Where(word => word.Length > 0)
            .Distinct()
            .ToList();
}
