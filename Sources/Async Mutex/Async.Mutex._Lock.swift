#if !hasFeature(Embedded) && canImport(Darwin)
    internal import Darwin.os.lock

    extension Async.Mutex where Value: ~Copyable {
        @safe
        @_rawLayout(like: os_unfair_lock_s)
        @usableFromInline
        struct _Lock: ~Copyable, @unchecked Sendable {
            @inlinable package init() {}
        }
    }
#endif
