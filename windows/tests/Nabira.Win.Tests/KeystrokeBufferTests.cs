using Nabira.Win.Core;
using Xunit;

namespace Nabira.Win.Tests;

/// <summary>Pure-logic tests for the keystroke buffer — the part that ports 1:1 across
/// platforms and can be verified in CI without a live Windows session.</summary>
public class KeystrokeBufferTests
{
    [Theory]
    [InlineData(0x20)] // Space
    [InlineData(0x0D)] // Enter
    [InlineData(0x09)] // Tab
    [InlineData(0x1B)] // Esc
    public void Boundaries_end_a_word(uint vk) => Assert.True(KeystrokeBuffer.IsWordBoundary(vk));

    [Theory]
    [InlineData(0x41)] // A
    [InlineData(0x08)] // Backspace
    public void Letters_and_backspace_are_not_boundaries(uint vk) =>
        Assert.False(KeystrokeBuffer.IsWordBoundary(vk));

    [Theory]
    [InlineData(0x41)] // A
    [InlineData(0x5A)] // Z
    [InlineData(0x30)] // 0
    [InlineData(0xBA)] // OEM_1 ';' — a letter in ЙЦУКЕН
    [InlineData(0xE2)] // OEM_102
    public void Typing_keys_are_buffered(uint vk) => Assert.True(KeystrokeBuffer.IsTypingKey(vk));

    [Theory]
    [InlineData(0x20)] // Space
    [InlineData(0x11)] // Ctrl
    [InlineData(0x12)] // Alt
    public void Non_typing_keys_are_ignored(uint vk) => Assert.False(KeystrokeBuffer.IsTypingKey(vk));

    [Fact]
    public void Append_then_reset_clears_the_word()
    {
        var b = new KeystrokeBuffer();
        Assert.True(b.IsEmpty);

        b.Append(new TypedKey(0x41, 0x1E, Shift: false, Caps: false));
        b.Append(new TypedKey(0x42, 0x30, Shift: true, Caps: false));
        Assert.Equal(2, b.CurrentWord.Count);
        Assert.True(b.CurrentWord[1].Shift);

        b.Reset();
        Assert.True(b.IsEmpty);
    }

    [Fact]
    public void Backspace_removes_only_the_last_captured_key()
    {
        var b = new KeystrokeBuffer();
        b.Append(new TypedKey(0x41, 0x1E, Shift: false, Caps: false));
        b.Append(new TypedKey(0x42, 0x30, Shift: false, Caps: false));

        b.RemoveLast();
        Assert.Single(b.CurrentWord);
        Assert.Equal(0x41u, b.CurrentWord[0].VkCode);

        b.RemoveLast();
        b.RemoveLast();
        Assert.True(b.IsEmpty);
    }

    [Theory]
    [InlineData(0x10)] // Shift
    [InlineData(0x11)] // Ctrl
    [InlineData(0x12)] // Alt
    [InlineData(0x5B)] // Win
    public void Modifier_keys_keep_the_current_word(uint vk) =>
        Assert.True(KeystrokeBuffer.IsModifierKey(vk));
}
