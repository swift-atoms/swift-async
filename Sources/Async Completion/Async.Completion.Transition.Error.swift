#if !hasFeature(Embedded)

    extension Async.Completion.Transition {

        public enum Error: Swift::Error, Sendable {

            case alreadyDone
        }
    }

#endif
