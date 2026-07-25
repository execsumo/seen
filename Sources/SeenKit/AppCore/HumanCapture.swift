import Foundation

/// Capture policy for the person at the keyboard — the global hotkey and the
/// menu bar's Capture actions.
///
/// The app-wide default (`AppSettings.defaultMaxDimension`, 1568 px) exists to
/// fit Anthropic's vision cap: an agent pays tokens by image *dimensions*, so
/// shrinking to 1568 px is what makes a capture cheap to look at. None of that
/// applies to a human. Nobody bills your clipboard, and a hotkey capture is
/// usually going somewhere that wants detail — a paste into a chat, a bug
/// report, your own eyes on a 5K display.
///
/// So the human paths override the agent budget with a deliberately generous
/// 2K cap. It is a cap rather than "native resolution" so a multi-display
/// grab can't put a 100 MB PNG on the pasteboard.
///
/// OCR is unaffected either way: it always runs on the full-resolution frame
/// before any downscale, so text fidelity never depended on this number.
public enum HumanCapture {
    /// Longest-edge cap, in pixels, for human-triggered captures.
    public static let maxDimension = 2048

    /// Builds the request the hotkey and menu use.
    ///
    /// `format` is left nil so human captures follow the same PNG default as
    /// everything else — lossless matters more here than for agents, since a
    /// person may zoom into what they captured.
    public static func request(
        target: CaptureRequest.Target? = nil,
        output: CaptureRequest.Output
    ) -> CaptureRequest {
        var request = CaptureRequest()
        if let target { request.target = target }
        request.output = output
        request.maxDimension = maxDimension
        return request
    }
}
