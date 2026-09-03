using System.Drawing.Drawing2D;
using Nabira.Win.Core;

namespace Nabira.Win.UI;

/// <summary>Branded replacement for the legacy Win32 popup menu. It uses ordinary WinForms
/// controls so typography, spacing, hover and DPI scaling match the rest of Nabira.</summary>
internal sealed class TrayMenuForm : Form
{
    private TriggerKind _trigger;
    private bool _enabled;
    private bool _wholeLine;
    private bool _autoConvert;

    public TrayMenuForm(
        string layoutName,
        string accountStatus,
        bool accessAllowed,
        bool enabled,
        TriggerKind trigger,
        bool wholeLine,
        bool autoConvert,
        Action<bool> enabledChanged,
        Action<TriggerKind> triggerChanged,
        Action<bool> wholeLineChanged,
        Action<bool> autoConvertChanged,
        bool sageInstalled,
        Action sageCorrectionRequested,
        Action accountRequested,
        Action settingsRequested,
        Action updateRequested,
        Action quitRequested)
    {
        _enabled = enabled;
        _trigger = trigger;
        _wholeLine = wholeLine;
        _autoConvert = autoConvert;

        FormBorderStyle = FormBorderStyle.None;
        ShowInTaskbar = false;
        TopMost = true;
        StartPosition = FormStartPosition.Manual;
        ClientSize = new Size(374, 608);
        BackColor = NabiraTheme.Surface;
        Font = NabiraTheme.Font(9.5f);
        AutoScaleMode = AutoScaleMode.Dpi;
        Padding = new Padding(10);
        DoubleBuffered = true;
        AccessibleName = "Меню Nabira";

        var brand = NabiraTheme.Label("Nabira", 24, 18, 190, 34, 17, FontStyle.Bold);
        var layout = NabiraTheme.Label(layoutName, 24, 53, 130, 22, 9, FontStyle.Bold, NabiraTheme.Accent);
        var status = NabiraTheme.Label(accountStatus, 152, 53, 194, 22, 8.5f,
            color: accessAllowed ? NabiraTheme.Success : NabiraTheme.Muted);
        status.TextAlign = ContentAlignment.MiddleRight;
        Controls.AddRange(new Control[] { brand, layout, status });

        var enableRow = Row(86, "N", EnabledTitle(), "Работает во всех разрешённых приложениях",
            toggle: _enabled, enabled: accessAllowed);
        enableRow.Click += (_, _) =>
        {
            _enabled = !_enabled;
            enableRow.Title = EnabledTitle();
            enableRow.ToggleValue = _enabled;
            enableRow.Invalidate();
            enabledChanged(_enabled);
        };

        var triggerRow = Row(150, "↔", "Исправление текста", TriggerName(_trigger), trailing: "Изменить");
        triggerRow.Click += (_, _) =>
        {
            _trigger = (TriggerKind)(((int)_trigger + 1) % 3);
            triggerRow.Detail = TriggerName(_trigger);
            triggerRow.Invalidate();
            triggerChanged(_trigger);
        };

        var wholeLineRow = Row(210, "¶", "Конвертировать всю строку",
            "Иначе — только последнее слово", toggle: _wholeLine);
        wholeLineRow.Click += (_, _) =>
        {
            _wholeLine = !_wholeLine;
            wholeLineRow.ToggleValue = _wholeLine;
            wholeLineRow.Invalidate();
            wholeLineChanged(_wholeLine);
        };

        var autoRow = Row(270, "A", "Автокоррекция при наборе",
            "Исправлять после пробела", toggle: _autoConvert);
        autoRow.Click += (_, _) =>
        {
            _autoConvert = !_autoConvert;
            autoRow.ToggleValue = _autoConvert;
            autoRow.Invalidate();
            autoConvertChanged(_autoConvert);
        };

        var sageRow = Row(330, "ИИ", "Исправить выделение или строку",
            sageInstalled ? "Локальная модель · Ctrl+Alt+Space" : "Подключается в настройках",
            trailing: sageInstalled ? "Запустить" : "");
        sageRow.Enabled = sageInstalled;
        sageRow.Click += (_, _) => InvokeAndClose(sageCorrectionRequested);

        var accountRow = Row(402, "●", "Аккаунт", accountStatus, trailing: "Открыть");
        accountRow.Click += (_, _) => InvokeAndClose(accountRequested);
        var settingsRow = Row(462, "⚙", "Настройки", "Все функции Nabira", trailing: "Открыть");
        settingsRow.Click += (_, _) => InvokeAndClose(settingsRequested);
        var updateRow = Row(522, "↓", "Проверить обновления", "Установлена текущая версия");
        updateRow.Click += (_, _) => InvokeAndClose(updateRequested);

        var quit = new TrayMenuRow
        {
            Left = 10,
            Top = 576,
            Width = 354,
            Height = 28,
            Glyph = "×",
            Title = "Выйти из Nabira",
            Danger = true,
            AccessibleName = "Выйти из Nabira",
        };
        quit.Click += (_, _) => InvokeAndClose(quitRequested);

        Controls.AddRange(new Control[]
        {
            enableRow, Divider(142), triggerRow, wholeLineRow, autoRow, sageRow, Divider(392),
            accountRow, settingsRow, updateRow, Divider(570), quit,
        });

        Deactivate += (_, _) => Close();
    }

