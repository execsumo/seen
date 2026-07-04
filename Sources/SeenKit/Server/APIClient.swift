import Foundation
import Network

public protocol SeenAPIClient: Sendable {
    func health() async throws -> String
    func config() async throws -> String
    func displays() async throws -> String
    func apps() async throws -> String
    func capture(_ request: CaptureRequest) async throws -> CaptureResult
    func startSession(_ request: SessionRequest) async throws -> SessionInfo
    func listSessions() async throws -> String
    func stopSession(id: UUID) async throws
}

public struct UDSAPIClient: SeenAPIClient {
    public let socketPath: String
    
    public init(socketPath: String = SeenPaths.socketPath) {
        self.socketPath = socketPath
    }
    
    public func health() async throws -> String {
        let (status, body) = try await sendRequest(method: "GET", path: "/health", body: nil)
        try checkStatus(status, body: body)
        return String(data: body, encoding: .utf8) ?? ""
    }
    
    public func config() async throws -> String {
        let (status, body) = try await sendRequest(method: "GET", path: "/config", body: nil)
        try checkStatus(status, body: body)
        return String(data: body, encoding: .utf8) ?? ""
    }
    
    public func displays() async throws -> String {
        let (status, body) = try await sendRequest(method: "GET", path: "/displays", body: nil)
        try checkStatus(status, body: body)
        return String(data: body, encoding: .utf8) ?? ""
    }
    
    public func apps() async throws -> String {
        let (status, body) = try await sendRequest(method: "GET", path: "/apps", body: nil)
        try checkStatus(status, body: body)
        return String(data: body, encoding: .utf8) ?? ""
    }
    
    public func capture(_ request: CaptureRequest) async throws -> CaptureResult {
        let data = try JSONCoding.encoder.encode(request)
        let (status, body) = try await sendRequest(method: "POST", path: "/capture", body: data)
        try checkStatus(status, body: body)
        return try JSONCoding.decoder.decode(CaptureResult.self, from: body)
    }
    
    public func startSession(_ request: SessionRequest) async throws -> SessionInfo {
        let data = try JSONCoding.encoder.encode(request)
        let (status, body) = try await sendRequest(method: "POST", path: "/sessions", body: data)
        try checkStatus(status, body: body)
        return try JSONCoding.decoder.decode(SessionInfo.self, from: body)
    }
    
    public func listSessions() async throws -> String {
        let (status, body) = try await sendRequest(method: "GET", path: "/sessions", body: nil)
        try checkStatus(status, body: body)
        return String(data: body, encoding: .utf8) ?? ""
    }
    
    public func stopSession(id: UUID) async throws {
        let (status, body) = try await sendRequest(method: "DELETE", path: "/sessions/\(id.uuidString)", body: nil)
        try checkStatus(status, body: body)
    }
    
    private func checkStatus(_ status: Int, body: Data) throws {
        if status >= 200 && status < 300 { return }
        
        struct ErrorWrapper: Decodable {
            struct ErrorBody: Decodable {
                var code: String
                var message: String
            }
            var error: ErrorBody
        }
        
        if let err = try? JSONCoding.decoder.decode(ErrorWrapper.self, from: body) {
            let code = err.error.code
            let message = err.error.message
            switch code {
            case "permission_required": throw SeenError.permissionRequired(message)
            case "target_not_found": throw SeenError.targetNotFound(message)
            case "bad_request": throw SeenError.badRequest(message)
            case "session_limit_exceeded": throw SeenError.sessionLimitExceeded(message)
            case "session_not_found": throw SeenError.sessionNotFound(UUID()) // Dummy UUID, real one in message
            case "unsupported_format": throw SeenError.unsupportedFormat(message)
            case "capture_failed": throw SeenError.captureFailed(message)
            case "encoding_failed": throw SeenError.encodingFailed(message)
            case "storage_failed": throw SeenError.storageFailed(message)
            default: throw SeenError.badRequest(message)
            }
        }
        throw SeenError.badRequest("HTTP \(status)")
    }
    
