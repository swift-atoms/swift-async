#if !hasFeature(Embedded) && canImport(Darwin)
    public import Darwin.os.lock

    extension Async {

        public struct Mutex<Value: ~Copyable>: ~Copyable {

            @usableFromInline
            let _lockRaw: _Lock

            @usableFromInline
            let _valueRaw: _Value

            @inlinable
            public init(_ value: consuming sending Value) {
                _lockRaw = _Lock()
                _valueRaw = _Value()
                unsafe _lockPointer().initialize(to: os_unfair_lock_s())
                unsafe _valuePointer().initialize(to: value)
            }
        }
    }

    extension Async.Mutex: @unchecked Sendable where Value: ~Copyable {}

    extension Async.Mutex._Value: @unchecked Sendable where Value: ~Copyable {}

    extension Async.Mutex where Value: ~Copyable {
        @usableFromInline
        func _lockPointer() -> UnsafeMutablePointer<os_unfair_lock_s> {
            withUnsafePointer(to: _lockRaw) { base in
                unsafe UnsafeMutablePointer(
                    mutating: UnsafeRawPointer(base)
                        .assumingMemoryBound(to: os_unfair_lock_s.self)
                )
            }
        }

        @usableFromInline
        func _valuePointer() -> UnsafeMutablePointer<Value> {
            withUnsafePointer(to: _valueRaw) { base in
                unsafe UnsafeMutablePointer(
                    mutating: UnsafeRawPointer(base)
                        .assumingMemoryBound(to: Value.self)
                )
            }
        }

        @usableFromInline
        func _lock() { unsafe os_unfair_lock_lock(_lockPointer()) }

        @usableFromInline
        func _unlock() { unsafe os_unfair_lock_unlock(_lockPointer()) }
    }

    extension Async.Mutex where Value: ~Copyable {

        @inlinable
        public borrowing func withLock<T: ~Copyable, E: Swift::Error>(
            _ body: (inout sending Value) throws(E) -> sending T
        ) throws(E) -> sending T {
            _lock()
            defer { _unlock() }
            return try unsafe body(&_valuePointer().pointee)
        }

        @inlinable
        public borrowing func withLockIfAvailable<T: ~Copyable, E: Swift::Error>(
            _ body: (inout sending Value) throws(E) -> sending T
        ) throws(E) -> sending T? {
            guard unsafe os_unfair_lock_trylock(_lockPointer()) else { return nil }
            defer { _unlock() }
            return try unsafe body(&_valuePointer().pointee)
        }
    }

#elseif !hasFeature(Embedded) && canImport(Synchronization)
    @_exported public import Synchronization

    extension Async {

        public typealias Mutex = Synchronization.Mutex
    }

#elseif !hasFeature(Embedded) && canImport(Kernel_Thread)
    @_exported public import Kernel_Thread

    extension Async {

        public typealias Mutex = Kernel.Thread.Mutex.Value
    }

#else

    extension Async {

        public final class Mutex<Value: ~Copyable>: @unchecked Sendable {
            @usableFromInline
            var _value: Value

            @inlinable
            public init(_ value: consuming sending Value) {
                self._value = value
            }
        }
    }

    extension Async.Mutex where Value: ~Copyable {

        @inlinable
        public func withLock<T: ~Copyable, E: Swift::Error>(
            _ body: (inout sending Value) throws(E) -> sending T
        ) throws(E) -> sending T {
            try body(&_value)
        }

        @inlinable
        public func withLockIfAvailable<T: ~Copyable, E: Swift::Error>(
            _ body: (inout sending Value) throws(E) -> sending T
        ) throws(E) -> sending T? {
            try body(&_value)
        }
    }

#endif