    protected override CreateParams CreateParams
    {
        get
        {
            const int CsDropShadow = 0x00020000;
            var value = base.CreateParams;
            value.ClassStyle |= CsDropShadow;
            return value;
        }
    }

    protected override void OnResize(EventArgs e)
    {
        base.OnResize(e);
        if (Width <= 0 || Height <= 0) return;
        using var path = NabiraTheme.RoundedRectangle(new Rectangle(0, 0, Width, Height), 18);
        Region = new Region(path);
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        base.OnPaint(e);
        e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
        using var path = NabiraTheme.RoundedRectangle(new Rectangle(0, 0, Width - 1, Height - 1), 18);
        using var stroke = new Pen(NabiraTheme.Stroke);
        e.Graphics.DrawPath(stroke, path);
    }

    public void ShowAt(Point cursor)
    {
        Rectangle area = Screen.FromPoint(cursor).WorkingArea;
        int minX = area.Left + 8;
        int maxX = Math.Max(minX, area.Right - Width - 8);
        int x = Math.Clamp(cursor.X - Width + 18, minX, maxX);
        int above = cursor.Y - Height - 12;
        int y = above >= area.Top + 8 ? above : cursor.Y + 12;
        int minY = area.Top + 8;
        int maxY = Math.Max(minY, area.Bottom - Height - 8);
        y = Math.Clamp(y, minY, maxY);
        Location = new Point(x, y);
        Show();
        Activate();
    }

    private string EnabledTitle() => _enabled ? "Nabira включена" : "Nabira приостановлена";

    private static string TriggerName(TriggerKind trigger) => trigger switch
    {
        TriggerKind.CtrlDoubleTap => "Двойной Ctrl",
        TriggerKind.ShiftDoubleTap => "Двойной Shift",
        TriggerKind.PauseBreak => "Клавиша Pause/Break",
        _ => "Не назначено",
    };

    private static TrayMenuRow Row(int top, string glyph, string title, string detail,
        string trailing = "", bool? toggle = null, bool enabled = true) => new()
    {
        Left = 10,
        Top = top,
        Width = 354,
        Height = 58,
        Glyph = glyph,
        Title = title,
        Detail = detail,
        TrailingText = trailing,
        ShowToggle = toggle.HasValue,
        ToggleValue = toggle ?? false,
        Enabled = enabled,
        AccessibleName = title,
    };

    private static Panel Divider(int top) => new()
    {
        Left = 24,
        Top = top,
        Width = 326,
        Height = 1,
        BackColor = NabiraTheme.Stroke,
    };

    private void InvokeAndClose(Action action)
    {
        Close();
        action();
    }
}

