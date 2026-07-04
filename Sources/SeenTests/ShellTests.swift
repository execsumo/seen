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
    
    TestCase("AppSettings round-trip") {
        let defaults = UserDefaults(suiteName: "TestSuite")!
        defaults.removePersistentDomain(forName: "TestSuite")
        
        Task { @MainActor in
            let settings = AppSettings(defaults: defaults)
            
            // test defaults when empty
            try expectEqual(settings.hotkeyCode, 1)
            try expectEqual(settings.hotkeyModifiers, 4352)
            try expectEqual(settings.defaultQuality, 0.75)
            try expectEqual(settings.defaultMaxDimension, 1568)
            try expectEqual(settings.defaultFormat, .jpeg)
            
            // test round trip
            settings.defaultQuality = 0.5
            settings.defaultMaxDimension = 1000
            
            let settings2 = AppSettings(defaults: defaults)
            try expectEqual(settings2.defaultQuality, 0.5)
            try expectEqual(settings2.defaultMaxDimension, 1000)
            
            let config = settings.captureConfiguration
            try expectEqual(config.defaultQuality, 0.5)
            try expectEqual(config.defaultMaxDimension, 1000)
        }
    }
]
