import XCTest

final class CounterMathTests: XCTestCase {
    func testNormalIncrease() {
        XCTAssertEqual(CounterMath.delta(previous: 1_000, current: 5_000, rebooted: false), 4_000)
    }

    func testWrapAroundFromUpperHalf() {
        // 4,294,000,000 → wraps at 2^32 → 1,000,000
        let delta = CounterMath.delta(previous: 4_294_000_000, current: 1_000_000, rebooted: false)
        XCTAssertEqual(delta, (4_294_967_296 - 4_294_000_000) + 1_000_000)
    }

    func testDecreaseFromLowerHalfIsResetNotWrap() {
        // A wrap from 500 MB would need > 3.5 GB of traffic, so this is a reset.
        XCTAssertEqual(CounterMath.delta(previous: 500_000_000, current: 2_000, rebooted: false), 2_000)
    }

    func testRebootCountsEverythingSinceBoot() {
        // Even if the new value happens to be higher than the old one.
        XCTAssertEqual(CounterMath.delta(previous: 100, current: 9_000, rebooted: true), 9_000)
    }

    func testNewInterfaceCountsFromZero() {
        XCTAssertEqual(CounterMath.delta(previous: nil, current: 7_000, rebooted: false), 7_000)
    }

    func testCountersWrapIndependently() {
        // rx wrapped, tx grew normally: summing first would have hidden the wrap.
        let previous: [String: UInt32] = ["pdp_ip0.rx": 4_294_967_000, "pdp_ip0.tx": 1_000]
        let current: [String: UInt32] = ["pdp_ip0.rx": 704, "pdp_ip0.tx": 1_500]
        XCTAssertEqual(CounterMath.totalDelta(previous: previous, current: current, rebooted: false), 1_000 + 500)
    }

    func testRebootDetection() {
        let boot = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertFalse(CounterMath.didReboot(lastBoot: boot, currentBoot: boot.addingTimeInterval(3),
                                             lastUptime: 100, currentUptime: 200), "clock-sync jitter is not a reboot")
        XCTAssertTrue(CounterMath.didReboot(lastBoot: boot, currentBoot: boot.addingTimeInterval(3_600),
                                            lastUptime: 100, currentUptime: 200))
        XCTAssertTrue(CounterMath.didReboot(lastBoot: boot, currentBoot: boot,
                                            lastUptime: 5_000, currentUptime: 40), "uptime went backwards")
        XCTAssertFalse(CounterMath.didReboot(lastBoot: nil, currentBoot: nil, lastUptime: nil, currentUptime: 1))
    }
}

final class DayMathTests: XCTestCase {
    let cal = TestClock.calendar

    func testSameDayGoesToThatDay() {
        let split = DayMath.split(bytes: 900, from: TestClock.date(10, 9), to: TestClock.date(10, 17), calendar: cal)
        XCTAssertEqual(split.map(\.key), ["2026-10-10"])
        XCTAssertEqual(split.map(\.bytes), [900])
    }

    func testSplitAcrossMidnightIsProportional() {
        // 22:00 → 07:00: 2 h on the 10th, 7 h on the 11th.
        let split = DayMath.split(bytes: 900, from: TestClock.date(10, 22), to: TestClock.date(11, 7), calendar: cal)
        XCTAssertEqual(split.map(\.key), ["2026-10-10", "2026-10-11"])
        XCTAssertEqual(split.map(\.bytes), [200, 700])
    }

    func testSplitAcrossSeveralDaysLosesNoBytes() {
        let split = DayMath.split(bytes: 1_000_003, from: TestClock.date(10, 12), to: TestClock.date(13, 12), calendar: cal)
        XCTAssertEqual(split.count, 4)
        XCTAssertEqual(split.reduce(0) { $0 + $1.bytes }, 1_000_003)
    }

    func testClockGoingBackwardsAssignsToEndDay() {
        let split = DayMath.split(bytes: 50, from: TestClock.date(11, 7), to: TestClock.date(10, 22), calendar: cal)
        XCTAssertEqual(split.map(\.key), ["2026-10-10"])
    }
}

