import Async
import Ownership
import Testing

extension Benchmark {
    @Suite struct UnboundedChannel {}
}

extension Benchmark.UnboundedChannel {

    @Test(.timed(iterations: 10, warmup: 2))
    func `1000 batch send`() async throws {
        let ends = Async.Channel<Int>.Unbounded().take().ends()
        let elements = Array(0..<Benchmark.iterations)

        try ends.sender.send(contentsOf: elements.map { Ownership.Slot($0) })
        ends.close()

        var count = 0
        while try await ends.receiver.receive() != nil { count += 1 }
        #expect(count == Benchmark.iterations)
    }

    @Test(.timed(iterations: 10, warmup: 2))
    func `1000 per-element send`() async throws {
        let ends = Async.Channel<Int>.Unbounded().take().ends()

        for i in 0..<Benchmark.iterations {
            try ends.sender.send(i)
        }
        ends.close()

        var count = 0
        while try await ends.receiver.receive() != nil { count += 1 }
        #expect(count == Benchmark.iterations)
    }
}

extension Benchmark.UnboundedChannel {

    @Test(.timed(iterations: 10, warmup: 2))
    func `1000 round-trips`() async throws {
        let ends = Async.Channel<Int>.Unbounded().take().ends()

        let producer = Task.detached {
            for i in 0..<Benchmark.iterations {
                try ends.sender.send(i)
            }
        }

        for _ in 0..<Benchmark.iterations {
            _ = try await ends.receiver.receive()
        }

        _ = try await producer.value
        ends.close()
    }

    @Test(.timed(iterations: 10, warmup: 2))
    func `1000 batch round-trips`() async throws {
        let ends = Async.Channel<Int>.Unbounded().take().ends()
        let started = Async.Barrier(parties: 2)

        let receiver = Task {
            await started.arrive()
            var count = 0
            while try await ends.receiver.receive() != nil { count += 1 }
            return count
        }

        await started.arrive()
        let elements = Array(0..<Benchmark.iterations)
        try ends.sender.send(contentsOf: elements.map { Ownership.Slot($0) })
        ends.close()

        let count = try await receiver.value
        #expect(count == Benchmark.iterations)
    }
}
