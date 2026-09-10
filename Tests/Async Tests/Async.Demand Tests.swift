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
    func fulfillConsumesExactlyTheRequestedCount() {
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
    func releaseReturnsOutstandingDemandAndZeroes() {
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
    func unlimitedFulfillsWithoutCounting() {
        var demand = Async.Demand.unlimited
        for _ in 0..<1000 {
            let fulfilled = demand.fulfill()
            #expect(fulfilled)
        }
        #expect(demand.isUnlimited)
        #expect(demand.count == nil)
    }

    @Test
    func addingAccumulates() {
        var demand = Async.Demand.none
        demand.add(.count(2))
        demand.add(.count(3))
        #expect(demand == .count(5))
        #expect(demand.count == 5)
    }

    @Test
    func unlimitedAbsorbs() {
        #expect(Async.Demand.unlimited.adding(.count(1)) == .unlimited)
        #expect(Async.Demand.count(1).adding(.unlimited) == .unlimited)
        #expect(Async.Demand.unlimited.subtracting(.count(9)) == .unlimited)
        #expect(Async.Demand.count(9).subtracting(.unlimited) == .none)
    }

    @Test
    func comparableOrdering() {
        #expect(Async.Demand.none < .count(1))
        #expect(Async.Demand.count(1) < .count(2))
        #expect(Async.Demand.count(.max) < .unlimited)
        #expect(Async.Demand.none < .unlimited)
    }
}

extension Demand.Test.`Demand operations preserve boundary behavior` {

    @Test
    func zeroCountIsNone() {
        #expect(Async.Demand.count(0) == .none)
        #expect(Async.Demand.count(0).isNone)
        #expect(!Async.Demand.count(0).isUnlimited)
    }

    @Test
    func finiteAdditionSaturatesBelowUnlimited() {
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
    func subtractionSaturatesAtNone() {
        #expect(Async.Demand.count(2).subtracting(.count(5)) == .none)
        #expect(Async.Demand.none.subtracting(.count(1)) == .none)
    }
}
