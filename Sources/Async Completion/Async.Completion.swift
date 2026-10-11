#if !hasFeature(Embedded)

    import Synchronization

    extension Async {

        public final class Completion<Success: Sendable, Failure: Swift::Error>: Sendable {

            private let _state: Atomic<State>
            private let _continuation: Async.Mutex<CheckedContinuation<Result, Never>?>

            public init() {
                self._state = Atomic(.pending)
                self._continuation = Async.Mutex(nil)
            }
        }
    }

    extension Async.Completion {

        public typealias Result = Swift::Result<
            Success, Async.Completion<Success, Failure>.Error
        >
    }

    extension Async.Completion {

        public func set(continuation: CheckedContinuation<Result, Never>) {
            _continuation.withLock { $0 = continuation }
        }
    }

    extension Async.Completion {

        public func start() throws(Transition.Error) {
            let (exchanged, _) = _state.compareExchange(
                expected: .pending,
                desired: .running,
                ordering: .acquiringAndReleasing
            )
            guard exchanged else { throw .alreadyDone }
        }

        public func complete(_ value: sending Success) throws(Transition.Error) {
            let (exchanged, _) = _state.compareExchange(
                expected: .running,
                desired: .completed,
                ordering: .acquiringAndReleasing
            )
            guard exchanged else { throw .alreadyDone }
            let cont = _continuation.withLock { cont in
                let captured = cont
                cont = nil
                return captured
            }
            cont?.resume(returning: .success(value))
        }

        public func timeout() throws(Transition.Error) {
            let (exchanged, _) = _state.compareExchange(
                expected: .running,
                desired: .timedOut,
                ordering: .acquiringAndReleasing
            )
            guard exchanged else { throw .alreadyDone }
            let cont = _continuation.withLock { cont in
                let captured = cont
                cont = nil
                return captured
            }
            cont?.resume(returning: .failure(.timeout))
        }

        public func cancel() throws(Transition.Error) {

            var (exchanged, original) = _state.compareExchange(
                expected: .pending,
                desired: .cancelled,
                ordering: .acquiringAndReleasing
            )
            if !exchanged && original == .running {
                (exchanged, _) = _state.compareExchange(
                    expected: .running,
                    desired: .cancelled,
                    ordering: .acquiringAndReleasing
                )
            }
            guard exchanged else { throw .alreadyDone }
            let cont = _continuation.withLock { cont in
                let captured = cont
                cont = nil
                return captured
            }
            cont?.resume(returning: .failure(.cancelled))
        }

        public func fail(_ error: Failure) throws(Transition.Error) {

            let (exchanged, _) = _state.compareExchange(
                expected: .pending,
                desired: .failed,
                ordering: .acquiringAndReleasing
            )
            guard exchanged else { throw .alreadyDone }
            let cont = _continuation.withLock { cont in
                let captured = cont
                cont = nil
                return captured
            }
            cont?.resume(returning: .failure(.failure(error)))
        }
    }

    extension Async.Completion where Failure == Never {

        public func fail(_ error: Async.Completion<Success, Never>.Error) throws(Transition.Error) {
            switch error {
            case .timeout:
                try timeout()

            case .cancelled:
                try cancel()

            case .failure:

                fatalError("Cannot fail with Never error type")
            }
        }
    }

    extension Async.Completion {

        public var state: State {
            _state.load(ordering: .acquiring)
        }

        public var isTerminal: Bool {
            switch state {
            case .pending, .running:
                return false

            case .completed, .timedOut, .cancelled, .failed:
                return true
            }
        }
    }

#endif
