#if !hasFeature(Embedded)

    extension Async.Completion {

        public enum Error: Swift::Error, Sendable {

            case timeout

            case cancelled

            case failure(Failure)
        }
    }

#endif
