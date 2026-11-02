import Testing
@testable import StarCatalog

@Suite struct SimulationClockTests {
    @Test func advancesByElapsedSecondsTimesTheSelectedSpeed() {
        var clock = SimulationClock(speed: SimulationSpeed(daysPerSecond: 12))
        clock.advance(bySeconds: 0.05)
        #expect(abs(clock.day - 0.6) < 1e-12)
    }

    @Test func pauseAndMaximumStepBoundTheAdvance() {
        var clock = SimulationClock(speed: .year)
        clock.isPaused = true
        clock.advance(bySeconds: 0.05)
        #expect(clock.day == 0)
        clock.isPaused = false
        clock.advance(bySeconds: 5)
        #expect(abs(clock.day - SimulationClock.maximumStep * SimulationSpeed.year.daysPerSecond) < 1e-12)
    }

    @Test(arguments: [-1.0, .nan, .infinity, -.infinity])
    func invalidElapsedSecondsDoNotAdvance(seconds: Double) {
        var clock = SimulationClock(speed: .year)
        clock.advance(bySeconds: seconds)
        #expect(clock.day == 0)
    }

    @Test func speedClampsAndNaNFallsBackToOneDayPerSecond() {
        #expect(SimulationSpeed(daysPerSecond: 0).daysPerSecond == 1)
        #expect(SimulationSpeed(daysPerSecond: -100).daysPerSecond == 1)
        #expect(SimulationSpeed(daysPerSecond: .nan).daysPerSecond == 1)
        #expect(SimulationSpeed(daysPerSecond: 400).daysPerSecond == Astrophysics.daysPerYear)
        #expect(SimulationSpeed(daysPerSecond: .infinity).daysPerSecond == Astrophysics.daysPerYear)
    }

    @Test func presetsAndDisplayNamesMatchTheFourSpeeds() {
        #expect(SimulationSpeed.presets == [.day, .week, .month, .year])
        #expect(SimulationSpeed.presets.map(\.daysPerSecond) == [1, 7, Astrophysics.daysPerYear / 12, Astrophysics.daysPerYear])
        #expect(SimulationSpeed.presets.map(\.displayName) == ["1 day", "1 week", "1 month", "1 year"])
        #expect(SimulationSpeed(daysPerSecond: 3).displayName == "3 days")
    }

    @Test func defaultClockStartsRunningAtOneWeekPerSecond() {
        let clock = SimulationClock()
        #expect(clock.day == 0)
        #expect(clock.speed == .week)
        #expect(!clock.isPaused)
    }
}
