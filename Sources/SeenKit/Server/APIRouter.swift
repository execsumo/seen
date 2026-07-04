import Foundation

public struct APIRouter: Sendable {
    public let coordinator: any CaptureCoordinating
    public let sessions: any SessionManaging
    public let capturer: any ScreenCapturing
    public let configurationProvider: @Sendable () -> CaptureConfiguration
    
    public init(
        coordinator: any CaptureCoordinating,
        sessions: any SessionManaging,
        capturer: any ScreenCapturing,
        configurationProvider: @escaping @Sendable () -> CaptureConfiguration
    ) {
        self.coordinator = coordinator
        self.sessions = sessions
        self.capturer = capturer
        self.configurationProvider = configurationProvider
    }
    
    public func handle(_ request: HTTPRequest) async -> HTTPResponse {
        do {
            switch (request.method, request.path) {
            case ("GET", "/health"):
                return await handleHealth()
            case ("GET", "/config"):
                return handleConfig()
            case ("GET", "/displays"):
                return try await handleDisplays()
            case ("GET", "/apps"):
                return try await handleApps()
            case ("POST", "/capture"):
                return try await handleCapture(request.body)
            case ("POST", "/sessions"):
                return try await handleStartSession(request.body)
            case ("GET", "/sessions"):
                return await handleListSessions()
            case ("DELETE", let path) where path.hasPrefix("/sessions/"):
                return try await handleStopSession(path: path)
            default:
                return HTTPResponse(status: 404, json: ErrorResponse(error: ErrorDetail(code: "not_found", message: "Path not found")))
            }
        } catch let error as SeenError {
            let status = statusCode(for: error)
            return HTTPResponse(status: status, json: ErrorResponse(error: ErrorDetail(code: error.code, message: error.message)))
        } catch {
            return HTTPResponse(status: 500, json: ErrorResponse(error: ErrorDetail(code: "internal", message: error.localizedDescription)))
        }
    }
    
    private func statusCode(for error: SeenError) -> Int {
        switch error {
        case .badRequest, .unsupportedFormat, .sessionLimitExceeded: return 400
        case .permissionRequired: return 403
        case .targetNotFound, .sessionNotFound: return 404
        case .captureFailed, .encodingFailed, .storageFailed: return 500
        }
    }
    
    private func handleHealth() async -> HTTPResponse {
        let hasPermission = await capturer.hasScreenRecordingPermission()
        let activeSessionsCount = await sessions.activeSessions().count
        let response = HealthResponse(
            status: "ok",
            version: Seen.version,
            screenRecordingPermission: hasPermission,
            activeSessions: activeSessionsCount
        )
        return HTTPResponse(status: 200, json: response)
    }
    
    private func handleConfig() -> HTTPResponse {
        let config = configurationProvider()
        return HTTPResponse(status: 200, json: config)
    }
    
    private func handleDisplays() async throws -> HTTPResponse {
        let displays = try await capturer.displays()
        return HTTPResponse(status: 200, json: DisplaysResponse(displays: displays))
    }
    
    private func handleApps() async throws -> HTTPResponse {
        let apps = try await capturer.applications()
        return HTTPResponse(status: 200, json: AppsResponse(apps: apps))
    }
    
    private func handleCapture(_ body: Data) async throws -> HTTPResponse {
        let req: CaptureRequest
        if body.isEmpty {
            req = CaptureRequest()
        } else {
            do {
                req = try JSONCoding.decoder.decode(CaptureRequest.self, from: body)
            } catch {
                throw SeenError.badRequest("Invalid JSON body")
            }
        }
        let result = try await coordinator.perform(req)
        return HTTPResponse(status: 200, json: result)
    }
    
    private func handleStartSession(_ body: Data) async throws -> HTTPResponse {
        let req: SessionRequest
        do {
            req = try JSONCoding.decoder.decode(SessionRequest.self, from: body)
        } catch {
            throw SeenError.badRequest("Invalid JSON body")
        }
        let sessionInfo = try await sessions.start(req)
        return HTTPResponse(status: 201, json: sessionInfo)
    }
    
    private func handleListSessions() async -> HTTPResponse {
        let list = await sessions.activeSessions()
        return HTTPResponse(status: 200, json: SessionsResponse(sessions: list))
    }
    
    private func handleStopSession(path: String) async throws -> HTTPResponse {
        let idString = path.dropFirst("/sessions/".count)
        guard let id = UUID(uuidString: String(idString)) else {
            throw SeenError.badRequest("Invalid UUID format")
        }
        try await sessions.stop(id: id)
        return HTTPResponse(status: 204)
    }
}

// MARK: - Payloads

private struct ErrorResponse: Encodable {
    var error: ErrorDetail
}

private struct ErrorDetail: Encodable {
    var code: String
    var message: String
}

private struct HealthResponse: Encodable {
    var status: String
    var version: String
    var screenRecordingPermission: Bool
    var activeSessions: Int
}

private struct DisplaysResponse: Encodable {
    var displays: [DisplayInfo]
}

private struct AppsResponse: Encodable {
    var apps: [AppWindowInfo]
}

private struct SessionsResponse: Encodable {
    var sessions: [SessionInfo]
}