final class BudgetTests: XCTestCase {
    let cal = TestClock.calendar
    let gb = Int64(Budget.bytesPerGB)

    func settings() -> BudgetSettings {
        var s = BudgetSettings()
        s.bundleSizeGB = 217
        s.durationDays = 90
        s.startDate = TestClock.date(1, 0)
        return s
    }

    func testDefaultBudgetIsBundleOverDuration() {
        let budget = Budget.dailyBudget(settings(), bundleUsed: 0, todayUsed: 0, now: TestClock.date(1, 12), calendar: cal)
        XCTAssertEqual(Double(budget) / Double(gb), 217.0 / 90.0, accuracy: 0.001)
    }

    func testBudgetAdaptsToUnderUse() {
        // Day 11 (80 days left), only 10 GB used so far → (217-10)/80 ≈ 2.59 GB.
        let budget = Budget.dailyBudget(settings(), bundleUsed: 10 * gb, todayUsed: 0, now: TestClock.date(11, 8), calendar: cal)
        XCTAssertEqual(Double(budget) / Double(gb), 207.0 / 80.0, accuracy: 0.001)
    }

    func testTodaysUsageDoesNotShrinkTodaysBudget() {
        let morning = Budget.dailyBudget(settings(), bundleUsed: 10 * gb, todayUsed: 0, now: TestClock.date(11, 8), calendar: cal)
        let evening = Budget.dailyBudget(settings(), bundleUsed: 12 * gb, todayUsed: 2 * gb, now: TestClock.date(11, 20), calendar: cal)
        XCTAssertEqual(morning, evening)
    }

    func testDaysLeft() {
        XCTAssertEqual(Budget.daysLeft(settings(), now: TestClock.date(1, 12), calendar: cal), 90)
        XCTAssertEqual(Budget.daysLeft(settings(), now: TestClock.date(31, 12), calendar: cal), 60)
        // 90 days from Oct 1 runs through Dec 29 (day 90); Dec 30 is past the end.
        XCTAssertEqual(Budget.daysLeft(settings(), now: TestClock.date(90, 12), calendar: cal), 1)
        XCTAssertEqual(Budget.daysLeft(settings(), now: TestClock.date(91, 12), calendar: cal), 0)
    }

    func testFixedBudget() {
        var s = settings()
        s.useFixedBudget = true
        s.fixedDailyBudgetGB = 2
        XCTAssertEqual(Budget.dailyBudget(s, bundleUsed: 100 * gb, todayUsed: 0, now: TestClock.date(5, 0), calendar: cal), 2 * gb)
    }

    func testPace() {
        let s = settings()
        // Noon on day 46 (45.5 of 90 days elapsed): even pace is 217 × 45.5/90 ≈ 109.7 GB.
        let noon = TestClock.date(46, 12)
        let expected = Double(217 * gb) * 45.5 / 90
        let under = Budget.pace(s, bundleUsed: 100 * gb, now: noon, calendar: cal)!
        XCTAssertEqual(Double(under), expected - Double(100 * gb), accuracy: 1_000)
        XCTAssertLessThan(Budget.pace(s, bundleUsed: 120 * gb, now: noon, calendar: cal)!, 0)
        XCTAssertNil(Budget.pace(s, bundleUsed: 0, now: TestClock.date(91, 0), calendar: cal), "after the bundle ends")
        XCTAssertNil(Budget.pace(s, bundleUsed: 0, now: TestClock.date(0, 12), calendar: cal), "before it starts")
    }

    func testSettingsDecodeWithoutNewFieldsKeepsDefaults() throws {
        // A settings blob saved before `isSetUp` existed must still decode.
        let old = #"{"bundleSizeGB":100,"durationDays":30}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(BudgetSettings.self, from: old)
        XCTAssertEqual(decoded.bundleSizeGB, 100)
        XCTAssertEqual(decoded.warningPercent, 80)
        XCTAssertFalse(decoded.isSetUp)
    }

