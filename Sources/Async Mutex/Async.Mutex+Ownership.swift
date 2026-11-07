#if !hasFeature(Embedded) && canImport(Synchronization)

    import Synchronization

    extension Async.Mutex where Value: ~Copyable {

        @inlinable
        public func withLock<V: ~Copyable & Sendable, T: ~Copyable, E: Swift::Error>(
            consuming value: consuming sending V,
            body: (inout sending Value, consuming V) throws(E) -> sending T
        ) throws(E) -> sending T {
            var slot: V? = value
            return try withLock { (state: inout sending Value) throws(E) -> T in
                guard let value = slot.take() else {
                    preconditionFailure(
                        "Async.Mutex.withLock(consuming:body:): value slot was empty"
                    )
                }
                return try body(&state, value)
            }
        }
    }

    extension Async.Mutex where Value: ~Copyable {

        @inlinable
        public func withLock<V: ~Copyable & Sendable, T: ~Copyable, E: Swift::Error>(
            deposit value: consuming sending V,
            body: (inout sending Value, inout V?) throws(E) -> sending T
        ) throws(E) -> sending T {
            var slot: V? = value
            return try withLock { (state: inout sending Value) throws(E) -> T in
                try body(&state, &slot)
            }
        }
    }

#endif
