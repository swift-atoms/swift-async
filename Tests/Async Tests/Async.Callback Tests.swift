import Async_Test_Support
import Testing

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#elseif os(Windows)
    import WinSDK
#endif

private func currentThreadID() -> UInt {
    #if canImport(Darwin)
        UInt(pthread_mach_thread_np(pthread_self()))
    #elseif canImport(Glibc)
        UInt(pthread_self())
    #elseif os(Windows)
        UInt(GetCurrentThreadId())
    #endif
}

private final class Box<T> {
    var value: T
    init(_ value: T) { self.value = value }
}

enum Callback {
    enum Test {
        @Suite struct `Callback operations preserve their basic behavior` {}
        @Suite struct `Callback operations preserve boundary behavior` {}
        @Suite struct `Callback operations compose with their dependencies` {}
        @Suite(.serialized) struct `Callback operations preserve values during repeated execution` {}
    }
}

extension Callback.Test.`Callback operations preserve their basic behavior` {
    @Test
    func `Init with immediate value returns that value`() async {
        let callback = Async.Callback(value: 42)
        #expect(await callback() == 42)
    }

    @Test
    func `Init with deferred computation produces value`() async {
        let callback = Async.Callback<String> { "computed" }
        #expect(await callback() == "computed")
    }

    @Test
    func `Deferred computation does not execute until called`() async {
        var executed = false
        let callback = Async.Callback<Int> {
            executed = true
            return 99
        }
        #expect(!executed)
        let result = await callback()
        #expect(executed)
        #expect(result == 99)
    }

    @Test
    func `Mapping transforms the callback value`() async {
        let callback = Async.Callback(value: 21).map { $0 * 2 }
        #expect(await callback() == 42)
    }

    @Test
    func `Map chains three levels`() async {
        let callback = Async.Callback(value: 10)
            .map { $0 + 5 }
            .map { "v=\($0)" }
            .map { $0.count }
        #expect(await callback() == 4)
    }

    @Test
    func `Flat mapping chains callback computations`() async {
        let callback = Async.Callback(value: 7)
            .flatMap { v in Async.Callback(value: "r=\(v * 6)") }
        #expect(await callback() == "r=42")
    }

    @Test
    func `FlatMap chains multiple levels`() async {
        let callback = Async.Callback(value: 1)
            .flatMap { v in Async.Callback(value: v + 10) }
            .flatMap { v in Async.Callback(value: v * 2) }
        #expect(await callback() == 22)
    }

    @Test
    func `Non-Sendable value produced inside callback`() async {
        let callback = Async.Callback<Box<String>> { Box("hello") }
        let result = await callback()
        #expect(result.value == "hello")
    }

    @Test
    func `Non-Sendable value through map`() async {
        let callback = Async.Callback<Box<Int>> { Box(21) }
            .map { "\($0.value * 2)" }
        #expect(await callback() == "42")
    }

    #if !hasFeature(Embedded)
        @Test
        func `Init wrapping bridges CPS completion handler`() async {
            let callback = Async.Callback<Int>(wrapping: { completion in
                completion(42)
            })
            #expect(await callback() == 42)
        }
    #endif
}

extension Callback.Test.`Callback operations preserve boundary behavior` {
    @Test
    func `Void callback completes without value`() async {
        var flag = false
        let callback = Async.Callback<Void> {
            flag = true
        }
        await callback()
        #expect(flag)
    }

    @Test
    func `Nested callback flattened via flatMap`() async {
        let inner = Async.Callback(value: 42)
        let outer = Async.Callback(value: ()).flatMap { _ in inner }
        #expect(await outer() == 42)
    }

    @Test
    func `Identity map preserves value`() async {
        let callback = Async.Callback(value: "unchanged").map { $0 }
        #expect(await callback() == "unchanged")
    }

    @Test
    func `Multiple invocations produce independent results`() async {
        var counter = 0
        let callback = Async.Callback<Int> {
            counter += 1
            return counter
        }
        let first = await callback()
        let second = await callback()
        #expect(first == 1)
        #expect(second == 2)
    }

    @Test
    func `FlatMap left identity — wrapping then chaining equals direct application`() async {
        let f: (Int) -> Async.Callback<String> = { v in .init(value: "n=\(v)") }
        let lhs = Async.Callback(value: 5).flatMap(f)
        let rhs = f(5)
        let lhsResult = await lhs()
        let rhsResult = await rhs()
        #expect(lhsResult == rhsResult)
    }

    @Test
    func `FlatMap right identity — chaining with init(value:) is identity`() async {
        let callback = Async.Callback(value: 42)
        let chained = callback.flatMap { Async.Callback(value: $0) }
        let lhs = await chained()
        let rhs = await callback()
        #expect(lhs == rhs)
    }

    #if !hasFeature(Embedded)
        @Test
        func `CPS bridge with asynchronous completion`() async {
            let callback = Async.Callback<String>(wrapping: { completion in
                Task.detached {
                    completion("delayed")
                }
            })
            #expect(await callback() == "delayed")
        }
    #endif
}

extension Callback.Test.`Callback operations compose with their dependencies` {
    @Test @MainActor
    func `Init closure preserves MainActor isolation`() async {
        let mainThreadID = currentThreadID()
        let callback = Async.Callback<Bool> { currentThreadID() == mainThreadID }
        #expect(await callback())
    }

    @Test @MainActor
    func `Map transform preserves MainActor isolation`() async {
        let mainThreadID = currentThreadID()
        let callback = Async.Callback(value: 21)
            .map { _ -> Bool in currentThreadID() == mainThreadID }
        #expect(await callback())
    }

    @Test @MainActor
    func `Chained maps preserve isolation at each level`() async {
        let mainThreadID = currentThreadID()
        let callback = Async.Callback(value: 0)
            .map { _ -> Bool in currentThreadID() == mainThreadID }
            .map { level1 -> (Bool, Bool) in (level1, currentThreadID() == mainThreadID) }
        let (level1, level2) = await callback()
        #expect(level1)
        #expect(level2)
    }

    @Test @MainActor
    func `Flat mapping preserves caller isolation`() async {
        let mainThreadID = currentThreadID()
        let callback = Async.Callback(value: 0)
            .flatMap { _ in Async.Callback(value: currentThreadID() == mainThreadID) }
        #expect(await callback())
    }

    @Test @MainActor
    func `Caller remains on MainActor after awaiting callback`() async {
        let mainThreadID = currentThreadID()
        let callback = Async.Callback(value: 42)
        let result = await callback()
        #expect(result == 42)
        #expect(currentThreadID() == mainThreadID)
    }

    #if !hasFeature(Embedded)
        @Test @MainActor
        func `CPS bridge returns to caller isolation`() async {
            let mainThreadID = currentThreadID()
            let callback = Async.Callback<Int>(wrapping: { completion in
                completion(42)
            })
            let result = await callback()
            #expect(result == 42)
            #expect(currentThreadID() == mainThreadID)
        }
    #endif
}
