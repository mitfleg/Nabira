using System.Drawing;
using System.Runtime.ExceptionServices;
using System.Windows.Forms;
using Nabira.Win.UI;
using Xunit;

namespace Nabira.Win.Tests;

public sealed class WindowsLayoutTests
{
    [Fact]
    public void SplitShell_KeepsContentOutsideSidebar_WhenWindowResizes()
    {
        RunInSta(() =>
        {
            using var form = new Form { ClientSize = new Size(980, 700) };
            using var sidebar = new Panel { Name = "sidebar" };
            using var content = new Panel { Name = "content" };
            TableLayoutPanel shell = NabiraTheme.SplitShell(sidebar, content, 236);
            form.Controls.Add(shell);

            form.CreateControl();
            shell.PerformLayout();
            AssertColumnsDoNotOverlap(sidebar, content, 236);

            form.ClientSize = new Size(1440, 900);
            shell.PerformLayout();
            AssertColumnsDoNotOverlap(sidebar, content, 236);

            form.ClientSize = new Size(900, 640);
            shell.PerformLayout();
            AssertColumnsDoNotOverlap(sidebar, content, 236);
        });
    }

    private static void AssertColumnsDoNotOverlap(Control sidebar, Control content, int expectedSidebarWidth)
    {
        Assert.Equal(0, sidebar.Left);
        Assert.Equal(expectedSidebarWidth, sidebar.Width);
        Assert.Equal(sidebar.Right, content.Left);
        Assert.True(content.Width > 0);
    }

    private static void RunInSta(Action action)
    {
        Exception? failure = null;
        var thread = new Thread(() =>
        {
            try { action(); }
            catch (Exception exception) { failure = exception; }
        });
        thread.SetApartmentState(ApartmentState.STA);
        thread.Start();
        thread.Join();
        if (failure is not null) ExceptionDispatchInfo.Capture(failure).Throw();
    }
}
