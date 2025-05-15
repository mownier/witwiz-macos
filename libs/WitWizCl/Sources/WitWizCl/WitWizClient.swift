import GRPCCore
import GRPCNIOTransportHTTP2

public actor WitWizClient {
    var host: String
    var port: Int?
    var useTLS: Bool
    
    public init() {
        self.host = ""
        self.port = nil
        self.useTLS = true
    }
    
    @discardableResult
    public func host(_ value: String) -> WitWizClient {
        host = value
        return self
    }
    
    @discardableResult
    public func port(_ value: Int?) -> WitWizClient {
        port = value
        return self
    }
    
    @discardableResult
    public func useTLS(_ value: Bool) -> WitWizClient {
        useTLS = value
        return self
    }
    
    public func joinGame(
        _ playerInputStream: AsyncStream<Witwiz_PlayerInput>,
        _ gameStateContinuation: AsyncStream<Witwiz_GameStateUpdate>.Continuation,
        _ okContination: AsyncStream<Bool>.Continuation
    ) async throws {
        try await withGRPCClient(
            transport: .http2NIOPosix(
                target: .dns(host: host, port: port),
                transportSecurity: useTLS ? .tls : .plaintext
            ),
            handleClient: { cl in
                let client = Witwiz_WitWiz.Client(wrapping: cl)
                let request = StreamingClientRequest<Witwiz_PlayerInput> { [weak self] writer in
                    for try await playerInput in try await playerInputStream {
                        if Task.isCancelled {
                            throw Errors.cancelled
                        }
                        try await writer.write(playerInput)
                    }
                }
                try await client.joinGame(request: request) { stream in
                    okContination.yield(true)
                    for try await update in try await stream.messages {
                        if Task.isCancelled {
                            throw Errors.cancelled
                        }
                        try await gameStateContinuation.yield(update)
                    }
                }
            }
        )
    }
    
    public enum Errors: Error {
        case cancelled
    }
}
