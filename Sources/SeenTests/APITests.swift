import Foundation
@testable import SeenKit

final actor MockCapturer: ScreenCapturing {
    var hasPermission = true
    
    func displays() async throws -> [DisplayInfo] {
        return [DisplayInfo(id: 1, width: 800, height: 600, name: "Mock Display")]
    }
    
    func applications() async throws -> [AppWindowInfo] {
        return [AppWindowInfo(id: 1, appName: "Mock App", bundleID: nil, title: nil)]
    }
    
    func capture(_ target: CaptureRequest.Target) async throws -> [CapturedFrame] {
        if !hasPermission { throw SeenError.permissionRequired("screen recording") }
        return []
    }
    
    func hasScreenRecordingPermission() async -> Bool { return hasPermission }
}

final actor MockCoordinator: CaptureCoordinating {
    var nextError: Error?
    
    func perform(_ request: CaptureRequest) async throws -> CaptureResult {
        if let err = nextError { throw err }
        return CaptureResult(items: [], timestamp: Date())
    }
    
    func observeEvents(_ handler: @escaping @Sendable (CaptureEvent) -> Void) async {}
    func setNextError(_ err: Error?) { nextError = err }
}

final actor MockSessionManager: SessionManaging {
    var active: [SessionInfo] = []
    
    func start(_ request: SessionRequest) async throws -> SessionInfo {
        let info = SessionInfo(id: UUID(), request: request, startedAt: Date(), endsAt: Date().addingTimeInterval(request.duration), captureCount: 0)
        active.append(info)
        return info
    }
    
    func stop(id: UUID) async throws {
        if !active.contains(where: { $0.id == id }) {
            throw SeenError.sessionNotFound(id)
        }
        active.removeAll { $0.id == id }
    }
    
    func activeSessions() async -> [SessionInfo] { return active }
}

final actor MockAPIClient: SeenAPIClient {
    func health() async throws -> String { return "{}" }
    func config() async throws -> String { return "{}" }
    func displays() async throws -> String { return "{}" }
    func apps() async throws -> String { return "{}" }
    func capture(_ request: CaptureRequest) async throws -> CaptureResult {
        return CaptureResult(items: [CaptureResult.Item(path: "/tmp/mock.jpg", sourceLabel: "mock", width: 100, height: 100, byteSize: 100, text: "mock text")], timestamp: Date())
    }
    func startSession(_ request: SessionRequest) async throws -> SessionInfo {
        return SessionInfo(id: UUID(), request: request, startedAt: Date(), endsAt: Date(), captureCount: 0)
    }
    func listSessions() async throws -> String { return "{}" }
    func stopSession(id: UUID) async throws {}
}