internal sealed class TrayMenuRow : Control
{
    private bool _hovered;

    public string Glyph { get; set; } = "";
    public string Title { get; set; } = "";
    public string Detail { get; set; } = "";
    public string TrailingText { get; set; } = "";
    public bool ShowToggle { get; set; }
    public bool ToggleValue { get; set; }
    public bool Danger { get; set; }

    public TrayMenuRow()
    {
        Cursor = Cursors.Hand;
        TabStop = true;
        SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer |
                 ControlStyles.ResizeRedraw | ControlStyles.UserPaint | ControlStyles.Selectable, true);
    }

    protected override void OnMouseEnter(EventArgs e) { _hovered = true; Invalidate(); base.OnMouseEnter(e); }
    protected override void OnMouseLeave(EventArgs e) { _hovered = false; Invalidate(); base.OnMouseLeave(e); }

    protected override void OnKeyDown(KeyEventArgs e)
    {
        if (e.KeyCode is Keys.Space or Keys.Enter)
        {
            OnClick(EventArgs.Empty);
            e.Handled = true;
        }
        base.OnKeyDown(e);
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
        Color background = _hovered && Enabled ? NabiraTheme.AccentSoft : NabiraTheme.Surface;
        using (var path = NabiraTheme.RoundedRectangle(new Rectangle(0, 0, Width - 1, Height - 1), 12))
        using (var fill = new SolidBrush(background))
            e.Graphics.FillPath(fill, path);

        Color titleColor = !Enabled ? Color.FromArgb(170, NabiraTheme.Muted)
            : Danger ? NabiraTheme.Danger : NabiraTheme.Ink;
        Color detailColor = Enabled ? NabiraTheme.Muted : Color.FromArgb(145, NabiraTheme.Muted);
        Color glyphBackground = Danger ? Color.FromArgb(255, 235, 239) : NabiraTheme.AccentSoft;

        using (var circle = new SolidBrush(glyphBackground))
            e.Graphics.FillEllipse(circle, 10, 11, 36, 36);
        TextRenderer.DrawText(e.Graphics, Glyph, NabiraTheme.Font(10, FontStyle.Bold),
            new Rectangle(10, 11, 36, 36), Danger ? NabiraTheme.Danger : NabiraTheme.Accent,
            TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPadding);
        TextRenderer.DrawText(e.Graphics, Title, NabiraTheme.Font(9.5f, FontStyle.Bold),
            new Rectangle(58, Detail.Length == 0 ? 18 : 10, 210, 24), titleColor,
            TextFormatFlags.EndEllipsis | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPadding);
        if (Detail.Length > 0)
            TextRenderer.DrawText(e.Graphics, Detail, NabiraTheme.Font(8.3f),
                new Rectangle(58, 32, 230, 19), detailColor,
                TextFormatFlags.EndEllipsis | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPadding);

        if (ShowToggle)
            DrawToggle(e.Graphics);
        else if (TrailingText.Length > 0)
            TextRenderer.DrawText(e.Graphics, TrailingText, NabiraTheme.Font(8.2f, FontStyle.Bold),
                new Rectangle(264, 17, 78, 22), Danger ? NabiraTheme.Danger : NabiraTheme.Accent,
                TextFormatFlags.Right | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPadding);

        if (Focused)
            ControlPaint.DrawFocusRectangle(e.Graphics, new Rectangle(4, 4, Width - 8, Height - 8));
    }

    private void DrawToggle(Graphics graphics)
    {
        var bounds = new Rectangle(302, 18, 40, 22);
        using var path = NabiraTheme.RoundedRectangle(bounds, 11);
        using var fill = new SolidBrush(ToggleValue ? NabiraTheme.Accent : Color.FromArgb(202, 209, 224));
        graphics.FillPath(fill, path);
        int knobX = ToggleValue ? 322 : 305;
        using var knob = new SolidBrush(Color.White);
        graphics.FillEllipse(knob, knobX, 21, 16, 16);
    }
}
