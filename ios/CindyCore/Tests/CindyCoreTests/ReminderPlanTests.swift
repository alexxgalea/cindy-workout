import XCTest
import CindyCore

/// The reminder from the setting to the requests handed to the system. Port of `ReminderDeliveryTest.kt`
/// (10 tests): Android's alarm and receiver become a plan made beforehand, because iOS runs no code
/// when a notification fires, so each test reads the plan where the Kotlin read the alarm manager and
/// the notifications posted.
final class ReminderPlanTests: XCTestCase {

    private let zone = Zone("Europe/Bucharest")
    private let monday = DayOfWeek.monday

    private func at(_ iso: String, _ hour: Int, _ minute: Int = 0) -> ZonedDateTime {
        ZonedDateTime.of(LocalDate(parse: iso)!, hour: hour, minute: minute, zone: zone)
    }

    private func attempt(_ iso: String, hour: Int = 12) -> Attempt {
        Attempt(rounds: 3, reps: 4, atMillis: zone.epochMs(LocalDate(parse: iso)!, hour: hour), durationMs: 20 * 60_000)
    }

    private func plan(_ now: ZonedDateTime, minute: Int = 18 * 60, on: Bool = true,
                      access: NotificationAccess = .allowed, _ attempts: [Attempt] = []) -> [PlannedReminder] {
        ReminderPlan.plan(now: now, minuteOfDay: minute, on: on, access: access, attempts: attempts,
                          firstDayOfWeek: monday)
    }

    // MARK: arming

    /// turning the reminder on arms the first one at the chosen time
    func testTurningTheReminderOnArmsTheFirstAtTheChosenTime() {
        let planned = plan(at("2026-09-09", 9))
        XCTAssertEqual(planned.first?.fireAtMs, at("2026-09-09", 18).epochMs)
        XCTAssertEqual(planned.first?.minuteOfDay, 18 * 60)
    }

    /// a week of them, one a day, each with a stable id
    func testAWeekOfThemOneADayEachWithAStableId() {
        let planned = plan(at("2026-09-09", 9))
        XCTAssertEqual(planned.count, ReminderPlan.days)
        XCTAssertEqual(planned.map { $0.id }.first, "reminder-2026-09-09")
        XCTAssertEqual(planned.map { $0.id }.last, "reminder-2026-09-15")
        XCTAssertEqual(Set(planned.map { $0.id }).count, ReminderPlan.days, "no id twice")
        for (a, b) in zip(planned, planned.dropFirst()) {
            XCTAssertEqual(b.fireAtMs - a.fireAtMs, 24 * 3_600_000, accuracy: 3_600_000, "a day apart, give or take a clock change")
        }
    }

    /// opening the app does not postpone a reminder that is due: planning again later the same day
    /// holds the same requests
    func testOpeningTheAppDoesNotPostponeAReminderThatIsDue() {
        let morning = plan(at("2026-09-09", 9))
        let afternoon = plan(at("2026-09-09", 17, 59))
        XCTAssertEqual(morning, afternoon)
    }

    /// once the time has passed, today's goes and the week starts tomorrow
    func testOnceTheTimeHasPassedTheWeekStartsTomorrow() {
        let planned = plan(at("2026-09-09", 18, 5))
        XCTAssertEqual(planned.first?.id, "reminder-2026-09-10")
        XCTAssertEqual(planned.count, ReminderPlan.days)
    }

    /// opening the app arms a reminder when none is armed: planning from nothing gives the week
    func testOpeningTheAppArmsAReminderWhenNoneIsArmed() {
        XCTAssertFalse(plan(at("2026-09-09", 9)).isEmpty)
    }

    /// turning it off cancels them all
    func testTurningItOffCancelsThemAll() {
        XCTAssertFalse(plan(at("2026-09-09", 9)).isEmpty)
        XCTAssertTrue(plan(at("2026-09-09", 9), on: false).isEmpty)
    }

    // MARK: what each says

    /// a day with no session gets a reminder, with the words Reminder gives for that day
    func testADayWithNoSessionGetsAReminder() {
        let planned = plan(at("2026-09-09", 9))
        XCTAssertEqual(planned.first?.message, Reminder.message([], today: LocalDate(2026, 9, 9), zone: zone,
                                                               firstDayOfWeek: monday))
        XCTAssertEqual(planned.first?.message.title, "Time for your first Cindy")
    }

    /// a day already trained stays quiet but the days after it are still planned
    func testADayAlreadyTrainedStaysQuietButTheRestAreStillPlanned() {
        let planned = plan(at("2026-09-09", 9), [attempt("2026-09-09", hour: 8)])
        XCTAssertFalse(planned.contains { $0.id == "reminder-2026-09-09" }, "today is trained")
        XCTAssertEqual(planned.first?.id, "reminder-2026-09-10")
        XCTAssertEqual(planned.count, ReminderPlan.days - 1)
    }

    /// tomorrow's message knows today was trained: the streak is at risk, and says so
    func testTomorrowKnowsTodayWasTrained() {
        let planned = plan(at("2026-09-09", 9), [attempt("2026-09-08"), attempt("2026-09-09", hour: 8)])
        XCTAssertEqual(planned.first?.message.title, "Keep your 2-day streak going")
        XCTAssertEqual(planned.first?.day, LocalDate(2026, 9, 10))
    }

