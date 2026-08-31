using System;
using System.Runtime.InteropServices;
using Nabira.Win.Native;
using Nabira.Win.Core;
using Xunit;

namespace Nabira.Win.Tests;

/// <summary>
/// Guards the SendInput ABI. The whole conversion feature injects keystrokes via
/// <c>SendInput</c>, and SendInput rejects any call whose <c>cbSize</c> ≠ the real
/// <c>sizeof(INPUT)</c> (40 on 64-bit, 28 on 32-bit) — returning 0 and injecting NOTHING, with no
/// exception. A too-small INPUT union (only KEYBDINPUT, not the larger MOUSEINPUT) shipped once and
/// silently broke every conversion on real Windows. These tests run on the windows-latest CI.
/// </summary>
public class SendInputTests
{
    [Fact]
    public void Captured_word_is_replaced_in_one_ordered_batch()
    {
        var inputs = TextInjector.BuildCapturedWordInputs(
            wordKeyCount: 3, text: "мир", boundaryVk: KeystrokeBuffer.VK_SPACE);

        Assert.Equal(14, inputs.Length); // 3 backspaces + 3 Unicode chars + Space, all down/up
        Assert.Equal(Win32.VK_BACK, inputs[0].U.ki.wVk);
        Assert.Equal(Win32.KEYEVENTF_KEYUP, inputs[1].U.ki.dwFlags);
        Assert.Equal('м', inputs[6].U.ki.wScan);
        Assert.Equal(Win32.KEYEVENTF_UNICODE, inputs[6].U.ki.dwFlags);
        Assert.Equal(KeystrokeBuffer.VK_SPACE, inputs[^2].U.ki.wVk);
        Assert.Equal(Win32.InjectedMarker, inputs[^1].U.ki.dwExtraInfo);
        Assert.Equal(Win32.KEYEVENTF_KEYUP, inputs[^1].U.ki.dwFlags);
    }

    [Fact]
    public void Captured_enter_is_reinjected_after_the_replacement()
    {
        var inputs = TextInjector.BuildCapturedWordInputs(
            wordKeyCount: 4, text: "хаха", boundaryVk: KeystrokeBuffer.VK_RETURN);

        Assert.Equal(18, inputs.Length); // 4 backspaces + 4 Unicode chars + Enter, all down/up
        Assert.Equal(KeystrokeBuffer.VK_RETURN, inputs[^2].U.ki.wVk);
        Assert.Equal(Win32.InjectedMarker, inputs[^1].U.ki.dwExtraInfo);
        Assert.Equal(Win32.KEYEVENTF_KEYUP, inputs[^1].U.ki.dwFlags);
    }

    [Fact]
    public void Input_struct_has_the_size_the_OS_expects()
    {
        int expected = IntPtr.Size == 8 ? 40 : 28;
        Assert.Equal(expected, Marshal.SizeOf<Win32.INPUT>());
    }

    [Fact]
    public void SendInput_accepts_our_struct_and_injects()
    {
        // A harmless Unicode keystroke (discarded when nothing is focused). SendInput returns the
        // number of events inserted; 0 would mean the OS rejected our struct (the shipped bug).
        var input = new Win32.INPUT
        {
            type = Win32.INPUT_KEYBOARD,
            U = new Win32.InputUnion
            {
                ki = new Win32.KEYBDINPUT
                {
                    wVk = 0,
                    wScan = 'a',
                    dwFlags = Win32.KEYEVENTF_UNICODE | Win32.KEYEVENTF_KEYUP,
                    time = 0,
                    dwExtraInfo = IntPtr.Zero,
                }
            }
        };
        uint sent = Win32.SendInput(1, new[] { input }, Marshal.SizeOf<Win32.INPUT>());
        Assert.Equal(1u, sent);
    }
}