    func testThresholds() {
        XCTAssertEqual(Budget.newlyCrossedThresholds(todayUsed: 79, budget: 100, thresholds: [80, 100], alreadyAlerted: []), [])
        XCTAssertEqual(Budget.newlyCrossedThresholds(todayUsed: 80, budget: 100, thresholds: [80, 100], alreadyAlerted: []), [80])
        XCTAssertEqual(Budget.newlyCrossedThresholds(todayUsed: 150, budget: 100, thresholds: [80, 100], alreadyAlerted: [80]), [100])
        XCTAssertEqual(Budget.newlyCrossedThresholds(todayUsed: 150, budget: 0, thresholds: [80, 100], alreadyAlerted: []), [])
    }
}

final class TrackerEngineTests: XCTestCase {
    let cal = TestClock.calendar
    let boot = Date(timeIntervalSince1970: 1_790_000_000)

    var settings: BudgetSettings {
        var s = BudgetSettings()
        s.startDate = TestClock.date(1, 0)
        s.bundleSizeGB = 1   // 1 GiB budget over 90 days keeps numbers small
        s.durationDays = 90
        return s
    }

    func reading(_ rx: UInt32, _ tx: UInt32, at date: Date, boot: Date? = nil, uptime: TimeInterval = 1_000) -> CounterReading {
        CounterReading(counters: ["pdp_ip0.rx": rx, "pdp_ip0.tx": tx], bootTime: boot ?? self.boot, uptime: uptime, date: date)
    }

    func testFirstReadingIsBaselineOnly() {
        var state = TrackerState()
        TrackerEngine.ingest(reading(3_000_000_000, 5_000, at: TestClock.date(10, 9)), into: &state, settings: settings, calendar: cal)
        XCTAssertEqual(state.bundleUsedBytes, 0)
        XCTAssertEqual(state.days["2026-10-10"]?.bytes, 0)
    }

    func testAccumulatesAcrossWrapAndReboot() {
        var state = TrackerState()
        let s = settings
        TrackerEngine.ingest(reading(4_294_000_000, 1_000, at: TestClock.date(10, 9), uptime: 1_000), into: &state, settings: s, calendar: cal)
        // rx wraps: +967,296 + 33,000 = 1,000,296; tx +500
        TrackerEngine.ingest(reading(33_000, 1_500, at: TestClock.date(10, 10), uptime: 4_600), into: &state, settings: s, calendar: cal)
        XCTAssertEqual(state.bundleUsedBytes, 1_000_796)

        // Reboot at 12:00, reading at 13:00 with fresh small counters → all of it counts.
        let newBoot = TestClock.date(10, 12)
        TrackerEngine.ingest(reading(20_000, 4_000, at: TestClock.date(10, 13), boot: newBoot, uptime: 3_600),
                             into: &state, settings: s, calendar: cal)
        XCTAssertEqual(state.bundleUsedBytes, 1_000_796 + 24_000)
        XCTAssertEqual(state.days["2026-10-10"]?.bytes, 1_024_796)
    }

    func testMidnightRolloverKeepsHistoryAndStartsNewDay() {
        var state = TrackerState()
        let s = settings
        TrackerEngine.ingest(reading(0, 0, at: TestClock.date(10, 22), uptime: 100), into: &state, settings: s, calendar: cal)
        TrackerEngine.ingest(reading(900, 0, at: TestClock.date(11, 7), uptime: 32_500), into: &state, settings: s, calendar: cal)
        XCTAssertEqual(state.days["2026-10-10"]?.bytes, 200)
        XCTAssertEqual(state.days["2026-10-11"]?.bytes, 700)

        let snap = TrackerEngine.snapshot(of: state, settings: s, now: TestClock.date(11, 8), calendar: cal)
        XCTAssertEqual(snap.todayBytes, 700)
        XCTAssertEqual(snap.history.count, 14)
        XCTAssertEqual(snap.history.last?.key, "2026-10-11")
        XCTAssertEqual(snap.history[12].bytes, 200)
    }

