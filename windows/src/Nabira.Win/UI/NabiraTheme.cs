using System.Drawing.Drawing2D;
using System.Windows.Forms;

namespace Nabira.Win.UI;

internal static class NabiraTheme
{
    public static readonly Color Ink = Color.FromArgb(20, 25, 47);
    public static readonly Color Muted = Color.FromArgb(101, 112, 137);
    public static readonly Color Cloud = Color.FromArgb(245, 247, 252);
    public static readonly Color Surface = Color.White;
    public static readonly Color Stroke = Color.FromArgb(226, 231, 242);
    public static readonly Color Accent = Color.FromArgb(82, 102, 248);
    public static readonly Color AccentSoft = Color.FromArgb(235, 238, 255);
    public static readonly Color Cyan = Color.FromArgb(55, 184, 234);
    public static readonly Color Success = Color.FromArgb(25, 160, 111);
    public static readonly Color Danger = Color.FromArgb(211, 65, 89);

    public static Font Font(float size, FontStyle style = FontStyle.Regular) =>
        new("Segoe UI", size, style, GraphicsUnit.Point);

    public static Label Label(string text, int left, int top, int width, int height,
        float size = 9.5f, FontStyle style = FontStyle.Regular, Color? color = null) => new()
        {
            Text = text,
            Left = left,
            Top = top,
            Width = width,
            Height = height,
            Font = Font(size, style),
            ForeColor = color ?? Ink,
            BackColor = Color.Transparent,
            AutoEllipsis = true,
        };

    public static ComboBox ComboBox(int left, int top, int width) => new()
    {
        Left = left,
        Top = top,
        Width = width,
        Height = 34,
        DropDownStyle = ComboBoxStyle.DropDownList,
        FlatStyle = FlatStyle.Flat,
        Font = Font(9.5f),
        BackColor = Surface,
        ForeColor = Ink,
    };

    public static Button PrimaryButton(string text, int left, int top, int width, int height = 40)
    {
        var button = new RoundedButton
        {
            Text = text,
            Left = left,
            Top = top,
            Width = width,
            Height = height,
            BackColor = Accent,
            ForeColor = Color.White,
            FlatStyle = FlatStyle.Flat,
            Font = Font(9.5f, FontStyle.Bold),
            Cursor = Cursors.Hand,
        };
        button.FlatAppearance.BorderSize = 0;
        return button;
    }

    public static Button SecondaryButton(string text, int left, int top, int width, int height = 40)
    {
        var button = new RoundedButton
        {
            Text = text,
            Left = left,
            Top = top,
            Width = width,
            Height = height,
            BackColor = AccentSoft,
            ForeColor = Accent,
            FlatStyle = FlatStyle.Flat,
            Font = Font(9.5f, FontStyle.Bold),
            Cursor = Cursors.Hand,
        };
        button.FlatAppearance.BorderSize = 0;
        return button;
    }

    public static TextBox TextBox(int left, int top, int width, bool password = false,
        bool multiline = false) => new()
        {
            Left = left,
            Top = top,
            Width = width,
            Height = multiline ? 176 : 34,
            Font = Font(10),
            BorderStyle = BorderStyle.FixedSingle,
            BackColor = Surface,
            ForeColor = Ink,
            UseSystemPasswordChar = password,
            Multiline = multiline,
            ScrollBars = multiline ? ScrollBars.Vertical : ScrollBars.None,
        };

    /// <summary>A deterministic two-column shell. Unlike sibling DockStyle.Left/Fill controls,
    /// TableLayoutPanel keeps the content column outside the brand rail at every Windows DPI.</summary>
    public static TableLayoutPanel SplitShell(Control sidebar, Control content, int sidebarWidth)
    {
        var shell = new TableLayoutPanel
        {
            Name = "nabiraSplitShell",
            Dock = DockStyle.Fill,
            ColumnCount = 2,
            RowCount = 1,
            Margin = Padding.Empty,
            Padding = Padding.Empty,
            BackColor = Cloud,
        };
        shell.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, sidebarWidth));
        shell.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        shell.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        sidebar.Dock = DockStyle.Fill;
        sidebar.Margin = Padding.Empty;
        content.Dock = DockStyle.Fill;
        content.Margin = Padding.Empty;
        shell.Controls.Add(sidebar, 0, 0);
        shell.Controls.Add(content, 1, 0);
        return shell;
    }

    public static GraphicsPath RoundedRectangle(Rectangle bounds, int radius)
    {
        int diameter = radius * 2;
        var path = new GraphicsPath();
        path.AddArc(bounds.Left, bounds.Top, diameter, diameter, 180, 90);
        path.AddArc(bounds.Right - diameter, bounds.Top, diameter, diameter, 270, 90);
        path.AddArc(bounds.Right - diameter, bounds.Bottom - diameter, diameter, diameter, 0, 90);
        path.AddArc(bounds.Left, bounds.Bottom - diameter, diameter, diameter, 90, 90);
        path.CloseFigure();
        return path;
    }
}

