import Foundation

public struct HTTPRequest: Sendable, Equatable {
    public var method: String
    public var path: String
    public var headers: [String: String]
    public var body: Data
    
    public init(method: String, path: String, headers: [String: String] = [:], body: Data = Data()) {
        self.method = method
        self.path = path
        self.headers = headers
        self.body = body
    }
}

public struct HTTPResponse: Sendable, Equatable {
    public var status: Int
    public var headers: [String: String]
    public var body: Data
    
    public init(status: Int, headers: [String: String] = [:], body: Data = Data()) {
        self.status = status
        self.headers = headers
        self.body = body
    }
    
    public init<T: Encodable>(status: Int, json: T) {
        self.status = status
        self.headers = ["Content-Type": "application/json"]
        self.body = (try? JSONCoding.encoder.encode(json)) ?? Data()
        self.headers["Content-Length"] = "\(self.body.count)"
    }
    
    public func serialize() -> Data {
        var data = Data()
        var statusText = "OK"
        switch status {
        case 200: statusText = "OK"
        case 201: statusText = "Created"
        case 204: statusText = "No Content"
        case 400: statusText = "Bad Request"
        case 403: statusText = "Forbidden"
        case 404: statusText = "Not Found"
        case 500: statusText = "Internal Server Error"
        default: statusText = "Unknown"
        }
        
        var headerLines = "HTTP/1.1 \(status) \(statusText)\r\n"
        var finalHeaders = headers
        if finalHeaders["Content-Length"] == nil && !body.isEmpty {
            finalHeaders["Content-Length"] = "\(body.count)"
        }
        finalHeaders["Connection"] = "close"
        
        for (key, value) in finalHeaders {
            headerLines += "\(key): \(value)\r\n"
        }
        headerLines += "\r\n"
        
        data.append(contentsOf: headerLines.utf8)
        data.append(body)
        return data
    }
}

public enum HTTPParserError: Error {
    case incomplete
    case invalidRequestLine
    case invalidHeader
}

public struct HTTPParser {
    public var buffer = Data()
    
    public init() {}
    
    public mutating func append(_ data: Data) {
        buffer.append(data)
    }
    
    public mutating func parse() throws -> HTTPRequest? {
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
        
        let requestLine = lines[0].components(separatedBy: " ")
        guard requestLine.count >= 2 else {
            throw HTTPParserError.invalidRequestLine
        }
        
        let method = requestLine[0]
        let path = requestLine[1]
        
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
            return nil // Need more body data
        }
        
        let bodyEndIndex = bodyStartIndex + bodyLength
        let body = buffer.subdata(in: bodyStartIndex..<bodyEndIndex)
        
        buffer.removeSubrange(buffer.startIndex..<bodyEndIndex)
        
        return HTTPRequest(method: method, path: path, headers: headers, body: body)
    }
}
