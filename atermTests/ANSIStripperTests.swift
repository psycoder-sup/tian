import Testing
@testable import aterm

struct ANSIStripperTests {
    // MARK: - Plain text passthrough

    @Test func plainTextPassesThrough() {
        var stripper = ANSIStripper()
        #expect(stripper.strip("hello world") == "hello world")
    }

    @Test func emptyStringReturnsEmpty() {
        var stripper = ANSIStripper()
        #expect(stripper.strip("") == "")
    }

    @Test func preservesNewlinesAndTabs() {
        var stripper = ANSIStripper()
        #expect(stripper.strip("line1\nline2\ttab") == "line1\nline2\ttab")
    }

    @Test func preservesCarriageReturn() {
        var stripper = ANSIStripper()
        #expect(stripper.strip("hello\r\nworld") == "hello\r\nworld")
    }

    // MARK: - CSI sequences

    @Test func stripsSGRSequence() {
        var stripper = ANSIStripper()
        #expect(stripper.strip("\u{1B}[31mred text\u{1B}[0m") == "red text")
    }

    @Test func stripsMultipleSGRSequences() {
        var stripper = ANSIStripper()
        #expect(stripper.strip("\u{1B}[1m\u{1B}[38;5;31mbold blue\u{1B}[0m") == "bold blue")
    }

    @Test func stripsCursorMovement() {
        var stripper = ANSIStripper()
        #expect(stripper.strip("\u{1B}[2Aup\u{1B}[3Bdown") == "updown")
    }

    @Test func stripsClearScreen() {
        var stripper = ANSIStripper()
        #expect(stripper.strip("\u{1B}[2Jcleared") == "cleared")
    }

    @Test func stripsClearLine() {
        var stripper = ANSIStripper()
        #expect(stripper.strip("before\u{1B}[Kafter") == "beforeafter")
    }

    @Test func strips8BitCSI() {
        var stripper = ANSIStripper()
        #expect(stripper.strip("\u{9B}31mred\u{9B}0m") == "red")
    }

    // MARK: - OSC sequences

    @Test func stripsOSCWithBEL() {
        var stripper = ANSIStripper()
        #expect(stripper.strip("\u{1B}]0;window title\u{07}text") == "text")
    }

    @Test func stripsOSCWithST() {
        var stripper = ANSIStripper()
        #expect(stripper.strip("\u{1B}]2;title\u{1B}\\text") == "text")
    }

    @Test func stripsOSC7WorkingDirectory() {
        var stripper = ANSIStripper()
        let osc7 = "\u{1B}]7;file:///Users/test\u{1B}\\"
        #expect(stripper.strip(osc7 + "prompt") == "prompt")
    }

    // MARK: - Other escape sequences

    @Test func stripsCharsetSelect() {
        var stripper = ANSIStripper()
        #expect(stripper.strip("\u{1B}(Btext") == "text")
    }

    @Test func stripsSingleCharEscape() {
        var stripper = ANSIStripper()
        // ESC M = reverse index
        #expect(stripper.strip("\u{1B}Mtext") == "text")
    }

    @Test func stripsSaveCursorEscape() {
        var stripper = ANSIStripper()
        #expect(stripper.strip("\u{1B}7saved\u{1B}8restored") == "savedrestored")
    }

    // MARK: - Control characters

    @Test func stripsBEL() {
        var stripper = ANSIStripper()
        #expect(stripper.strip("hello\u{07}world") == "helloworld")
    }

    @Test func stripsOtherControlChars() {
        var stripper = ANSIStripper()
        // SO (0x0E) and SI (0x0F)
        #expect(stripper.strip("hello\u{0E}world\u{0F}end") == "helloworldend")
    }

    // MARK: - Stateful: sequences split across chunks

    @Test func handlesESCSplitAcrossChunks() {
        var stripper = ANSIStripper()
        let result1 = stripper.strip("text\u{1B}")
        let result2 = stripper.strip("[31mred")
        #expect(result1 == "text")
        #expect(result2 == "red")
    }

    @Test func handlesCSISplitAcrossChunks() {
        var stripper = ANSIStripper()
        let result1 = stripper.strip("\u{1B}[38;5")
        let result2 = stripper.strip(";31m colored")
        #expect(result1 == "")
        #expect(result2 == " colored")
    }