let apiTests: [TestCase] = [
    TestCase("HTTPMessage codec - parse request", {
        var parser = HTTPParser()
        let reqData = "POST /capture HTTP/1.1\r\nContent-Length: 16\r\n\r\n{\"target\":\"all\"}".data(using: .utf8)!
        parser.append(reqData)
        let parsed = try parser.parse()
        try expect(parsed != nil)
        try expectEqual(parsed?.method, "POST")
        try expectEqual(parsed?.path, "/capture")
        try expectEqual(parsed?.body, "{\"target\":\"all\"}".data(using: .utf8)!)
    }),
    
    TestCase("HTTPMessage codec - serialize response", {
        let resp = HTTPResponse(status: 200, json: ["status": "ok"])
        let data = resp.serialize()
        let str = String(data: data, encoding: .utf8)!
        try expect(str.hasPrefix("HTTP/1.1 200 OK\r\n"))
        try expect(str.contains("Content-Length: 15"))
        try expect(str.contains("Connection: close"))
        try expect(str.hasSuffix("\r\n{\"status\":\"ok\"}"))
    }),
    
    TestCase("APIRouter - happy path", {
        let coordinator = MockCoordinator()
        let sessions = MockSessionManager()
        let capturer = MockCapturer()
        let router = APIRouter(coordinator: coordinator, sessions: sessions, capturer: capturer, configurationProvider: { CaptureConfiguration() })
        
        let req = HTTPRequest(method: "GET", path: "/health")
        let res = await router.handle(req)
        try expectEqual(res.status, 200)
    }),
    
    TestCase("APIRouter - error mapping", {
        let coordinator = MockCoordinator()
        await coordinator.setNextError(SeenError.permissionRequired("screen recording"))
        let sessions = MockSessionManager()
        let capturer = MockCapturer()
        let router = APIRouter(coordinator: coordinator, sessions: sessions, capturer: capturer, configurationProvider: { CaptureConfiguration() })
        
        let captureReq = HTTPRequest(method: "POST", path: "/capture", body: "{}".data(using: .utf8)!)
        let captureRes = await router.handle(captureReq)
        try expectEqual(captureRes.status, 403)
        
        let stopReq = HTTPRequest(method: "DELETE", path: "/sessions/\(UUID().uuidString)")
        let stopRes = await router.handle(stopReq)
        try expectEqual(stopRes.status, 404)
        
        let badReq = HTTPRequest(method: "POST", path: "/capture", body: "{invalid}".data(using: .utf8)!)
        let badRes = await router.handle(badReq)
        try expectEqual(badRes.status, 400)
    }),
    
    TestCase("SessionManager - capture loop and caps", {
        actor EventStore {
            var events: [CaptureEvent] = []
            func add(_ event: CaptureEvent) { events.append(event) }
            func get() -> [CaptureEvent] { return events }
        }
        let store = EventStore()
        
        let coordinator = MockCoordinator()
        let sessions = SessionManager(coordinator: coordinator, eventSink: { e in Task { await store.add(e) } }, sleep: { _ in })
        
        let req = SessionRequest(interval: 5, duration: 15) // ~4 captures
        let info = try await sessions.start(req)
        try expectEqual(info.request.interval, 5)
        
        try await Task.sleep(nanoseconds: 100_000_000) // allow loop to finish
        
        let active = await sessions.activeSessions()
        try expectEqual(active.count, 0)
        
        let events = await store.get()
        var completed = 0
        for event in events {
            if case .captureCompleted = event { completed += 1 }
        }
        try expect(completed > 0)
    }),
    
    TestCase("UDSHTTPServer - end to end", {
        let coordinator = MockCoordinator()
        let sessions = MockSessionManager()
        let capturer = MockCapturer()
        let router = APIRouter(coordinator: coordinator, sessions: sessions, capturer: capturer, configurationProvider: { CaptureConfiguration() })
        let server = UDSHTTPServer(router: router)
        
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let socketPath = tempDir.appendingPathComponent("seen.sock").path
        
        try await server.start(socketPath: socketPath)
        
        let client = UDSAPIClient(socketPath: socketPath)
        let health = try await client.health()
        try expect(health.contains("status"))
        
        let req = CaptureRequest()
        let res = try await client.capture(req)
        try expect(res.items.isEmpty)
        
        await server.stop()
        
        let attrs = try FileManager.default.attributesOfItem(atPath: socketPath)
        let posix = attrs[.posixPermissions] as? NSNumber
        try expectEqual(posix?.int16Value, 0o600)
    }),
    
    TestCase("MCPHandler - initialize and tools/list", {
        let client = MockAPIClient()
        let handler = MCPHandler(client: client)
        
        let initReq = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\"}".data(using: .utf8)!
        let initResData = await handler.handle(initReq)
        let initRes = String(data: initResData!, encoding: .utf8)!
        try expect(initRes.contains("2025-06-18"))
        
        let listReq = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/list\"}".data(using: .utf8)!
        let listResData = await handler.handle(listReq)
        let listRes = String(data: listResData!, encoding: .utf8)!
        try expect(listRes.contains("capture_screen"))
        try expect(listRes.contains("start_watch"))
    }),
    
    TestCase("MCPHandler - capture_screen", {
        let client = MockAPIClient()
        let handler = MCPHandler(client: client)
        
        let data = Data([0xFF, 0xD8, 0xFF, 0xD9])
        try data.write(to: URL(fileURLWithPath: "/tmp/mock.jpg"))
        
        let callReq = "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"tools/call\",\"params\":{\"name\":\"capture_screen\",\"arguments\":{}}}".data(using: .utf8)!
        let callResData = await handler.handle(callReq)
        let callRes = String(data: callResData!, encoding: .utf8)!
        try expect(callRes.contains("image\\/jpeg"))
        try expect(callRes.contains("mock text"))
    })
]