    private func sendRequest(method: String, path: String, body: Data?) async throws -> (Int, Data) {
        let endpoint = NWEndpoint.unix(path: socketPath)
        let connection = NWConnection(to: endpoint, using: .tcp)
        
        return try await withCheckedThrowingContinuation { continuation in
            let state = RequestState(continuation: continuation, connection: connection)
            
            connection.stateUpdateHandler = { [state] nwState in
                switch nwState {
                case .ready:
                    var req = HTTPRequest(method: method, path: path)
                    req.headers["Host"] = "seen"
                    if let body = body {
                        req.body = body
                        req.headers["Content-Length"] = "\(body.count)"
                    }
                    let reqData = HTTPResponse(status: 200).serializeRequest(req)
                    
                    state.receiveNext()
                    
                    connection.send(content: reqData, completion: .contentProcessed { [state] error in
                        if let error = error {
                            state.resume(with: .failure(error))
                            return
                        }
                    })
                case .failed(let error):
                    state.resume(with: .failure(error))
                case .cancelled:
                    state.resume(with: .failure(SeenError.badRequest("Connection cancelled")))
                default:
                    break
                }
            }
            connection.start(queue: DispatchQueue(label: "seen.client"))
        }
    }
}

private final class RequestState: @unchecked Sendable {
    private var continuation: CheckedContinuation<(Int, Data), Error>?
    private let connection: NWConnection
    private let lock = NSLock()
    private var receivedData = Data()
    
    init(continuation: CheckedContinuation<(Int, Data), Error>, connection: NWConnection) {
        self.continuation = continuation
        self.connection = connection
    }
    
    func resume(with result: Result<(Int, Data), Error>) {
        lock.lock()
        let cont = continuation
        continuation = nil
        lock.unlock()
        
        if let cont = cont {
            cont.resume(with: result)
            connection.cancel()
        }
    }
    
    func receiveNext() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            if let error = error {
                self.resume(with: .failure(error))
                return
            }
            
            self.lock.lock()
            if let data = data {
                self.receivedData.append(data)
            }
            var parser = HTTPResponseParser()
            parser.append(self.receivedData)
            let result = try? parser.parse()
            self.lock.unlock()
            
            if let resp = result {
                self.resume(with: .success((resp.status, resp.body)))
            } else if isComplete {
                self.resume(with: .failure(SeenError.badRequest("Incomplete HTTP response")))
            } else {
                self.receiveNext()
            }
        }
    }
}

extension HTTPResponse {
    func serializeRequest(_ request: HTTPRequest) -> Data {
        var data = Data()
        var headerLines = "\(request.method) \(request.path) HTTP/1.1\r\n"
        var finalHeaders = request.headers
        finalHeaders["Connection"] = "close"
        
        for (key, value) in finalHeaders {
            headerLines += "\(key): \(value)\r\n"
        }
        headerLines += "\r\n"
        
        data.append(contentsOf: headerLines.utf8)
        data.append(request.body)
        return data
    }
}

struct HTTPResponseParser {
    var buffer = Data()
    
    mutating func append(_ data: Data) {
        buffer.append(data)
    }
    
    mutating func parse() throws -> (status: Int, body: Data)? {
        guard let headerEndRange = buffer.range(of: Data("\r\n\r\n".utf8)) else {
            return nil
        }
        
        let headerData = buffer.subdata(in: buffer.startIndex..<headerEndRange.lowerBound)
        guard let headerString = String(data: headerData, encoding: .utf8) else {
            throw HTTPParserError.invalidRequestLine
        }
        
        let lines = headerString.components(separatedBy: "\r\n")
        guard !lines.isEmpty else {
            throw HTTPParserError.invalidRequestLine
        }
        
        let statusLine = lines[0].components(separatedBy: " ")
        guard statusLine.count >= 2, let status = Int(statusLine[1]) else {
            throw HTTPParserError.invalidRequestLine
        }
        
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard !line.isEmpty else { continue }
            let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: true)
            if parts.count == 2 {
                headers[String(parts[0]).trimmingCharacters(in: .whitespaces).lowercased()] = String(parts[1]).trimmingCharacters(in: .whitespaces)
            }
        }
        
        var bodyLength = 0
        if let contentLengthStr = headers["content-length"], let contentLength = Int(contentLengthStr) {
            bodyLength = contentLength
        }
        
        let bodyStartIndex = headerEndRange.upperBound
        if buffer.count - bodyStartIndex < bodyLength {
            return nil
        }
        
        let bodyEndIndex = bodyStartIndex + bodyLength
        let body = buffer.subdata(in: bodyStartIndex..<bodyEndIndex)
        
        buffer.removeSubrange(buffer.startIndex..<bodyEndIndex)
        return (status: status, body: body)
    }
}
