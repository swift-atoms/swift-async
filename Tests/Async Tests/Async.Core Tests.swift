import Async_Test_Support
import Testing

enum Core {
    enum Test {
        @Suite struct `Lifecycle transitions follow the shutdown order` {}
        @Suite struct `Precedence resolves competing completion outcomes` {}
        @Suite struct `Promises retain the first fulfilled value` {}
        #if !hasFeature(Embedded)
            @Suite struct `Completions enforce their state transitions` {}
        #endif
    }
}

extension Core.Test.`Lifecycle transitions follow the shutdown order` {
    @Test
    func `Open state has correct queries`() {
        var state: Async.Lifecycle.State = .open
        #expect(state.isOpen)
        let isActive = state.shutdown.isActive
        let isComplete = state.shutdown.isComplete
        #expect(!isActive)
        #expect(!isComplete)
    }

    @Test
    func `Closing state has correct queries`() {
        var state: Async.Lifecycle.State = .closing
        #expect(!state.isOpen)
        let isActive = state.shutdown.isActive
        let isComplete = state.shutdown.isComplete
        #expect(isActive)
        #expect(!isComplete)
    }

    @Test
    func `Closed state has correct queries`() {
        var state: Async.Lifecycle.State = .closed
        #expect(!state.isOpen)
        let isActive = state.shutdown.isActive
        let isComplete = state.shutdown.isComplete
        #expect(isActive)
        #expect(isComplete)
    }

    @Test
    func `Shutdown begin transitions open to closing`() {
        var state: Async.Lifecycle.State = .open
        let result = state.shutdown.begin()
        #expect(result)
        #expect(state == .closing)
    }

    @Test
    func `Shutdown begin is idempotent on closing`() {
        var state: Async.Lifecycle.State = .closing
        let result = state.shutdown.begin()
        #expect(!result)
        #expect(state == .closing)
    }

    @Test
    func `Shutdown begin is idempotent on closed`() {
        var state: Async.Lifecycle.State = .closed
        let result = state.shutdown.begin()
        #expect(!result)
        #expect(state == .closed)
    }

    @Test
    func `Shutdown complete transitions closing to closed`() {
        var state: Async.Lifecycle.State = .closing
        let result = state.shutdown.complete()
        #expect(result)
        #expect(state == .closed)
    }

    @Test
    func `Shutdown complete is idempotent on open`() {
        var state: Async.Lifecycle.State = .open
        let result = state.shutdown.complete()
        #expect(!result)
        #expect(state == .open)
    }

    @Test
    func `Shutdown complete is idempotent on closed`() {
        var state: Async.Lifecycle.State = .closed
        let result = state.shutdown.complete()
        #expect(!result)
        #expect(state == .closed)
    }

    @Test
    func `Full lifecycle open to closing to closed`() {
        var state: Async.Lifecycle.State = .open
        #expect(state.isOpen)

        let didBegin = state.shutdown.begin()
        #expect(didBegin)
        #expect(state == .closing)
        let isActive = state.shutdown.isActive
        let isComplete = state.shutdown.isComplete
        #expect(isActive)
        #expect(!isComplete)

        let didComplete = state.shutdown.complete()
        #expect(didComplete)
        #expect(state == .closed)
        let finalComplete = state.shutdown.isComplete
        #expect(finalComplete)
    }

    @Test
    func `Cannot skip closing state`() {
        var state: Async.Lifecycle.State = .open

        let result = state.shutdown.complete()
        #expect(!result)
        #expect(state == .open)
    }
}

extension Core.Test.`Precedence resolves competing completion outcomes` {
    @Test
    func `Shutdown takes precedence over every other outcome`() {
        let result = Async.Precedence.resolve(
            shutdown: true,
            cancelled: true,
            timedOut: true,
            success: "success",
            onShutdown: "shutdown",
            onCancelled: "cancelled",
            onTimeout: "timeout"
        )
        #expect(result == "shutdown")
    }

    @Test
    func `Cancelled dominates timeout and success`() {
        let result = Async.Precedence.resolve(
            shutdown: false,
            cancelled: true,
            timedOut: true,
            success: "success",
            onShutdown: "shutdown",
            onCancelled: "cancelled",
            onTimeout: "timeout"
        )
        #expect(result == "cancelled")
    }

    @Test
    func `Timeout takes precedence over success`() {
        let result = Async.Precedence.resolve(
            shutdown: false,
            cancelled: false,
            timedOut: true,
            success: "success",
            onShutdown: "shutdown",
            onCancelled: "cancelled",
            onTimeout: "timeout"
        )
        #expect(result == "timeout")
    }

