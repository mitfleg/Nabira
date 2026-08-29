using System.Drawing;
using System.Windows.Forms;
using Nabira.Win.Core;

namespace Nabira.Win.UI;

/// <summary>Modern Russian-first settings surface. Settings are persisted immediately,
/// so closing the window never loses a change.</summary>
internal sealed class SettingsForm : Form
{
    public event Action<TriggerKind>? TriggerChanged;
    public event Action? SwitchChanged;
    public event Action? CaseChanged;

    private readonly Panel _content;

    public SettingsForm()
    {
        var s = Settings.Current;

        Text = L10n.T("settings.title");
        StartPosition = FormStartPosition.CenterScreen;
        ClientSize = new Size(980, 700);
        MinimumSize = new Size(900, 640);
        BackColor = NabiraTheme.Cloud;
        Font = NabiraTheme.Font(9.5f);
        AutoScaleMode = AutoScaleMode.Dpi;
        DoubleBuffered = true;
        try { Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath); } catch { }

        var sidebar = BuildSidebar();
        _content = new Panel
        {
            Dock = DockStyle.Fill,
            BackColor = NabiraTheme.Cloud,
            AutoScroll = true,
            Padding = new Padding(38, 28, 38, 28),
        };
        Controls.Add(_content);
        Controls.Add(sidebar);
        sidebar.BringToFront();

        _content.Controls.Add(NabiraTheme.Label("Настройки", 38, 25, 560, 45, 24, FontStyle.Bold));
        _content.Controls.Add(NabiraTheme.Label(
            "Настройте Nabira под свой способ печати. Изменения сохраняются сразу.",
            40, 73, 640, 26, 10, color: NabiraTheme.Muted));

        var demo = new CardPanel
        {
            Left = 38,
            Top = 112,
            Width = 660,
            Height = 74,
            Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right,
            BackColor = NabiraTheme.AccentSoft,
        };
        demo.Controls.Add(NabiraTheme.Label("Nabira замечает раскладку сама", 20, 13, 330, 23,
            10, FontStyle.Bold, NabiraTheme.Accent));
        demo.Controls.Add(NabiraTheme.Label("ghbdtn", 365, 22, 86, 28, 12, FontStyle.Strikeout, NabiraTheme.Muted));
        demo.Controls.Add(NabiraTheme.Label("→", 454, 21, 30, 28, 13, FontStyle.Bold, NabiraTheme.Accent));
        demo.Controls.Add(NabiraTheme.Label("привет", 490, 20, 130, 30, 13, FontStyle.Bold, NabiraTheme.Ink));
        _content.Controls.Add(demo);

        int y = 208;
        CardPanel correctionCard = Section("Автокоррекция", "Исправление текста сразу после пробела", y, 350);
        AddToggle(correctionCard, 66, "Автоматически исправлять раскладку",
            "Nabira заменит неверно набранное слово после пробела.", s.AutoConvert,
            value => { s.AutoConvert = value; s.Save(); });
        AddToggle(correctionCard, 124, "Исправлять опечатки",
            "Только уверенные исправления на русском и английском.", s.TypoCorrection,
            value => { s.TypoCorrection = value; s.Save(); });
        AddToggle(correctionCard, 182, "Исправлять ДВе заглавные",
            "Например, «ПРивет» превратится в «Привет».", s.FixDoubleCapitals,
            value => { s.FixDoubleCapitals = value; s.Save(); });
        AddToggle(correctionCard, 240, "Исправлять пунктуацию",
            "Знаки препинания, введённые в неверной раскладке.", s.FixPunctuation,
            value => { s.FixPunctuation = value; s.Save(); });
        AddToggle(correctionCard, 298, "Автоматически ставить «ё»",
            "Только в однозначных русских словах.", s.Yoficator,
            value => { s.Yoficator = value; s.Save(); if (value) _ = Task.Run(Yoficator.WarmUp); });
        _content.Controls.Add(correctionCard);