    @Test func handlesOSCSplitAcrossChunks() {
        var stripper = ANSIStripper()
        let result1 = stripper.strip("\u{1B}]0;window")
        let result2 = stripper.strip(" title\u{07}after")
        #expect(result1 == "")
        #expect(result2 == "after")
    }

    @Test func handlesOSCSTSplitAcrossChunks() {
        var stripper = ANSIStripper()
        let result1 = stripper.strip("\u{1B}]2;title\u{1B}")
        let result2 = stripper.strip("\\after")
        #expect(result1 == "")
        #expect(result2 == "after")
    }

    @Test func stateResetsProperlyBetweenSequences() {
        var stripper = ANSIStripper()
        let result = stripper.strip("\u{1B}[31mfirst\u{1B}[0m \u{1B}[32msecond\u{1B}[0m")
        #expect(result == "first second")
        #expect(stripper.state == .normal)
    }

    // MARK: - Edge cases

    @Test func unicodePassesThrough() {
        var stripper = ANSIStripper()
        #expect(stripper.strip("hello 🌍 世界") == "hello 🌍 世界")
    }

    @Test func realShellPrompt() {
        var stripper = ANSIStripper()
        let prompt = "\u{1B}[1m\u{1B}[7m%\u{1B}[27m\u{1B}[1m\u{1B}[0m"
        #expect(stripper.strip(prompt) == "%")
    }

    @Test func oscWithEscInsidePayloadDoesNotTerminateEarly() {
        var stripper = ANSIStripper()
        // ESC inside OSC that's NOT followed by backslash should stay in OSC
        let result = stripper.strip("\u{1B}]0;ti\u{1B}Xtle\u{07}after")
        #expect(result == "after")
    }

    // MARK: - DEC private mode sequences

    @Test func stripsDECPrivateMode() {
        var stripper = ANSIStripper()
        // Show cursor (?25h) and hide cursor (?25l)
        #expect(stripper.strip("\u{1B}[?25hvisible\u{1B}[?25l") == "visible")
    }

    @Test func stripsDECAlternateScreen() {
        var stripper = ANSIStripper()
        // Enter and exit alternate screen buffer
        #expect(stripper.strip("\u{1B}[?1049hcontent\u{1B}[?1049l") == "content")
    }

    // MARK: - Extended color sequences

    @Test func strips24BitColor() {
        var stripper = ANSIStripper()
        #expect(stripper.strip("\u{1B}[38;2;255;128;0mcolored\u{1B}[0m") == "colored")
    }

    @Test func strips256ColorBackground() {
        var stripper = ANSIStripper()
        #expect(stripper.strip("\u{1B}[48;5;196mred bg\u{1B}[0m") == "red bg")
    }

    // MARK: - Scroll region

    @Test func stripsScrollRegion() {
        var stripper = ANSIStripper()
        #expect(stripper.strip("\u{1B}[1;24rscrolled") == "scrolled")
    }

    // MARK: - Malformed sequences

    @Test func handlesMalformedCSIGracefully() {
        var stripper = ANSIStripper()
        // Incomplete CSI at end of input — should not crash, state stays in .csi
        let result = stripper.strip("text\u{1B}[38;5")
        #expect(result == "text")
        #expect(stripper.state == .csi)

        // Next chunk completes the sequence
        let result2 = stripper.strip(";1m more")
        #expect(result2 == " more")
        #expect(stripper.state == .normal)
    }

    @Test func handlesLoneEscapeAtEnd() {
        var stripper = ANSIStripper()
        let result = stripper.strip("text\u{1B}")
        #expect(result == "text")
        #expect(stripper.state == .escape)
    }

    // MARK: - OSC variants

    @Test func stripsOSC52Clipboard() {
        var stripper = ANSIStripper()
        // OSC 52 is used for clipboard operations
        #expect(stripper.strip("\u{1B}]52;c;SGVsbG8=\u{07}after") == "after")
    }

    @Test func stripsOSC133ShellIntegration() {
        var stripper = ANSIStripper()
        // OSC 133 is used by shells for prompt/command marking
        #expect(stripper.strip("\u{1B}]133;A\u{07}prompt$ \u{1B}]133;B\u{07}") == "prompt$ ")
    }
}