    @Test
    func `Success when nothing is set`() {
        let result = Async.Precedence.resolve(
            shutdown: false,
            cancelled: false,
            timedOut: false,
            success: "success",
            onShutdown: "shutdown",
            onCancelled: "cancelled",
            onTimeout: "timeout"
        )
        #expect(result == "success")
    }

    @Test
    func `Autoclosure lazily evaluates success outcome`() {
        var evaluated = false
        let result = Async.Precedence.resolve(
            shutdown: true,
            cancelled: false,
            timedOut: false,
            success: {
                evaluated = true
                return "success"
            }(),
            onShutdown: "shutdown",
            onCancelled: "cancelled",
            onTimeout: "timeout"
        )
        #expect(result == "shutdown")
        #expect(!evaluated)
    }
}

extension Core.Test.`Promises retain the first fulfilled value` {
    @Test
    func `Init creates unfulfilled promise`() {
        let promise = Async.Promise<Int>()
        #expect(!promise.isFulfilled)
        #expect(promise.fulfilled == nil)
    }

    @Test
    func `Value() does not observe Task cancellation`() async {

        let promise = Async.Promise<Int>()

        let task = Task { await promise.value() }

        try? await Task.sleep(for: .milliseconds(20))

        task.cancel()

        try? await Task.sleep(for: .milliseconds(20))

        #expect(promise.fulfill(42))

        let result = await task.value
        #expect(result == 42, "cancelled awaiter still receives the fulfilled value")
        #expect(task.isCancelled, "task should still report itself as cancelled")
    }

    @Test
    func `Fulfill sets value and returns true`() {
        let promise = Async.Promise<Int>()
        let result = promise.fulfill(42)
        #expect(result)
        #expect(promise.isFulfilled)
        #expect(promise.fulfilled == 42)
    }

    @Test
    func `Double fulfill returns false`() {
        let promise = Async.Promise<Int>()
        #expect(promise.fulfill(1))
        #expect(!promise.fulfill(2))

        #expect(promise.fulfilled == 1)
    }

    @Test
    func `Wait callback invoked immediately when fulfilled`() {
        let promise = Async.Promise<Int>()
        promise.fulfill(42)

        let publication = Async.Publication<Int>()
        promise.wait { value in
            publication.publish(value)
        }
        #expect(publication.take() == 42)
    }

    @Test
    func `Wait callback deferred until fulfill`() {
        let promise = Async.Promise<Int>()

        let publication = Async.Publication<Int>()
        promise.wait { value in
            publication.publish(value)
        }

        #expect(publication.take() == nil)

        promise.fulfill(99)
        #expect(publication.take() == 99)
    }

    @Test
    func `Multiple waiters all receive value`() {
        let promise = Async.Promise<Int>()

        let pub1 = Async.Publication<Int>()
        let pub2 = Async.Publication<Int>()
        let pub3 = Async.Publication<Int>()

        promise.wait { pub1.publish($0) }
        promise.wait { pub2.publish($0) }
        promise.wait { pub3.publish($0) }

        promise.fulfill(7)

        #expect(pub1.take() == 7)
        #expect(pub2.take() == 7)
        #expect(pub3.take() == 7)
    }

    @Test
    func `Gate open and wait`() {
        let gate = Async.Gate()
        #expect(!gate.isOpen)

        let publication = Async.Publication<Bool>()
        gate.wait {
            publication.publish(true)
        }
        #expect(publication.take() == nil)

        #expect(gate.open())
        #expect(gate.isOpen)
        #expect(publication.take() == true)
    }

    @Test
    func `Gate double open returns false`() {
        let gate = Async.Gate()
        #expect(gate.open())
        #expect(!gate.open())
    }

    #if !hasFeature(Embedded)
        @Test
        func `Async value returns fulfilled value`() async {
            let promise = Async.Promise<Int>()
            promise.fulfill(42)
            let value = await promise.value()
            #expect(value == 42)
        }

        @Test
        func `Async gate wait returns after open`() async {
            let gate = Async.Gate()
            gate.open()
            await gate.wait()

        }
    #endif
}


