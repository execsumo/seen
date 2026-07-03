import Foundation
import AppKit

public struct PushPipeline: Sendable {
    public var processRunner: any ProcessRunning
    
    public init(processRunner: any ProcessRunning = DefaultProcessRunner()) {
        self.processRunner = processRunner
    }
    
    public func push(_ result: CaptureResult, to destination: PushDestination) async throws {
        let paths = result.items.map { $0.path }
        let text = result.combinedText
        
        switch destination {
        case .commandTemplate(let template):
            let rendered = PushTemplate.render(template, paths: paths, text: text)
            _ = try await processRunner.run("/bin/zsh", ["-lc", rendered])
            
        case .tmuxPane(let pane, let template):
            let rendered = PushTemplate.render(template, paths: paths, text: text)
            _ = try await processRunner.run("/usr/bin/env", ["tmux", "send-keys", "-t", pane, rendered, "Enter"])
            
        case .clipboard:
            await MainActor.run {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                
                var objects: [NSPasteboardWriting] = []
                for path in paths {
                    objects.append(NSURL(fileURLWithPath: path))
                }
                if !text.isEmpty {
                    objects.append(text as NSString)
                }
                pasteboard.writeObjects(objects)
            }
        }
    }
}