        y += 370;
        CardPanel conversionCard = Section("Конвертация", "Ручное исправление текста и обучение", y, 270);
        var trigger = AddCombo(conversionCard, 72, "Исправлять текст по нажатию", TriggerItems(), (int)s.Trigger);
        trigger.SelectedIndexChanged += (_, _) =>
        {
            s.Trigger = (TriggerKind)trigger.SelectedIndex;
            s.Save();
            TriggerChanged?.Invoke(s.Trigger);
        };
        AddToggle(conversionCard, 126, "Конвертировать всю строку",
            "Иначе исправляется последнее набранное слово.", s.ConvertWholeLine,
            value => { s.ConvertWholeLine = value; s.Save(); });
        AddToggle(conversionCard, 184, "Умная конвертация выделения",
            "Уже правильные слова останутся без изменений.", s.SmartConversion,
            value => { s.SmartConversion = value; s.Save(); });
        AddToggle(conversionCard, 242, "Запоминать мои отмены",
            "Явная отмена добавляет слово в персональное исключение.", s.AdaptiveLearning,
            value => { s.AdaptiveLearning = value; s.Save(); });
        _content.Controls.Add(conversionCard);

        y += 290;
        CardPanel hotkeysCard = Section("Горячие клавиши", "Отдельные действия Nabira", y, 190);
        var switchCombo = AddCombo(hotkeysCard, 72, "Только переключить раскладку", OptionalTriggerItems(),
            s.SwitchTriggerEnabled ? (int)s.SwitchTrigger + 1 : 0);
        switchCombo.SelectedIndexChanged += (_, _) =>
        {
            int index = switchCombo.SelectedIndex;
            s.SwitchTriggerEnabled = index > 0;
            if (index > 0) s.SwitchTrigger = (TriggerKind)(index - 1);
            s.Save();
            SwitchChanged?.Invoke();
        };
        var caseCombo = AddCombo(hotkeysCard, 128, "Изменить регистр текста", OptionalTriggerItems(),
            s.CaseTriggerEnabled ? (int)s.CaseTrigger + 1 : 0);
        caseCombo.SelectedIndexChanged += (_, _) =>
        {
            int index = caseCombo.SelectedIndex;
            if (index > 0)
            {
                var chosen = (TriggerKind)(index - 1);
                if (chosen == s.Trigger || (s.SwitchTriggerEnabled && chosen == s.SwitchTrigger))
                {
                    MessageBox.Show(L10n.T("settings.hotkey.conflict"), Text,
                        MessageBoxButtons.OK, MessageBoxIcon.Information);
                    caseCombo.SelectedIndex = 0;
                    return;
                }
                s.CaseTrigger = chosen;
            }
            s.CaseTriggerEnabled = index > 0;
            s.Save();
            CaseChanged?.Invoke();
        };
        _content.Controls.Add(hotkeysCard);

        y += 210;
        CardPanel systemCard = Section("Система", "Запуск, раскладки и обновления", y, 270);
        AddToggle(systemCard, 66, "Запускать вместе с Windows", "Nabira будет готова сразу после входа.",
            AutoStart.IsEnabled(), AutoStart.SetEnabled);
        AddToggle(systemCard, 124, "Запоминать раскладку для приложений",
            "Например, русский в Telegram и английский в редакторе кода.", s.PerAppLayout,
            value => { s.PerAppLayout = value; s.Save(); });
        AddToggle(systemCard, 182, "Звук при смене раскладки", "Короткое подтверждение успешного переключения.",
            s.SoundOnSwitch, value => { s.SoundOnSwitch = value; s.Save(); });
        AddToggle(systemCard, 240, "Проверять обновления", "Автоматическая проверка не чаще одного раза в сутки.",
            s.CheckUpdatesEnabled, value => { s.CheckUpdatesEnabled = value; s.Save(); });
        _content.Controls.Add(systemCard);

        y += 294;
        var exceptions = NabiraTheme.SecondaryButton("Настроить исключения", 38, y, 190, 42);
        exceptions.Click += (_, _) => { using var form = new ExceptionsForm(); form.ShowDialog(this); };
        var site = MakeLink("nabira.site", 250, y + 12, "https://nabira.site");
        var telegram = MakeLink("Поддержка: @mitfleg", 348, y + 12, "https://t.me/mitfleg");
        var close = NabiraTheme.PrimaryButton("Готово", 586, y, 112, 42);
        close.Anchor = AnchorStyles.Top | AnchorStyles.Right;
        close.Click += (_, _) => Close();
        _content.Controls.AddRange(new Control[] { exceptions, site, telegram, close });