internal sealed class GradientPanel : Panel
{
    public Color StartColor { get; set; } = Color.FromArgb(59, 76, 220);
    public Color EndColor { get; set; } = Color.FromArgb(53, 181, 231);

    public GradientPanel()
    {
        SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer |
                 ControlStyles.ResizeRedraw | ControlStyles.UserPaint, true);
    }

    protected override void OnPaintBackground(PaintEventArgs e)
    {
        using var brush = new LinearGradientBrush(ClientRectangle, StartColor, EndColor, 50f);
        e.Graphics.FillRectangle(brush, ClientRectangle);
        e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
        using var glow = new SolidBrush(Color.FromArgb(26, Color.White));
        e.Graphics.FillEllipse(glow, Width - 210, 90, 320, 320);
        e.Graphics.FillEllipse(glow, -130, Height - 190, 270, 270);
    }
}

internal sealed class CardPanel : Panel
{
    public int Radius { get; set; } = 18;

    public CardPanel()
    {
        BackColor = NabiraTheme.Surface;
        SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer |
                 ControlStyles.ResizeRedraw | ControlStyles.UserPaint, true);
    }

    protected override void OnPaintBackground(PaintEventArgs e) =>
        e.Graphics.Clear(Parent?.BackColor ?? NabiraTheme.Cloud);

    protected override void OnPaint(PaintEventArgs e)
    {
        e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
        var bounds = new Rectangle(0, 0, Width - 1, Height - 1);
        using var path = NabiraTheme.RoundedRectangle(bounds, Radius);
        using var fill = new SolidBrush(BackColor);
        using var stroke = new Pen(NabiraTheme.Stroke);
        e.Graphics.FillPath(fill, path);
        e.Graphics.DrawPath(stroke, path);
        base.OnPaint(e);
    }
}

internal sealed class ProgressStrip : Control
{
    private int _value;
    public int Maximum { get; set; } = 7;
    public int Value
    {
        get => _value;
        set { _value = Math.Clamp(value, 0, Math.Max(1, Maximum)); Invalidate(); }
    }

    public ProgressStrip()
    {
        Height = 8;
        SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer |
                 ControlStyles.ResizeRedraw | ControlStyles.UserPaint, true);
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
        var bounds = new Rectangle(0, 0, Width - 1, Height - 1);
        using var track = NabiraTheme.RoundedRectangle(bounds, Math.Max(1, Height / 2));
        using var trackBrush = new SolidBrush(NabiraTheme.Stroke);
        e.Graphics.FillPath(trackBrush, track);
        int fillWidth = (int)Math.Round((Width - 1) * (Value / (double)Math.Max(1, Maximum)));
        if (fillWidth > Height)
        {
            using var fillPath = NabiraTheme.RoundedRectangle(new Rectangle(0, 0, fillWidth, Height - 1), Math.Max(1, Height / 2));
            using var fill = new SolidBrush(NabiraTheme.Accent);
            e.Graphics.FillPath(fill, fillPath);
        }
    }
}

internal sealed class RoundedButton : Button
{
    protected override void OnResize(EventArgs e)
    {
        base.OnResize(e);
        if (Width <= 0 || Height <= 0) return;
        using var path = NabiraTheme.RoundedRectangle(new Rectangle(0, 0, Width, Height), 10);
        Region = new Region(path);
    }
}

internal sealed class ToggleSwitch : Control
{
    private bool _checked;

    public bool Checked
    {
        get => _checked;
        set
        {
            if (_checked == value) return;
            _checked = value;
            Invalidate();
            CheckedChanged?.Invoke(this, EventArgs.Empty);
        }
    }

    public event EventHandler? CheckedChanged;

    public ToggleSwitch()
    {
        Size = new Size(46, 26);
        Cursor = Cursors.Hand;
        TabStop = true;
        SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer |
                 ControlStyles.ResizeRedraw | ControlStyles.UserPaint | ControlStyles.Selectable, true);
        AccessibleRole = AccessibleRole.CheckButton;
    }

    protected override void OnClick(EventArgs e)
    {
        Checked = !Checked;
        base.OnClick(e);
    }

    protected override void OnKeyDown(KeyEventArgs e)
    {
        if (e.KeyCode is Keys.Space or Keys.Enter)
        {
            Checked = !Checked;
            e.Handled = true;
        }
        base.OnKeyDown(e);
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
        var track = new Rectangle(1, 2, Width - 2, Height - 4);
        using var path = NabiraTheme.RoundedRectangle(track, track.Height / 2);
        using var brush = new SolidBrush(Checked ? NabiraTheme.Accent : Color.FromArgb(199, 206, 221));
        e.Graphics.FillPath(brush, path);

        int knob = Height - 8;
        int x = Checked ? Width - knob - 4 : 4;
        using var knobBrush = new SolidBrush(Color.White);
        e.Graphics.FillEllipse(knobBrush, x, 4, knob, knob);

        if (Focused)
        {
            using var focus = new Pen(Color.FromArgb(100, NabiraTheme.Accent)) { DashStyle = DashStyle.Dot };
            e.Graphics.DrawRectangle(focus, 0, 0, Width - 1, Height - 1);
        }
    }
}