#if !hasFeature(Embedded)
    extension Core.Test.`Completions enforce their state transitions` {
        @Test
        func `Init creates pending state`() {
            let completion = Async.Completion<Int, Never>()
            #expect(completion.state == .pending)
            #expect(!completion.isTerminal)
        }

        @Test
        func `Start transitions to running`() throws {
            let completion = Async.Completion<Int, Never>()
            try completion.start()
            #expect(completion.state == .running)
            #expect(!completion.isTerminal)
        }

        @Test
        func `Complete transitions to completed`() throws {
            let completion = Async.Completion<Int, Never>()
            try completion.start()
            try completion.complete(42)
            #expect(completion.state == .completed)
            #expect(completion.isTerminal)
        }

        @Test
        func `Timeout transitions to timedOut`() throws {
            let completion = Async.Completion<Int, Never>()
            try completion.start()
            try completion.timeout()
            #expect(completion.state == .timedOut)
            #expect(completion.isTerminal)
        }

        @Test
        func `Cancel from pending transitions to cancelled`() throws {
            let completion = Async.Completion<Int, Never>()
            try completion.cancel()
            #expect(completion.state == .cancelled)
            #expect(completion.isTerminal)
        }

        @Test
        func `Cancel from running transitions to cancelled`() throws {
            let completion = Async.Completion<Int, Never>()
            try completion.start()
            try completion.cancel()
            #expect(completion.state == .cancelled)
            #expect(completion.isTerminal)
        }

        @Test
        func `Starting a completion twice throws`() throws {
            let completion = Async.Completion<Int, Never>()
            try completion.start()
            do {
                try completion.start()
                Issue.record("Expected alreadyDone error")
            } catch {

            }
        }

        @Test
        func `Complete without start throws`() {
            let completion = Async.Completion<Int, Never>()
            do {
                try completion.complete(42)
                Issue.record("Expected alreadyDone error")
            } catch {

            }
        }

        @Test
        func `Timeout without start throws`() {
            let completion = Async.Completion<Int, Never>()
            do {
                try completion.timeout()
                Issue.record("Expected alreadyDone error")
            } catch {

            }
        }

        @Test
        func `Cancel from completed throws`() throws {
            let completion = Async.Completion<Int, Never>()
            try completion.start()
            try completion.complete(42)
            do {
                try completion.cancel()
                Issue.record("Expected alreadyDone error")
            } catch {

            }
        }

        @Test
        func `Complete after timeout throws`() throws {
            let completion = Async.Completion<Int, Never>()
            try completion.start()
            try completion.timeout()
            do {
                try completion.complete(99)
                Issue.record("Expected alreadyDone error")
            } catch {

            }
        }

        @Test
        func `Fail from pending transitions to failed`() {
            let completion = Async.Completion<Int, TestError>()
            do {
                try completion.fail(.testFailure)
                #expect(completion.state == .failed)
                #expect(completion.isTerminal)
            } catch {
                Issue.record("Unexpected error")
            }
        }

        @Test
        func `Fail from running throws`() throws {
            let completion = Async.Completion<Int, TestError>()
            try completion.start()
            do {
                try completion.fail(.testFailure)
                Issue.record("Expected alreadyDone error")
            } catch {

            }
        }

        @Test
        func `Full lifecycle with continuation`() async {
            let completion = Async.Completion<Int, Never>()

            let result = await withCheckedContinuation { continuation in
                completion.set(continuation: continuation)
                do {
                    try completion.start()
                    try completion.complete(42)
                } catch {
                    Issue.record("Unexpected transition error: \(error)")
                }
            }

            if case .success(let value) = result {
                #expect(value == 42)
            } else {
                Issue.record("Expected success result")
            }
        }

        @Test
        func `Cancellation delivers cancellation error`() async {
            let completion = Async.Completion<Int, Never>()

            let result = await withCheckedContinuation { continuation in
                completion.set(continuation: continuation)
                do {
                    try completion.start()
                    try completion.cancel()
                } catch {
                    Issue.record("Unexpected transition error: \(error)")
                }
            }

            if case .failure(.cancelled) = result {

            } else {
                Issue.record("Expected cancelled error, got \(result)")
            }
        }

        @Test
        func `Timeout delivers timeout error`() async {
            let completion = Async.Completion<Int, Never>()

            let result = await withCheckedContinuation { continuation in
                completion.set(continuation: continuation)
                do {
                    try completion.start()
                    try completion.timeout()
                } catch {
                    Issue.record("Unexpected transition error: \(error)")
                }
            }

            if case .failure(.timeout) = result {

            } else {
                Issue.record("Expected timeout error, got \(result)")
            }
        }
    }

    private enum TestError: Swift.Error, Sendable {
        case testFailure
    }
#endif
