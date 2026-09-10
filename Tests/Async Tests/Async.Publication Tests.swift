import Async_Test_Support
import Testing

enum Publication {
    enum Test {
        @Suite struct `Publication operations preserve their basic behavior` {}
        @Suite struct `Publication operations preserve boundary behavior` {}
        @Suite struct `Publication operations compose with their dependencies` {}
        @Suite(.serialized) struct `Publication operations preserve values during repeated execution` {}
    }
}

extension Publication.Test.`Publication operations preserve their basic behavior` {
    @Test
    func `Init creates empty slot`() {
        let publication = Async.Publication<Int>()
        let taken = publication.take()
        #expect(taken == nil)
    }

    @Test
    func `Init with value creates non-empty slot`() {
        let publication = Async.Publication<Int>(42)
        let taken = publication.take()
        #expect(taken == 42)
    }

    @Test
    func `Publishing stores a value`() {
        let publication = Async.Publication<Int>()
        publication.publish(42)
        let taken = publication.take()
        #expect(taken == 42)
    }

    @Test
    func `Taking a published value clears its slot`() {
        let publication = Async.Publication<Int>()
        publication.publish(42)
        _ = publication.take()
        let secondTake = publication.take()
        #expect(secondTake == nil)
    }

    @Test
    func `Latest publish dominates earlier values`() {
        let publication = Async.Publication<Int>()
        publication.publish(1)
        publication.publish(2)
        publication.publish(3)

        let taken = publication.take()
        #expect(taken == 3)
    }

    @Test
    func `Multiple takes after single publish - single winner`() {
        let publication = Async.Publication<Int>()
        publication.publish(42)

        let first = publication.take()
        let second = publication.take()
        let third = publication.take()

        #expect(first == 42)
        #expect(second == nil)
        #expect(third == nil)
    }
}

extension Publication.Test.`Publication operations preserve boundary behavior` {
    @Test
    func `Take on never-published slot`() {
        let publication = Async.Publication<String>()
        #expect(publication.take() == nil)
        #expect(publication.take() == nil)
    }

    @Test
    func `Publish after take resets slot`() {
        let publication = Async.Publication<Int>()
        publication.publish(1)
        _ = publication.take()
        publication.publish(2)
        #expect(publication.take() == 2)
    }

    @Test
    func `Rapid publication and consumption preserve their values`() {
        let publication = Async.Publication<Int>()

        (0..<1000).forEach { i in
            publication.publish(i)
            let taken = publication.take()
            #expect(taken == i)
        }
    }
}

extension Publication.Test.`Publication operations preserve values during repeated execution` {

    @Test
    func `Concurrent take race - exactly one winner`() async {

        for round in 0..<100 {
            let publication = Async.Publication<Int>()
            let publishedValue = round * 1000 + 42
            publication.publish(publishedValue)

            let results = await withTaskGroup(of: Int?.self) { group in
                for _ in 0..<10 {
                    group.addTask {
                        publication.take()
                    }
                }

                var results: [Int?] = []
                for await result in group {
                    results.append(result)
                }
                return results
            }

            let winners = results.compactMap { $0 }
            #expect(
                winners.count == 1,
                "Expected exactly 1 winner, got \(winners.count) in round \(round)"
            )

            #expect(winners.first == publishedValue)

            let losers = results.filter { $0 == nil }
            #expect(losers.count == 9)
        }
    }

    @Test
    func `Publish happens-before take visibility`() async {

        let publication = Async.Publication<Int>()
        let iterations = 1_000
        let range = 0..<iterations

        await withTaskGroup(of: Void.self) { group in

            group.addTask {
                for i in range {
                    publication.publish(i)
                    await Task.yield()
                }
            }

            group.addTask {
                var seen = false
                for _ in 0..<(iterations * 10) {
                    if let value = publication.take() {

                        #expect(range.contains(value), "Observed out-of-range value: \(value)")
                        seen = true
                        break
                    }
                    await Task.yield()
                }

                #expect(seen, "Never observed any published value - visibility failure")
            }
        }
    }

    @Test
    func `Publish-take interleaving observes valid values`() async {

        let publication = Async.Publication<Int>()
        let iterations = 1_000
        let range = 0..<iterations

        let ends = Async.Channel<Int>.Unbounded().take().ends()

        await withTaskGroup(of: Void.self) { group in

            group.addTask {
                for i in range {
                    publication.publish(i)
                    await Task.yield()
                }
            }

            group.addTask { [sender = ends.sender] in
                for _ in range {
                    if let value = publication.take() {
                        try? sender.send(value)
                    }
                    await Task.yield()
                }
            }
        }

        ends.close()

        var observed: [Int] = []
        while let value = try? await ends.receiver.receive() {
            observed.append(value)
        }

        #expect(!observed.isEmpty, "No values observed during interleaving")

        for value in observed {
            #expect(range.contains(value), "Observed out-of-range value: \(value)")
        }
    }

    @Test
    func `High contention publish-take admissibility`() async {

        let publication = Async.Publication<Int>()
        let publisherCount = 5
        let takerCount = 5
        let iterationsPerActor = 100
        let totalRange = 0..<(publisherCount * iterationsPerActor)

        let ends = Async.Channel<Int>.Unbounded().take().ends()

        await withTaskGroup(of: Void.self) { group in

            for p in 0..<publisherCount {
                group.addTask {
                    let base = p * iterationsPerActor
                    for j in 0..<iterationsPerActor {
                        publication.publish(base + j)
                        await Task.yield()
                    }
                }
            }

            for _ in 0..<takerCount {
                group.addTask { [sender = ends.sender] in
                    for _ in 0..<iterationsPerActor {
                        if let value = publication.take() {
                            try? sender.send(value)
                        }
                        await Task.yield()
                    }
                }
            }
        }

        ends.close()

        var observed: [Int] = []
        while let value = try? await ends.receiver.receive() {
            observed.append(value)
        }

        for value in observed {
            #expect(totalRange.contains(value), "Observed inadmissible value: \(value)")
        }

        #expect(!observed.isEmpty, "No values observed under high contention")
    }

    @Test
    func `Cancellation bridge pattern - token race`() async {

        for round in 0..<100 {
            let publication = Async.Publication<Int>()
            let token = round + 1

            let result = await withTaskGroup(of: String.self) { group in

                group.addTask {
                    publication.publish(token)

                    await Task.yield()

                    if let taken = publication.take() {
                        return "operation:\(taken)"
                    }
                    return "operation:lost"
                }

                group.addTask {

                    await Task.yield()

                    if let taken = publication.take() {
                        return "cancel:\(taken)"
                    }
                    return "cancel:lost"
                }

                var outcomes: [String] = []
                for await outcome in group {
                    outcomes.append(outcome)
                }
                return outcomes
            }

            let claimers = result.filter { !$0.hasSuffix(":lost") }
            #expect(
                claimers.count == 1,
                "Expected exactly 1 claimer, got \(claimers.count) in round \(round): \(result)"
            )

            if let winner = claimers.first {
                #expect(winner.hasSuffix(":\(token)"), "Winner claimed wrong token: \(winner)")
            }
        }
    }
}
