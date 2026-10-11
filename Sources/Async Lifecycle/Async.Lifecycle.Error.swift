extension Async.Lifecycle {

    public enum Error: Swift::Error, Sendable, Equatable {

        case shutdown

        case cancelled

        case timeout
    }
}

extension Async.Lifecycle.Error: CustomStringConvertible {

    public var description: Swift::String {
        switch self {
        case .shutdown: "shutdown"
        case .cancelled: "cancelled"
        case .timeout: "timeout"
        }
    }
}
