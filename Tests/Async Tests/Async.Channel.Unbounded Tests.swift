import Async_Test_Support
import Ownership
import Testing

@Suite
struct UnboundedChannelTests {

    @Test
    func `Send and receive single element`() async throws {
        let ends = Async.Channel<Int>.Unbounded().take().ends()

        try ends.sender.send(42)
        ends.close()
        let value = try await ends.receiver.receive()
        #expect(value == 42)
    }

    @Test
    func `Send succeeds when channel is open`() throws {
        let ends = Async.Channel<Int>.Unbounded().take().ends()
        try ends.sender.send(42)
        ends.close()
    }

    @Test
    func `Closed channel rejects send`() {
        let ends = Async.Channel<Int>.Unbounded().take().ends()
        ends.close()
        #expect(throws: Async.Channel<Int>.Error.closed) {
            try ends.sender.send(42)
        }
    }

    @Test
    func `Receive returns nil after close and drain`() async throws {
        let ends = Async.Channel<Int>.Unbounded().take().ends()

        try ends.sender.send(1)
        try ends.sender.send(2)
        ends.close()

        let first = try await ends.receiver.receive()
        let second = try await ends.receiver.receive()
        let third = try await ends.receiver.receive()

        #expect(first == 1)
        #expect(second == 2)
        #expect(third == nil)
    }

    @Test
    func `Poll returns nil when empty`() {
        let ends = Async.Channel<Int>.Unbounded().take().ends()
        let result = ends.receiver.poll()
        #expect(result == nil)
    }

    @Test
    func `Poll returns element when available`() throws {
        let ends = Async.Channel<Int>.Unbounded().take().ends()

        try ends.sender.send(42)
        let result = ends.receiver.poll()
        #expect(result == 42)
    }

    @Test
    func `Send batch elements`() async throws {
        let ends = Async.Channel<Int>.Unbounded().take().ends()

        try ends.sender.send(
            contentsOf: [Ownership.Slot(1), Ownership.Slot(2), Ownership.Slot(3)]
        )
        ends.close()

        var received: [Int] = []
        while let value = try await ends.receiver.receive() {
            received.append(value)
        }
        #expect(received == [1, 2, 3])
    }

    @Test
    func `closed reflects state`() {
        let ends = Async.Channel<Int>.Unbounded().take().ends()

        #expect(ends.sender.closed == false)
        #expect(ends.receiver.closed == false)
        ends.close()
        #expect(ends.sender.closed == true)
        #expect(ends.receiver.closed == true)
    }

    @Test
    func `Receive suspends until element available`() async throws {
        let ends = Async.Channel<Int>.Unbounded().take().ends()
        let started = Async.Barrier(parties: 2)

        let elements = ends.receiver.elements
        let sender = ends.sender

        let receiveTask = Task {
            try? await started.arrive()
            var iterator = elements.makeAsyncIterator()
            return try await iterator.next()
        }

        try? await started.arrive()

        try sender.send(42)

        let result = try await receiveTask.value
        #expect(result == 42)
    }

    @Test
    func `Receive resumes with nil on close`() async throws {
        let ends = Async.Channel<Int>.Unbounded().take().ends()
        let started = Async.Barrier(parties: 2)

        let elements = ends.receiver.elements
        let sender = ends.sender

        let receiveTask = Task {
            try? await started.arrive()
            var iterator = elements.makeAsyncIterator()
            return try await iterator.next()
        }

        try? await started.arrive()

        sender.close()

        let result = try await receiveTask.value
        #expect(result == nil)
    }

    @Test
    func `Multiple producers can send concurrently`() async throws {
        let ends = Async.Channel<Int>.Unbounded().take().ends()
        let sender = ends.sender
        let count = 100

        await withThrowingTaskGroup(of: Void.self) { group in
            for i in 0..<count {
                group.addTask {
                    try sender.send(i)
                }
            }
        }

        sender.close()

        var received: Set<Int> = []
        while let value = try await ends.receiver.receive() {
            received.insert(value)
        }

        #expect(received.count == count)
        (0..<count).forEach { i in
            #expect(received.contains(i))
        }
    }

    @Test
    func `Cancellation throws cancelled error`() async {
        let ends = Async.Channel<Int>.Unbounded().take().ends()
        let started = Async.Barrier(parties: 2)

        let elements = ends.receiver.elements

        let receiveTask = Task {
            try? await started.arrive()
            var iterator = elements.makeAsyncIterator()
            return try await iterator.next()
        }

        try? await started.arrive()

        receiveTask.cancel()

        do {
            _ = try await receiveTask.value
            Issue.record("Expected cancellation error")
        } catch let error as Async.Channel<Int>.Error {
            #expect(error == .cancelled)
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test
    func `Close with buffered elements drains then returns nil`() async throws {
        let ends = Async.Channel<Int>.Unbounded().take().ends()

        try ends.sender.send(1)
        try ends.sender.send(2)
        try ends.sender.send(3)

        ends.close()

        let first = try await ends.receiver.receive()
        let second = try await ends.receiver.receive()
        let third = try await ends.receiver.receive()

        #expect(first == 1)
        #expect(second == 2)
        #expect(third == 3)

        let fourth = try await ends.receiver.receive()
        #expect(fourth == nil)
    }

    @Test
    func `Sender copies share storage`() async throws {
        let ends = Async.Channel<Int>.Unbounded().take().ends()
        let sender1 = ends.sender
        let sender2 = sender1

        try sender1.send(1)
        try sender2.send(2)

        let first = ends.receiver.poll()
        let second = ends.receiver.poll()

        #expect(first == 1)
        #expect(second == 2)

        sender1.close()
        #expect(sender2.closed == true)
        #expect(ends.receiver.closed == true)
    }

    @Test
    func `Sender copies compare equal by endpoint identity`() {
        let ends = Async.Channel<Int>.Unbounded().take().ends()
        let sender = ends.sender
        let copy = sender

        #expect(sender == copy)
    }

    @Test
    func `Senders from distinct channels compare unequal`() {
        let first = Async.Channel<Int>.Unbounded().take().ends()
        let second = Async.Channel<Int>.Unbounded().take().ends()

        #expect(first.sender != second.sender)
    }

    @Test
    func `Sender equality remains stable after close`() {
        let ends = Async.Channel<Int>.Unbounded().take().ends()
        let sender = ends.sender
        let copy = sender

        sender.close()

        #expect(sender == copy)
    }

    @Test
    func `Sender equality supports noncopyable elements`() {
        final class Payload {}
        struct Parcel: ~Copyable {
            let payload: Payload
        }

        let ends = Async.Channel<Parcel>.Unbounded().take().ends()
        let sender = ends.sender
        let copy = sender

        #expect(sender == copy)
    }

    @Test
    func `Direct delivery when receiver waiting`() async throws {
        let ends = Async.Channel<Int>.Unbounded().take().ends()
        let started = Async.Barrier(parties: 2)

        let elements = ends.receiver.elements
        let sender = ends.sender

        let receiveTask = Task {
            try? await started.arrive()
            var iterator = elements.makeAsyncIterator()
            return try await iterator.next()
        }

        try? await started.arrive()

        try sender.send(42)

        let value = try await receiveTask.value
        #expect(value == 42)

        let remaining = ends.receiver.poll()
        #expect(remaining == nil)
    }

    @Test
    func `AsyncSequence iteration`() async throws {
        let ends = Async.Channel<Int>.Unbounded().take().ends()

        try ends.sender.send(
            contentsOf: [Ownership.Slot(1), Ownership.Slot(2), Ownership.Slot(3)]
        )
        ends.close()

        var received: [Int] = []
        for try await value in ends.receiver.elements {
            received.append(value)
        }

        #expect(received == [1, 2, 3])
    }

    @Test
    func `Poll does not affect suspension state`() async throws {
        let ends = Async.Channel<Int>.Unbounded().take().ends()
        let started = Async.Barrier(parties: 2)
        let sender = ends.sender

        #expect(ends.receiver.poll() == nil)

        let elements = ends.receiver.elements

        let receiveTask = Task {
            try? await started.arrive()
            var iterator = elements.makeAsyncIterator()
            return try await iterator.next()
        }

        try? await started.arrive()

        try sender.send(42)

        let value = try await receiveTask.value
        #expect(value == 42)
    }

    @Test
    func `Non-Sendable element exits receive() across an isolation boundary (sending result)`()
        async throws
    {

        final class Payload {
            var value: Int
            init(value: Int) { self.value = value }
        }
        struct Parcel: ~Copyable {
            let payload: Payload
        }
        actor Sink {
            func consume(_ parcel: consuming sending Parcel) -> Int {
                parcel.payload.value
            }
        }

        let ends = Async.Channel<Parcel>.Unbounded().take().ends()
        try ends.sender.send(Parcel(payload: Payload(value: 99)))
        ends.sender.close()
        guard let parcel = try await ends.receiver.receive() else {
            Issue.record("expected an element before close drained")
            return
        }

        let sink = Sink()
        let received = await sink.consume(parcel)
        #expect(received == 99)
    }
}