    /// a session saved today takes today's request away when the plan is made again
    func testASavedSessionTakesTodaysRequestAway() {
        let before = plan(at("2026-09-09", 9))
        XCTAssertTrue(before.contains { $0.id == "reminder-2026-09-09" })
        let after = plan(at("2026-09-09", 10), [attempt("2026-09-09", hour: 10)])
        XCTAssertFalse(after.contains { $0.id == "reminder-2026-09-09" })
    }

    // MARK: permission, the live workout and the clock

    /// without permission nothing is scheduled; once it is given, planning again schedules the week
    func testWithoutPermissionNothingIsScheduledUntilItIsGiven() {
        XCTAssertTrue(plan(at("2026-09-09", 9), access: .refused).isEmpty)
        XCTAssertTrue(plan(at("2026-09-09", 9), access: .undecided).isEmpty)
        XCTAssertEqual(plan(at("2026-09-09", 9), access: .allowed).count, ReminderPlan.days)
    }

    /// a live workout silences it
    func testALiveWorkoutSilencesIt() {
        XCTAssertFalse(ReminderPlan.showsInApp(liveWorkout: true))
        XCTAssertTrue(ReminderPlan.showsInApp(liveWorkout: false))
    }

    /// a time zone change plans the week again at the same hour on the wall
    func testATimeZoneChangePlansTheWeekAgain() {
        let home = plan(at("2026-09-09", 9))
        let london = Zone("Europe/London")
        let there = ReminderPlan.plan(now: ZonedDateTime(epochMs: at("2026-09-09", 9).epochMs, zone: london),
                                      minuteOfDay: 18 * 60, on: true, access: .allowed, attempts: [],
                                      firstDayOfWeek: monday)
        XCTAssertEqual(there.first?.minuteOfDay, 18 * 60)
        XCTAssertNotEqual(home.first?.fireAtMs, there.first?.fireAtMs, "6 pm in London is not 6 pm in Bucharest")
        XCTAssertEqual(there.first?.fireAtMs, london.epochMs(LocalDate(2026, 9, 9), hour: 18, minute: 0))
    }

    /// a clock change keeps the hour on the wall
    func testAClockChangeKeepsTheHourOnTheWall() {
        // Europe/Bucharest falls back on 2026-10-25.
        let planned = plan(at("2026-10-22", 9))
        XCTAssertEqual(planned.count, ReminderPlan.days)
        XCTAssertTrue(planned.allSatisfy { $0.minuteOfDay == 18 * 60 }, "every day at six, either side of the change")
    }

    // MARK: the sheet

    /// turning off asks for nothing; turning on asks once, refuses honestly, and says the time
    func testSavingFollowsPermission() {
        XCTAssertEqual(ReminderPlan.save(on: false, minuteOfDay: 1080, is24Hour: true, access: .refused), .turnedOff)
        XCTAssertEqual(ReminderPlan.save(on: true, minuteOfDay: 1080, is24Hour: true, access: .undecided), .ask)
        XCTAssertEqual(ReminderPlan.save(on: true, minuteOfDay: 1080, is24Hour: true, access: .refused), .refused)
        XCTAssertEqual(ReminderPlan.save(on: true, minuteOfDay: 1080, is24Hour: true, access: .allowed),
                       .set(toast: "Reminder set for 18:00"))
        XCTAssertEqual(ReminderPlan.save(on: true, minuteOfDay: 1080, is24Hour: false, access: .allowed),
                       .set(toast: "Reminder set for 6:00 PM"))
    }

    /// TRY IT sends one when it can, asks first when it has not been asked, and says when it cannot
    func testTryItFollowsPermission() {
        XCTAssertEqual(ReminderPlan.tryIt(access: .undecided), .ask)
        XCTAssertEqual(ReminderPlan.tryIt(access: .allowed), .send)
        XCTAssertEqual(ReminderPlan.tryIt(access: .refused), .refused)
    }

    /// the sheet's words are the Android sheet's
    func testTheSheetsWordsAreAndroids() {
        XCTAssertEqual(ReminderPlan.sheetTitle, "Daily reminder")
        XCTAssertEqual(ReminderPlan.sheetSubtitle, "One nudge at the time you choose, and none on days you've already trained.")
        XCTAssertEqual(ReminderPlan.offTitle, "Notifications are off")
        XCTAssertEqual(ReminderPlan.offSubtitle, "Cindy can't remind you until notifications are allowed for it.")
        XCTAssertEqual(ReminderPlan.timeDescription("18:00"), "Time, 18:00, tap to change")
    }

    /// the menu row is honest when the reminder is on and cannot arrive
    func testTheMenuRowIsHonestWhenItCannotArrive() {
        let profile = Profile(defaults: UserDefaults(suiteName: "ReminderPlanTests.\(UUID().uuidString)")!)
        profile.reminderOn = true
        func subtitle(allowed: Bool) -> String? {
            MenuBuilder.build(MenuInput(profile: profile, attempts: [], zone: zone, firstDayOfWeek: monday,
                                        today: LocalDate(2026, 9, 9), notificationsAllowed: allowed))
                .rows.first { $0.id == .reminder }?.subtitle
        }
        XCTAssertEqual(subtitle(allowed: false), "Blocked \u{2014} notifications are off for Cindy")
        XCTAssertEqual(subtitle(allowed: true), "Daily at 18:00 \u{00B7} not on days you train")
    }
}
