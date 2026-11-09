#if !hasFeature(Embedded)

    import Synchronization

    extension Async {

        public final class Completion<Success: Sendable, Failure: Swift::Error>: Sendable {

            private let _state: Atomic<State>
            private let _outcome: Async.Mutex<Outcome>

            public init() {
                self._state = Atomic(.pending)
                self._outcome = Async.Mutex(Outcome())
            }
        }
    }

    extension Async.Completion {

        public typealias Result = Swift::Result<
            Success, Async.Completion<Success, Failure>.Error
        >
    }

    extension Async.Completion {

        fileprivate struct Outcome: Sendable {
            var waiters: [CheckedContinuation<Result, Never>] = []
            var result: Result? = nil
        }

        /// Suspends until the terminal transition and returns its result.
        ///
        /// Any number of callers may await, before or after the terminal
        /// transition; each receives the same result. Task cancellation is
        /// ignored: a cancelled awaiter keeps waiting.
        nonisolated(nonsending)
            public func result() async -> Result
        {
            await withCheckedContinuation { continuation in
                let immediate: Result? = _outcome.withLock { outcome in
                    if let result = outcome.result {
                        return result
                    }
                    outcome.waiters.append(continuation)
                    return nil
                }
                if let immediate {
                    continuation.resume(returning: immediate)
                }
            }
        }

        private func finish(_ result: Result) {
            let waiters = _outcome.withLock { outcome in
                outcome.result = result
                let waiters = outcome.waiters
                outcome.waiters = []
                return waiters
            }
            for waiter in waiters {
                waiter.resume(returning: result)
            }
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
            finish(.success(value))
        }

        public func timeout() throws(Transition.Error) {
            let (exchanged, _) = _state.compareExchange(
                expected: .running,
                desired: .timedOut,
                ordering: .acquiringAndReleasing
            )
            guard exchanged else { throw .alreadyDone }
            finish(.failure(.timeout))
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
            finish(.failure(.cancelled))
        }

        public func fail(_ error: Failure) throws(Transition.Error) {

            let (exchanged, _) = _state.compareExchange(
                expected: .pending,
                desired: .failed,
                ordering: .acquiringAndReleasing
            )
            guard exchanged else { throw .alreadyDone }
            finish(.failure(.failure(error)))
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
