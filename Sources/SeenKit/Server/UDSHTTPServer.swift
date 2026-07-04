import Foundation
import Network

public actor UDSHTTPServer {
    private var listener: NWListener?
    private let router: APIRouter
    
    public init(router: APIRouter) {
        self.router = router
    }
    
    public func start(socketPath: String = SeenPaths.socketPath) async throws {
        stop()
        
        let url = URL(fileURLWithPath: socketPath)
        let directory = url.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
        }
        
        if FileManager.default.fileExists(atPath: socketPath) {
            try? FileManager.default.removeItem(atPath: socketPath)
        }
        
        let endpoint = NWEndpoint.unix(path: socketPath)
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = endpoint
        
        let nwListener = try NWListener(using: parameters)
        self.listener = nwListener
        
        nwListener.newConnectionHandler = { [weak self] (connection: NWConnection) in
            guard let self = self else { return }
            Task {
                await self.handleConnection(connection)
            }
        }
        
        final class StartState: @unchecked Sendable {
            var continuation: CheckedContinuation<Void, Error>?
            let lock = NSLock()
            
            init(_ continuation: CheckedContinuation<Void, Error>) {
                self.continuation = continuation
            }
            
            func resume() {
                lock.lock()
                let c = continuation
                continuation = nil
                lock.unlock()
                c?.resume()
            }
            
            func resume(throwing error: Error) {
                lock.lock()
                let c = continuation
                continuation = nil
                lock.unlock()
                c?.resume(throwing: error)
            }
        }
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let stateHelper = StartState(continuation)
            nwListener.stateUpdateHandler = { (state: NWListener.State) in
                switch state {
                case .ready:
                    // Try setting chmod 0600 on the socket
                    try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: socketPath)
                    stateHelper.resume()
                case .failed(let error):
                    print("Server failed with error: \(error)")
                    stateHelper.resume(throwing: error)
                default:
                    break
                }
            }
            
            nwListener.start(queue: DispatchQueue(label: "seen.server"))
        }
    }
    
    public func stop() {
        listener?.cancel()
        listener = nil
    }
    
    private func handleConnection(_ connection: NWConnection) async {
        connection.start(queue: DispatchQueue(label: "seen.server.conn"))
        
        var parser = HTTPParser()
        var isDone = false
        
        while !isDone {
            do {
                let (data, _, isComplete, error) = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(Data?, NWConnection.ContentContext?, Bool, NWError?), Error>) in
                    connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, context, isComplete, error in
                        continuation.resume(returning: (data, context, isComplete, error))
                    }
                }
                
                if error != nil {
                    isDone = true
                    break
                }
                
                if let data = data {
                    parser.append(data)
                    if let request = try? parser.parse() {
                        let response = await router.handle(request)
                        let responseData = response.serialize()
                        
                        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                            connection.send(content: responseData, isComplete: true, completion: .contentProcessed { error in
                                if let error = error {
                                    continuation.resume(throwing: error)
                                } else {
                                    continuation.resume()
                                }
                            })
                        }
                        isDone = true // Connection: close semantics
                    }
                }
                
                if isComplete {
                    isDone = true
                }
            } catch {
                isDone = true
            }
        }
        connection.cancel()
        try? await Task.sleep(nanoseconds: 50_000_000)
    }
}
