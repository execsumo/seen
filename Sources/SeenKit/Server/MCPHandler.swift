import Foundation

public struct MCPHandler {
    public let client: any SeenAPIClient
    
    public init(client: any SeenAPIClient) {
        self.client = client
    }
    
    public func handle(_ message: Data) async -> Data? {
        guard let requestString = String(data: message, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !requestString.isEmpty,
              let requestData = requestString.data(using: .utf8) else {
            return nil
        }
        
        do {
            guard let dict = try JSONSerialization.jsonObject(with: requestData) as? [String: Any],
                  let id = dict["id"] else {
                return nil // Notification or invalid
            }
            
            let method = dict["method"] as? String ?? ""
            
            if method == "initialize" {
                let result: [String: Any] = [
                    "protocolVersion": "2025-06-18",
                    "capabilities": ["tools": [String: Any]()],
                    "serverInfo": ["name": "seen", "version": Seen.version]
                ]
                return encodeResponse(id: id, result: result)
            } else if method == "ping" {
                return encodeResponse(id: id, result: [:])
            } else if method == "tools/list" {
                let tools: [[String: Any]] = [
                    [
                        "name": "capture_screen",
                        "description": "Capture the screen",
                        "inputSchema": [
                            "type": "object",
                            "properties": [
                                "target": ["type": "string"],
                                "output": ["type": "string"],
                                "max_dimension": ["type": "integer"]
                            ]
                        ]
                    ],
                    [
                        "name": "list_targets",
                        "description": "List capturable targets",
                        "inputSchema": ["type": "object", "properties": [String: Any]()]
                    ],
                    [
                        "name": "start_watch",
                        "description": "Start interval capture",
                        "inputSchema": [
                            "type": "object",
                            "properties": [
                                "interval_seconds": ["type": "number"],
                                "duration_seconds": ["type": "number"],
                                "target": ["type": "string"]
                            ],
                            "required": ["interval_seconds", "duration_seconds"]
                        ]
                    ],
                    [
                        "name": "stop_watch",
                        "description": "Stop interval capture",
                        "inputSchema": [
                            "type": "object",
                            "properties": [
                                "session_id": ["type": "string"]
                            ],
                            "required": ["session_id"]
                        ]
                    ],
                    [
                        "name": "watch_status",
                        "description": "List active sessions",
                        "inputSchema": ["type": "object", "properties": [String: Any]()]
                    ]
                ]
                return encodeResponse(id: id, result: ["tools": tools])
            } else if method == "tools/call" {
                let params = dict["params"] as? [String: Any] ?? [:]
                let name = params["name"] as? String ?? ""
                let args = params["arguments"] as? [String: Any] ?? [:]
                
                do {
                    let toolResult = try await callTool(name: name, arguments: args)
                    return encodeResponse(id: id, result: toolResult)
                } catch {
                    return encodeResponse(id: id, result: ["isError": true, "content": [["type": "text", "text": error.localizedDescription]]])
                }
            } else {
                return encodeError(id: id, code: -32601, message: "Method not found")
            }
        } catch {
            return nil
        }
    }
    
    private func callTool(name: String, arguments: [String: Any]) async throws -> [String: Any] {
        switch name {
        case "capture_screen":
            var req = CaptureRequest()
            if let targetStr = arguments["target"] as? String {
                req.target = parseTarget(targetStr)
            }
            if let outStr = arguments["output"] as? String, let out = CaptureRequest.Output(rawValue: outStr) {
                req.output = out
            }
            if let maxDim = arguments["max_dimension"] as? Int {
                req.maxDimension = maxDim
            }
            let res = try await client.capture(req)
            var content: [[String: Any]] = []
            
            var texts: [String] = []
            
            for item in res.items {
                if req.output.includesImage {
                    if let imgData = try? Data(contentsOf: URL(fileURLWithPath: item.path)) {
                        let b64 = imgData.base64EncodedString()
                        let ext = URL(fileURLWithPath: item.path).pathExtension.lowercased()
                        var mime = "image/jpeg"
                        if ext == "png" { mime = "image/png" }
                        else if ext == "heic" { mime = "image/heic" }
                        else if ext == "webp" { mime = "image/webp" }
                        
                        content.append([
                            "type": "image",
                            "data": b64,
                            "mimeType": mime
                        ])
                    }
                }
                var t = "Path: \(item.path)"
                if let ocr = item.text, !ocr.isEmpty {
                    t += "\nText: \(ocr)"
                }
                texts.append(t)
            }
            content.append(["type": "text", "text": texts.joined(separator: "\n\n")])
            return ["content": content]
            
        case "list_targets":
            let d = try await client.displays()
            let a = try await client.apps()
            return ["content": [["type": "text", "text": "Displays:\n\(d)\n\nApps:\n\(a)"]]]
            
        case "start_watch":
            guard let interval = arguments["interval_seconds"] as? Double,
                  let duration = arguments["duration_seconds"] as? Double else {
                throw SeenError.badRequest("Missing interval_seconds or duration_seconds")
            }
            var req = CaptureRequest()
            if let targetStr = arguments["target"] as? String {
                req.target = parseTarget(targetStr)
            }
            let sreq = SessionRequest(interval: interval, duration: duration, capture: req)
            let res = try await client.startSession(sreq)
            if let data = try? JSONCoding.encoder.encode(res), let str = String(data: data, encoding: .utf8) {
                return ["content": [["type": "text", "text": str]]]
            }
            return ["content": [["type": "text", "text": "Started session \(res.id)"]]]
            
        case "stop_watch":
            guard let idStr = arguments["session_id"] as? String, let id = UUID(uuidString: idStr) else {
                throw SeenError.badRequest("Invalid session_id")
            }
            try await client.stopSession(id: id)
            return ["content": [["type": "text", "text": "Stopped session \(idStr)"]]]
            
        case "watch_status":
            let res = try await client.listSessions()
            return ["content": [["type": "text", "text": res]]]
            
        default:
            throw SeenError.badRequest("Unknown tool \(name)")
        }
    }
    
    private func parseTarget(_ s: String) -> CaptureRequest.Target {
        if s.hasPrefix("display:") {
            let idStr = s.dropFirst("display:".count)
            if let id = UInt32(idStr) { return .display(id) }
        } else if s.hasPrefix("app:") {
            let name = String(s.dropFirst("app:".count))
            return .app(name)
        } else if s.hasPrefix("window:") {
            let idStr = s.dropFirst("window:".count)
            if let id = UInt32(idStr) { return .window(id) }
        }
        return .allDisplays
    }
    
    private func encodeResponse(id: Any, result: [String: Any]) -> Data {
        let resp: [String: Any] = ["jsonrpc": "2.0", "id": id, "result": result]
        return (try? JSONSerialization.data(withJSONObject: resp)) ?? Data()
    }
    
    private func encodeError(id: Any, code: Int, message: String) -> Data {
        let resp: [String: Any] = ["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]]
        return (try? JSONSerialization.data(withJSONObject: resp)) ?? Data()
    }
}
