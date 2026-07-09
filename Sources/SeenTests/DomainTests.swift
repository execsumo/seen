import Foundation
import SeenKit

let domainTests: [TestCase] = [
    TestCase("file naming: timestamp format matches convention") {
        let date = Date(timeIntervalSince1970: 1_782_136_222) // 2026-06-22 13:50:22 UTC
        let name = CaptureFileNaming.filename(
            timestamp: date,
            sourceLabel: "display-1",
            format: .jpeg,
            timeZone: TimeZone(identifier: "UTC")!
        )
        try expectEqual(name, "capture_2026-06-22_13-50-22_display-1.jpg")
    },

    TestCase("file naming: no label omits the suffix") {
        let date = Date(timeIntervalSince1970: 0)
        let name = CaptureFileNaming.filename(
            timestamp: date, sourceLabel: nil, format: .png,
            timeZone: TimeZone(identifier: "UTC")!
        )
        try expectEqual(name, "capture_1970-01-01_00-00-00.png")
    },

    TestCase("file naming: labels are sanitized") {
        try expectEqual(CaptureFileNaming.sanitize("Google Chrome"), "google-chrome")
        try expectEqual(CaptureFileNaming.sanitize("  Micro$oft -- Teams!  "), "micro-oft-teams")
        try expectEqual(CaptureFileNaming.sanitize("---"), "")
    },

    TestCase("capture request: target JSON round-trips all shapes") {
        let targets: [CaptureRequest.Target] = [
            .allDisplays, .display(1), .app("Google Chrome"), .window(4242),
        ]
        for target in targets {
            let data = try JSONEncoder().encode(CaptureRequest(target: target))
            let decoded = try JSONDecoder().decode(CaptureRequest.self, from: data)
            try expectEqual(decoded.target, target)
        }
    },

    TestCase("capture request: empty JSON object yields defaults") {
        let decoded = try JSONDecoder().decode(CaptureRequest.self, from: Data("{}".utf8))
        try expectEqual(decoded, CaptureRequest())
        try expectEqual(decoded.target, .allDisplays)
        try expectEqual(decoded.output, .both)
    },

    TestCase("capture request: agent-style JSON parses") {
        let json = #"{"target":{"app":"Teams"},"output":"text","maxDimension":1024}"#
        let decoded = try JSONDecoder().decode(CaptureRequest.self, from: Data(json.utf8))
        try expectEqual(decoded.target, .app("Teams"))
        try expectEqual(decoded.output, .text)
        try expectEqual(decoded.maxDimension, 1024)
    },

    TestCase("session limits: valid request passes") {
        try SessionLimits.validate(SessionRequest(interval: 10, duration: 300))
    },

    TestCase("session limits: rejects fast intervals, long durations, too many captures") {
        for request in [
            SessionRequest(interval: 1, duration: 60),          // interval below minimum
            SessionRequest(interval: 10, duration: 31 * 60),    // duration above maximum
            SessionRequest(interval: 5, duration: 30 * 60),     // 361 captures > 200 cap
            SessionRequest(interval: 10, duration: 0),          // non-positive duration
        ] {
            let error = try await expectThrows { try SessionLimits.validate(request) }
            try expect(error is SeenError, "expected SeenError, got \(error)")
        }
    },

    TestCase("errors: codes are stable API identifiers") {
        try expectEqual(SeenError.permissionRequired("screen-recording").code, "permission_required")
        try expectEqual(SeenError.sessionLimitExceeded("x").code, "session_limit_exceeded")
        try expectEqual(SeenError.targetNotFound("x").code, "target_not_found")
    },

    TestCase("configuration: per-request overrides beat defaults") {
        let config = CaptureConfiguration()
        let request = CaptureRequest(format: .png, quality: 0.5, maxDimension: 800)
        let options = config.encodingOptions(for: request)
        try expectEqual(options, EncodingOptions(format: .png, quality: 0.5, maxDimension: 800))

        let defaults = config.encodingOptions(for: CaptureRequest())
        try expectEqual(defaults, EncodingOptions(format: .png, quality: 0.75, maxDimension: 1568))
    },

    TestCase("result: combinedText labels sources only when multiple") {
        let item1 = CaptureResult.Item(path: "/a.jpg", sourceLabel: "display-1", width: 1, height: 1, byteSize: 1, text: "hello")
        let item2 = CaptureResult.Item(path: "/b.jpg", sourceLabel: "display-2", width: 1, height: 1, byteSize: 1, text: "")
        let single = CaptureResult(items: [item1], timestamp: .now)
        try expectEqual(single.combinedText, "hello")
        let multi = CaptureResult(items: [item1, item2], timestamp: .now)
        try expectEqual(multi.combinedText, "[display-1]\nhello")
    },
]
