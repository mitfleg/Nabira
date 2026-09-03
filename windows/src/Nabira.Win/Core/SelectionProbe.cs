using System.Runtime.InteropServices;
using Interop.UIAutomationClient;

namespace Nabira.Win.Core;

/// <summary>Reads selection presence without touching the clipboard. This prevents editors such
/// as VS Code from treating Ctrl+C with no selection as a copied line and later duplicating it.</summary>
internal static class SelectionProbe
{
    private static readonly IUIAutomation Automation = new CUIAutomation8();

    internal static bool TryHasExplicitSelection(out bool hasSelection)
    {
        hasSelection = false;
        try
        {
            IUIAutomationElement? focused = Automation.GetFocusedElement();
            object? rawPattern = focused?.GetCurrentPattern((int)UIA_PatternIds.UIA_TextPatternId);
            if (rawPattern is not IUIAutomationTextPattern pattern) return false;

            IUIAutomationTextRangeArray? ranges = pattern.GetSelection();
            if (ranges == null) return false;
            for (int index = 0; index < ranges.Length; index++)
            {
                IUIAutomationTextRange range = ranges.GetElement(index);
                if (range.CompareEndpoints(
                    TextPatternRangeEndpoint.TextPatternRangeEndpoint_Start,
                    range,
                    TextPatternRangeEndpoint.TextPatternRangeEndpoint_End) != 0)
                {
                    hasSelection = true;
                    break;
                }
            }
            return true;
        }
        catch (COMException) { return false; }
        catch (InvalidCastException) { return false; }
    }
}
