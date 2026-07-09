import Foundation
import Carbon
import AppKit
import SeenKit

@MainActor
public final class HotkeyManager {
    private var hotkeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    
    private let coordinator: any CaptureCoordinating
    private let settings: AppSettings
    private let pipeline: PushPipeline
    
    public init(coordinator: any CaptureCoordinating, settings: AppSettings, pipeline: PushPipeline) {
        self.coordinator = coordinator
        self.settings = settings
        self.pipeline = pipeline
    }
    
    public func register() {
        unregister()
        
        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = OSType(0x5345454E) // 'SEEN'
        hotKeyID.id = 1
        
        var eventType = EventTypeSpec()
        eventType.eventClass = OSType(kEventClassKeyboard)
        eventType.eventKind = OSType(kEventHotKeyPressed)
        
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        
        InstallEventHandler(GetApplicationEventTarget(), { nextHandler, theEvent, userData in
            let manager = Unmanaged<HotkeyManager>.fromOpaque(userData!).takeUnretainedValue()
            manager.hotkeyPressed()
            return noErr
        }, 1, &eventType, selfPtr, &eventHandlerRef)
        
        let keyCode = UInt32(settings.hotkeyCode)
        let modifiers = UInt32(settings.hotkeyModifiers)
        
        RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotkeyRef)
    }
    
    public func unregister() {
        if let ref = hotkeyRef {
            UnregisterEventHotKey(ref)
            hotkeyRef = nil
        }
        if let ref = eventHandlerRef {
            RemoveEventHandler(ref)
            eventHandlerRef = nil
        }
    }
    
    private func hotkeyPressed() {
        Task {
            do {
                var request = CaptureRequest()
                request.output = settings.captureOutput
                let result = try await coordinator.perform(request)
                // Hotkey delivers to the clipboard only: it spawns nothing under
                // Seen, so a capture never drags a child process's TCC prompts
                // onto the app. Agents pick their own output via the API/MCP/CLI.
                try await pipeline.push(result, to: .clipboard)
            } catch {
                print("Hotkey capture failed: \(error)")
            }
        }
    }
}