        _content.AutoScrollMinSize = new Size(0, y + 82);
        AcceptButton = close;
    }

    private static GradientPanel BuildSidebar()
    {
        var panel = new GradientPanel { Dock = DockStyle.Left, Width = 236 };
        var mark = NabiraTheme.Label("A│Я", 30, 34, 76, 48, 21, FontStyle.Bold, Color.White);
        var name = NabiraTheme.Label("Nabira", 30, 92, 170, 40, 20, FontStyle.Bold, Color.White);
        var tag = NabiraTheme.Label("Печатайте мысль,\nа не раскладку.", 30, 133, 180, 62, 11,
            FontStyle.Bold, Color.FromArgb(225, 238, 255));
        var privacy = NabiraTheme.Label("Ваш текст остаётся\nна этом компьютере", 30, 615, 180, 50, 9,
            color: Color.FromArgb(220, 240, 255));
        privacy.Anchor = AnchorStyles.Left | AnchorStyles.Bottom;
        panel.Controls.AddRange(new Control[] { mark, name, tag, privacy });
        return panel;
    }

    private static CardPanel Section(string title, string subtitle, int top, int height)
    {
        var card = new CardPanel
        {
            Left = 38,
            Top = top,
            Width = 660,
            Height = height,
            Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right,
        };
        card.Controls.Add(NabiraTheme.Label(title, 22, 16, 280, 28, 13, FontStyle.Bold));
        card.Controls.Add(NabiraTheme.Label(subtitle, 22, 43, 470, 22, 9, color: NabiraTheme.Muted));
        return card;
    }

    private static void AddToggle(Control card, int top, string title, string detail, bool value,
        Action<bool> changed)
    {
        card.Controls.Add(NabiraTheme.Label(title, 22, top, 490, 23, 10, FontStyle.Bold));
        card.Controls.Add(NabiraTheme.Label(detail, 22, top + 23, 500, 22, 8.7f, color: NabiraTheme.Muted));
        var toggle = new ToggleSwitch
        {
            Left = card.Width - 70,
            Top = top + 7,
            Checked = value,
            Anchor = AnchorStyles.Top | AnchorStyles.Right,
            AccessibleName = title,
        };
        toggle.CheckedChanged += (_, _) => changed(toggle.Checked);
        card.Controls.Add(toggle);
    }

    private static ComboBox AddCombo(Control card, int top, string title, object[] items, int selected)
    {
        card.Controls.Add(NabiraTheme.Label(title, 22, top + 7, 300, 25, 9.5f, FontStyle.Bold));
        var combo = NabiraTheme.ComboBox(card.Width - 292, top, 264);
        combo.Anchor = AnchorStyles.Top | AnchorStyles.Right;
        combo.Items.AddRange(items);
        combo.SelectedIndex = Math.Clamp(selected, 0, items.Length - 1);
        card.Controls.Add(combo);
        return combo;
    }

    private static object[] TriggerItems() => new object[]
    {
        Tray.TrayIcon.TriggerName(TriggerKind.CtrlDoubleTap),
        Tray.TrayIcon.TriggerName(TriggerKind.ShiftDoubleTap),
        Tray.TrayIcon.TriggerName(TriggerKind.PauseBreak),
    };

    private static object[] OptionalTriggerItems() => new object[]
    {
        L10n.T("settings.off"),
        Tray.TrayIcon.TriggerName(TriggerKind.CtrlDoubleTap),
        Tray.TrayIcon.TriggerName(TriggerKind.ShiftDoubleTap),
        Tray.TrayIcon.TriggerName(TriggerKind.PauseBreak),
    };

    private static LinkLabel MakeLink(string text, int left, int top, string url)
    {
        var link = new LinkLabel
        {
            Text = text,
            Left = left,
            Top = top,
            AutoSize = true,
            Font = NabiraTheme.Font(9.5f, FontStyle.Bold),
            LinkColor = NabiraTheme.Accent,
            ActiveLinkColor = NabiraTheme.Cyan,
        };
        link.LinkClicked += (_, _) => OpenUrl(url);
        return link;
    }

    private static void OpenUrl(string url)
    {
        try { System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(url) { UseShellExecute = true }); }
        catch { }
    }
}