    func testUsageBeforeBundleStartIsNotCountedAgainstBundle() {
        var state = TrackerState()
        var s = settings
        s.startDate = TestClock.date(11, 0)
        TrackerEngine.ingest(reading(0, 0, at: TestClock.date(10, 22), uptime: 100), into: &state, settings: s, calendar: cal)
        TrackerEngine.ingest(reading(900, 0, at: TestClock.date(11, 7), uptime: 32_500), into: &state, settings: s, calendar: cal)
        XCTAssertEqual(state.bundleUsedBytes, 700)
    }

    func testAlertsFireOncePerThresholdPerDay() {
        var state = TrackerState()
        var s = settings
        s.useFixedBudget = true
        s.fixedDailyBudgetGB = 1
        let gb = UInt32(Budget.bytesPerGB)

        TrackerEngine.ingest(reading(0, 0, at: TestClock.date(10, 8), uptime: 100), into: &state, settings: s, calendar: cal)
        TrackerEngine.ingest(reading(gb / 100 * 81, 0, at: TestClock.date(10, 12), uptime: 200), into: &state, settings: s, calendar: cal)
        XCTAssertEqual(TrackerEngine.takeAlerts(from: &state, settings: s, now: TestClock.date(10, 12), calendar: cal), [80])
        XCTAssertEqual(TrackerEngine.takeAlerts(from: &state, settings: s, now: TestClock.date(10, 13), calendar: cal), [])

        TrackerEngine.ingest(reading(gb + 1, 0, at: TestClock.date(10, 18), uptime: 300), into: &state, settings: s, calendar: cal)
        XCTAssertEqual(TrackerEngine.takeAlerts(from: &state, settings: s, now: TestClock.date(10, 18), calendar: cal), [100])
        XCTAssertEqual(TrackerEngine.takeAlerts(from: &state, settings: s, now: TestClock.date(10, 19), calendar: cal), [])

        // Next day: fresh slate, usage 0 → nothing yet.
        TrackerEngine.ingest(reading(gb + 1, 0, at: TestClock.date(11, 9), uptime: 400), into: &state, settings: s, calendar: cal)
        XCTAssertEqual(TrackerEngine.takeAlerts(from: &state, settings: s, now: TestClock.date(11, 9), calendar: cal), [])
        XCTAssertEqual(state.alertedThresholds, [])
    }
}

final class UsageTrackerTests: XCTestCase {
    func testPersistsThroughStoreAndCorrection() {
        let suite = "DataTrackerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        var counter: UInt32 = 1_000
        var uptime: TimeInterval = 10
        let tracker = UsageTracker(store: UsageStore(defaults: defaults, lockURL: nil),
                                   readCounters: {
                                       CounterReading(counters: ["pdp_ip0.rx": counter], bootTime: Date(timeIntervalSince1970: 1),
                                                      uptime: uptime, date: Date())
                                   })
        tracker.refresh(evaluateAlerts: false)
        counter += 4_000
        uptime += 60
        let result = tracker.refresh(evaluateAlerts: false)
        XCTAssertEqual(result.snapshot.bundleUsedBytes, 4_000)

        XCTAssertFalse(tracker.settings.isSetUp)
        tracker.setBundleUsed(bytes: 50 * Int64(Budget.bytesPerGB))
        XCTAssertTrue(tracker.settings.isSetUp, "entering usage so far completes setup")
        counter += 1_000
        uptime += 60
        XCTAssertEqual(tracker.refresh(evaluateAlerts: false).snapshot.bundleUsedBytes, 50 * Int64(Budget.bytesPerGB) + 1_000)
    }
}

/// Fixed time zone and dates so tests don't depend on where they run.
enum TestClock {
    static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Africa/Accra")!
        return c
    }()

    /// Day `day` counted from Oct 1, 2026 (day 1), at `hour`:00.
    static func date(_ day: Int, _ hour: Int) -> Date {
        let start = calendar.date(from: DateComponents(year: 2026, month: 10, day: 1))!
        return calendar.date(byAdding: DateComponents(day: day - 1, hour: hour), to: start)!
    }
}
