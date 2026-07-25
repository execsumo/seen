import Foundation
@testable import SeenKit

let shellTests: [TestCase] = [
    TestCase("PushTemplate rendering") {
        let paths = ["/tmp/file 1.png", "/tmp/file'2.png"]
        let text = "Hello 'world'"
        
        let pathRender = PushTemplate.render("cmd {path}", paths: paths, text: text)
        try expectEqual(pathRender, "cmd '/tmp/file 1.png'")
        
        let pathsRender = PushTemplate.render("cmd {paths}", paths: paths, text: text)
        try expectEqual(pathsRender, "cmd '/tmp/file 1.png' '/tmp/file'\\''2.png'")
        
        let textRender = PushTemplate.render("cmd {text}", paths: paths, text: text)
        try expectEqual(textRender, "cmd 'Hello '\\''world'\\'''")
        
        let unknown = PushTemplate.render("cmd {unknown}", paths: paths, text: text)
        try expectEqual(unknown, "cmd {unknown}")
    },
    
    TestCase("PushPipeline mock runner") {
        actor MockProcessRunner: ProcessRunning {
            var calls: [(String, [String])] = []
            func run(_ executable: String, _ arguments: [String]) async throws -> Int32 {
                calls.append((executable, arguments))
                return 0
            }
        }
        
        let runner = MockProcessRunner()
        let pipeline = PushPipeline(processRunner: runner)
        let result = CaptureResult(items: [
            .init(path: "/a", sourceLabel: "s", width: 1, height: 1, byteSize: 1, text: "t")
        ], timestamp: Date())
        
        try await pipeline.push(result, to: .commandTemplate("cmd {path} {text}"))
        let calls1 = await runner.calls
        try expectEqual(calls1.count, 1)
        try expectEqual(calls1[0].0, "/bin/zsh")
        try expectEqual(calls1[0].1, ["-lc", "cmd '/a' 't'"])
        
        try await pipeline.push(result, to: .tmuxPane(pane: "1.1", template: "cmd {path}"))
        let calls2 = await runner.calls
        try expectEqual(calls2.count, 2)
        try expectEqual(calls2[1].0, "/usr/bin/env")
        try expectEqual(calls2[1].1, ["tmux", "send-keys", "-t", "1.1", "cmd '/a'", "Enter"])
    },
    
    TestCase("Icon state function") {
        let now = Date()
        try expectEqual(iconState(lastCapture: nil, activeSessions: 0, now: now), .idle)
        
        try expectEqual(iconState(lastCapture: now.addingTimeInterval(-1), activeSessions: 0, now: now), .recentCapture)
        try expectEqual(iconState(lastCapture: now.addingTimeInterval(-4), activeSessions: 0, now: now), .idle)
        
        try expectEqual(iconState(lastCapture: nil, activeSessions: 1, now: now), .sessionActive)
        try expectEqual(iconState(lastCapture: now.addingTimeInterval(-1), activeSessions: 1, now: now), .sessionActive)
    },
    
    TestCase("AppSettings: image encoding is built-in, not persisted") {
        let defaults = UserDefaults(suiteName: "TestSuite")!
        defaults.removePersistentDomain(forName: "TestSuite")

        Task { @MainActor in
            let settings = AppSettings(defaults: defaults)

            // Persisted settings default correctly when empty.
            try expectEqual(settings.hotkeyCode, 1)
            try expectEqual(settings.hotkeyModifiers, 4352)

            // Encoding is the built-in default: PNG at 1568 px.
            try expectEqual(settings.defaultQuality, 0.75)
            try expectEqual(settings.defaultMaxDimension, 1568)
            try expectEqual(settings.defaultFormat, .png)

            // A stale value an older build's UI persisted must NOT resurrect —
            // encoding is baked into the app now, not user-configurable.
            defaults.set(0.5, forKey: "defaultQuality")
            defaults.set(1000, forKey: "defaultMaxDimension")
            defaults.set("jpeg", forKey: "defaultFormat")

            let settings2 = AppSettings(defaults: defaults)
            try expectEqual(settings2.defaultQuality, 0.75)
            try expectEqual(settings2.defaultMaxDimension, 1568)
            try expectEqual(settings2.defaultFormat, .png)

            let config = settings2.captureConfiguration
            try expectEqual(config.defaultQuality, 0.75)
            try expectEqual(config.defaultMaxDimension, 1568)
        }
    },

    TestCase("HumanCapture: hotkey/menu captures override the agent token budget") {
        // The person at the keyboard is not paying tokens by image dimension,
        // so human-triggered captures get 2K rather than the 1568 px agent cap.
        let req = HumanCapture.request(output: .both)
        try expectEqual(req.maxDimension, 2048)
        try expectEqual(req.maxDimension != nil, true)
        try expectEqual(req.output, .both)
        // Format stays nil so human captures still follow the PNG default.
        try expectEqual(req.format == nil, true)

        // The 2K cap must actually be larger than the agent default, or this
        // whole policy is a no-op.
        try expect(HumanCapture.maxDimension > 1568)
    },

    TestCase("HumanCapture: target and output pass through") {
        let targeted = HumanCapture.request(target: .app("Chrome"), output: .text)
        try expectEqual(targeted.target, .app("Chrome"))
        try expectEqual(targeted.output, .text)
        try expectEqual(targeted.maxDimension, 2048)

        // No target means all displays, matching CaptureRequest's own default.
        let untargeted = HumanCapture.request(output: .image)
        try expectEqual(untargeted.target, .allDisplays)
    }
]
