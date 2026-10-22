import _Concurrency

extension Async {

    public struct Callback<Value> {
        @usableFromInline
        let operation: nonisolated(nonsending) () async -> Value

        @inlinable
        public init(
            _ operation: nonisolated(nonsending) @escaping () async -> Value
        ) {
            self.operation = operation
        }
    }
}

extension Async.Callback {

    @inlinable
    public init(value: Value) {
        self.operation = { value }
    }

    @inlinable
    nonisolated(nonsending)
        public func callAsFunction() async -> Value
    {
        await operation()
    }

    @inlinable
    public func map<NewValue>(
        _ transform: @escaping (Value) -> NewValue
    ) -> Async.Callback<NewValue> {
        .init { transform(await self()) }
    }

    @inlinable
    public func flatMap<NewValue>(
        _ transform: @escaping (Value) -> Async.Callback<NewValue>
    ) -> Async.Callback<NewValue> {
        .init { await transform(await self())() }
    }
}

#if !hasFeature(Embedded)
    extension Async.Callback where Value: Sendable {

        @inlinable
        public init(
            wrapping cps:
                @escaping @Sendable (
                    @escaping @Sendable (sending Value) -> Void
                ) -> Void
        ) {
            self.init {
                await withCheckedContinuation { continuation in
                    cps { value in
                        continuation.resume(returning: value)
                    }
                }
            }
        }
    }
#endif
