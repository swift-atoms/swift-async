internal import Async_Mutex

extension Async.Cancellation {

    public final class Source: Sendable {
        let _state: Async.Mutex<_State>

        public init() {
            self._state = Async.Mutex(_State())
        }
    }
}

extension Async.Cancellation.Source {

    public var isCancelled: Bool {
        self._state.withLock { $0.machine.isCancelled }
    }

    public var token: Async.Cancellation.Token {
        Async.Cancellation.Token(source: self)
    }
}

extension Async.Cancellation.Source {

    @discardableResult
    public func cancel() -> Bool {
        let fired: [(UInt64, @Sendable () -> Void)]? = self._state.withLock { state in
            guard state.machine.cancel() else { return nil }
            let handlers = state.handlers.sorted { $0.key < $1.key }
            state.handlers.removeAll()
            return handlers.map { ($0.key, $0.value) }
        }
        guard let fired else { return false }
        for (_, handler) in fired {
            handler()
        }
        return true
    }
}

extension Async.Cancellation.Source {

    public func onCancel(
        _ handler: @escaping @Sendable () -> Void
    ) -> Async.Cancellation.Registration {
        let identifier: UInt64? = self._state.withLock { state in
            guard !state.machine.isCancelled else { return nil }
            let identifier = state.nextIdentifier
            state.nextIdentifier &+= 1
            state.handlers[identifier] = handler
            return identifier
        }
        guard let identifier else {

            handler()
            return Async.Cancellation.Registration(source: self, identifier: nil)
        }
        return Async.Cancellation.Registration(source: self, identifier: identifier)
    }

    func _deregister(_ identifier: UInt64) -> Bool {
        self._state.withLock { state in
            state.handlers.removeValue(forKey: identifier) != nil
        }
    }
}
