extension Async.Cancellation.Source {
    struct _State {
        var machine: Async.Cancellation.State = .active
        var nextIdentifier: UInt64 = 0
        var handlers: [UInt64: @Sendable () -> Void] = [:]
    }
}
