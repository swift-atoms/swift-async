# swift-async

Use this package when you are building a concurrency type yourself and need its small parts: a lock, a one-shot value that several waiters await, a cancellation source with handlers, a single-slot hand-off, a demand counter, a guarded completion state machine, or a lazy async computation. Everything lives under the `Async` namespace; import `Async` for all of it or one module (`Async_Promise`, `Async_Cancellation`, …) for one part. To pass a stream of values between tasks, use swift-async-channel instead.

## Model

- `Async.Mutex<Value: ~Copyable>`: a value guarded by a lock. `withLock` runs a closure with `inout` access and returns its result; `withLockIfAvailable` returns `nil` instead of waiting. `withLock(consuming:body:)` and `withLock(deposit:body:)` move a value into the critical section.
- `Async.Promise<Value>` (class): a value fulfilled once. `fulfill(_:)` returns whether this call set it; `wait(_:)` takes a callback; `value()` suspends until fulfilled; `isFulfilled` and `fulfilled` read the state. `Async.Gate` is `Async.Promise<Void>` with `open()`, `wait()` and `isOpen`.
- `Async.Cancellation.Source` (class) owns the state; `source.token` is an `Async.Cancellation.Token` value that observes it (`isCancelled`, `checkCancellation()`, `onCancel(_:)`). `onCancel(_:)` returns an `Async.Cancellation.Registration` whose `deregister()` returns whether it removed the handler. `Async.Cancellation.State` is the bare `active`/`cancelled` value.
- `Async.Publication<Value>` (class): one slot. `publish(_:)` overwrites it; `take()` returns the value and empties the slot.
- `Async.Demand` (value): a backpressure count, `.none`, `.count(n)` or `.unlimited`, with `adding`/`add`, `subtracting`, `fulfill()` (consume one) and `release()` (return all, reset to `.none`).
- `Async.Completion<Success, Failure>` (class): an atomic state machine (`Async.Completion.State`: `pending`, `running`, `completed`, `timedOut`, `cancelled`, `failed`) that resumes a `CheckedContinuation<Async.Completion.Result, Never>` registered with `set(continuation:)` when it reaches a terminal state.
- `Async.Lifecycle.State` (`open`, `closing`, `closed`) moves forward through `state.shutdown.begin()` and `state.shutdown.complete()`.
- `Async.Precedence.resolve(...)` picks one outcome from the shutdown, cancelled and timed-out flags.
- `Async.Callback<Value>` (value): a deferred `async` computation, called as `callback()`, composed with `map` and `flatMap`. `init(wrapping:)` bridges a completion-handler API.
- `Async.Continuation<T>` resumes either a `CheckedContinuation` or a callback; `Async.Continuation.Unsafe` wraps an `UnsafeContinuation` and is `~Copyable`, so `resume(returning:)` consumes it.

## Rules

- `Async.Mutex` is not reentrant. Under Embedded Swift, or with none of Darwin, Synchronization or Kernel_Thread available, it is a plain box with no locking, for single-threaded use.
- `Async.Promise`: the first `fulfill` wins and later calls return `false`. Every waiter gets the value; a `wait` after fulfillment runs its callback at once on the caller. `value()` ignores task cancellation: a cancelled awaiter still waits for, and receives, the value.
- `Async.Cancellation.Source.cancel()` returns `true` exactly once, even under concurrent callers. Handlers run once, in registration order, outside the lock, and may call back into the source. A handler registered after cancellation runs immediately, and its registration's `deregister()` returns `false`.
- `Async.Publication`: the latest `publish` wins, and concurrent `take()` calls yield the value to exactly one caller.
- `Async.Demand` saturates: finite counts clamp to `maximumFiniteCount`, `.unlimited` absorbs addition and survives `subtracting`, subtracting `.unlimited` or more than is left gives `.none`, and `fulfill()` on `.none` returns `false`. Ordering puts `.unlimited` above every count.
- `Async.Completion` allows only `start()` pending→running; `complete`, `timeout` running→terminal; `cancel()` from pending or running; `fail` from pending only. Every other call throws. Call `set(continuation:)` before the terminal transition: a continuation set afterwards is never resumed.
- `Async.Lifecycle.State`: `begin()` only from `open`, `complete()` only from `closing`; otherwise they return `false` and leave the state unchanged, so `closing` cannot be skipped.
- `Async.Precedence`: shutdown beats cancelled beats timeout beats success; only the chosen outcome is evaluated.
- `Async.Callback` runs nothing until called, runs again on every call, and runs in the caller's isolation. The function passed to `init(wrapping:)` must call its completion exactly once.
- Under Embedded Swift there is no `Async.Completion`, `Async.Continuation.Unsafe`, `Async.Promise.value()`, `Async.Gate.wait()`, `Async.Callback(wrapping:)`, `withLock(consuming:body:)` or `withLock(deposit:body:)`.

## Error Handling

- `Async.Cancellation.Error.cancelled`: thrown by `Async.Cancellation.Token.checkCancellation()` once the source is cancelled.
- `Async.Completion.Transition.Error.alreadyDone`: thrown by `Async.Completion`'s `start`, `complete`, `timeout`, `cancel` and `fail` when the transition is not allowed from the current state.
- `Async.Completion.Error` (`timeout`, `cancelled`, `failure(Failure)`): the failure side of `Async.Completion.Result`, delivered to the continuation.
- `Async.Lifecycle.Error` (`shutdown`, `cancelled`, `timeout`): for a type built on `Async.Lifecycle` to throw; its `description` is the case name.

## Example

```swift
let promise = Async.Promise<Int>()
let publication = Async.Publication<Int>()
promise.wait { publication.publish($0) }
publication.take()       // nil: not fulfilled yet
promise.fulfill(99)      // true
promise.fulfill(1)       // false: the first value is kept
publication.take()       // 99
await promise.value()    // 99
```
