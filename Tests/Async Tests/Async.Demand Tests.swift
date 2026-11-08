import Async_Test_Support
import Testing

enum Demand {
    enum Test {
        @Suite struct `Demand operations preserve their basic behavior` {}
        @Suite struct `Demand operations preserve boundary behavior` {}
    }
}

extension Demand.Test.`Demand operations preserve their basic behavior` {

    @Test
    func `fulfill consumes exactly the requested count`() {
        var demand = Async.Demand.count(3)
        let first = demand.fulfill()
        let second = demand.fulfill()
        let third = demand.fulfill()
        let fourth = demand.fulfill()
        #expect(first)
        #expect(second)
        #expect(third)
        #expect(!fourth)
        #expect(demand.isNone)
    }

    @Test
    func `release returns outstanding demand and zeroes`() {
        var demand = Async.Demand.count(5)
        let released = demand.release()
        #expect(released == .count(5))
        #expect(demand.isNone)
        let secondRelease = demand.release()
        #expect(secondRelease == .none)
        let fulfilled = demand.fulfill()
        #expect(!fulfilled)
    }

    @Test
    func `unlimited fulfills without counting`() {
        var demand = Async.Demand.unlimited
        for _ in 0..<1000 {
            let fulfilled = demand.fulfill()
            #expect(fulfilled)
        }
        #expect(demand.isUnlimited)
        #expect(demand.count == nil)
    }

    @Test
    func `adding accumulates`() {
        var demand = Async.Demand.none
        demand.add(.count(2))
        demand.add(.count(3))
        #expect(demand == .count(5))
        #expect(demand.count == 5)
    }

    @Test
    func `unlimited absorbs`() {
        #expect(Async.Demand.unlimited.adding(.count(1)) == .unlimited)
        #expect(Async.Demand.count(1).adding(.unlimited) == .unlimited)
        #expect(Async.Demand.unlimited.subtracting(.count(9)) == .unlimited)
        #expect(Async.Demand.count(9).subtracting(.unlimited) == .none)
    }

    @Test
    func `comparable ordering`() {
        #expect(Async.Demand.none < .count(1))
        #expect(Async.Demand.count(1) < .count(2))
        #expect(Async.Demand.count(.max) < .unlimited)
        #expect(Async.Demand.none < .unlimited)
    }
}

extension Demand.Test.`Demand operations preserve boundary behavior` {

    @Test
    func `zero count is none`() {
        #expect(Async.Demand.count(0) == .none)
        #expect(Async.Demand.count(0).isNone)
        #expect(!Async.Demand.count(0).isUnlimited)
    }

    @Test
    func `finite addition saturates below unlimited`() {
        let maximum = Async.Demand.count(Async.Demand.maximumFiniteCount)
        let saturated = maximum.adding(.count(1))
        #expect(saturated == maximum)
        #expect(!saturated.isUnlimited)
        #expect(Async.Demand.count(.max) == maximum)
        let doubled = maximum.adding(maximum)
        #expect(doubled == maximum)
        #expect(!doubled.isUnlimited)
    }

    @Test
    func `subtraction saturates at none`() {
        #expect(Async.Demand.count(2).subtracting(.count(5)) == .none)
        #expect(Async.Demand.none.subtracting(.count(1)) == .none)
    }
}
