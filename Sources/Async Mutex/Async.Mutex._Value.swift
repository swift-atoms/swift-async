#if !hasFeature(Embedded) && canImport(Darwin)
    extension Async.Mutex where Value: ~Copyable {
        @safe
        @_rawLayout(like: Value, movesAsLike)
        @usableFromInline
        struct _Value: ~Copyable {
            @inlinable package init() {}
        }
    }
#endif
