import Async_Test_Support
import Synchronization
import Testing

enum Cancellation {
    enum Test {
        @Suite struct `Cancellation operations preserve their basic behavior` {}
        @Suite struct `Cancellation operations preserve boundary behavior` {}
        @Suite struct `Cancellation operations preserve state during concurrent use` {}
    }
}

extension Cancellation.Test.`Cancellation operations preserve their basic behavior` {
    @Test
    func `state transitions exactly once`() {
        var state = Async.Cancellation.State.active
        #expect(!state.isCancelled)
        let firstTransition = state.cancel()
        #expect(firstTransition)
        #expect(state.isCancelled)
        let secondTransition = state.cancel()
        #expect(!secondTransition)
        #expect(state.isCancelled)
    }

    @Test
    func `source cancels exactly once`() {
        let source = Async.Cancellation.Source()
        #expect(!source.isCancelled)
        #expect(source.cancel())
        #expect(source.isCancelled)
        #expect(!source.cancel())
        #expect(source.isCancelled)
    }

    @Test
    func `handler runs exactly once at cancellation`() {
        let source = Async.Cancellation.Source()
        let count = Atomic<Int>(0)
        let registration = source.onCancel { count.wrappingAdd(1, ordering: .relaxed) }
        #expect(count.load(ordering: .relaxed) == 0)
        source.cancel()
        #expect(count.load(ordering: .relaxed) == 1)
        source.cancel()
        #expect(count.load(ordering: .relaxed) == 1)

        #expect(!registration.deregister())
    }

    @Test
    func `handler registered after cancellation runs promptly`() {
        let source = Async.Cancellation.Source()
        source.cancel()
        let count = Atomic<Int>(0)
        let registration = source.onCancel { count.wrappingAdd(1, ordering: .relaxed) }
        #expect(count.load(ordering: .relaxed) == 1)
        #expect(!registration.deregister())
    }

    @Test
    func `deregistered handler never runs`() {
        let source = Async.Cancellation.Source()
        let count = Atomic<Int>(0)
        let registration = source.onCancel { count.wrappingAdd(1, ordering: .relaxed) }
        #expect(registration.deregister())
        #expect(!registration.deregister())
        source.cancel()
        #expect(count.load(ordering: .relaxed) == 0)
    }

    @Test
    func `token observes source state`() throws {
        let source = Async.Cancellation.Source()
        let token = source.token
        #expect(!token.isCancelled)
        try token.checkCancellation()
        source.cancel()
        #expect(token.isCancelled)
        #expect(throws: Async.Cancellation.Error.cancelled) {
            try token.checkCancellation()
        }
    }
}

extension Cancellation.Test.`Cancellation operations preserve boundary behavior` {
    @Test
    func `cancel with no handlers`() {
        let source = Async.Cancellation.Source()
        #expect(source.cancel())
        #expect(source.isCancelled)
    }

    @Test
    func `handlers run in registration order`() {
        let source = Async.Cancellation.Source()
        let order = Async.Mutex<[Int]>([])
        (0..<8).forEach { index in
            _ = source.onCancel { order.withLock { $0.append(index) } }
        }
        source.cancel()
        #expect(order.withLock { $0 } == Array(0..<8))
    }

    @Test
    func `handler may reenter source`() {
        let source = Async.Cancellation.Source()
        let observed = Atomic<Bool>(false)
        _ = source.onCancel {
            if source.isCancelled, !source.cancel() {
                observed.store(true, ordering: .relaxed)
            }
        }
        source.cancel()
        let wasObserved = observed.load(ordering: .relaxed)
        #expect(wasObserved)
    }
}

private final class Counter: Sendable {
    private let _value = Atomic<Int>(0)
}

extension Counter {
    var value: Int { self._value.load(ordering: .relaxed) }

    func increment() {
        self._value.wrappingAdd(1, ordering: .relaxed)
    }
}

extension Cancellation.Test.`Cancellation operations preserve state during concurrent use` {
    @Test
    func `concurrent cancel is exactly once`() async {
        let source = Async.Cancellation.Source()
        let handlerRuns = Counter()
        let transitions = Counter()
        for _ in 0..<16 {
            _ = source.onCancel { handlerRuns.increment() }
        }
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<32 {
                group.addTask {
                    if source.cancel() {
                        transitions.increment()
                    }
                }
            }
        }
        #expect(transitions.value == 1)
        #expect(handlerRuns.value == 16)
    }

    @Test
    func `registration races cancellation`() async {
        for _ in 0..<64 {
            let source = Async.Cancellation.Source()
            let runs = Counter()
            await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    _ = source.onCancel { runs.increment() }
                }
                group.addTask {
                    source.cancel()
                }
            }
            #expect(runs.value == 1)
        }
    }
}
