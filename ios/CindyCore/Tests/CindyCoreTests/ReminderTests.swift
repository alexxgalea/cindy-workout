import XCTest
import CindyCore

/// When the daily reminder fires and what it says. Port of `ReminderTest.kt`.
final class ReminderTests: XCTestCase {

    private let zone = Zone("Europe/Bucharest")
    private let today = LocalDate(2026, 9, 9)
    private let monday = DayOfWeek.monday

    private func attempt(_ iso: String, rounds: Int = 13, reps: Int = 10) -> Attempt {
        Attempt(rounds: rounds, reps: reps, atMillis: zone.epochMs(LocalDate(parse: iso)!, hour: 12), durationMs: 20 * 60_000)
    }

    private func message(_ a: Attempt..., on: LocalDate? = nil) -> Reminder.Message? {
        Reminder.message(a, today: on ?? today, zone: zone, firstDayOfWeek: monday)
    }

    /// `2026-09-09T10:00` in Bucharest.
    private func at(_ iso: String, _ hour: Int, _ minute: Int = 0) -> ZonedDateTime {
        ZonedDateTime.of(LocalDate(parse: iso)!, hour: hour, minute: minute, zone: zone)
    }

    private func millis(_ iso: String, _ hour: Int, _ minute: Int = 0) -> Int64 { at(iso, hour, minute).epochMs }

    // MARK: nextFire

    /// next fire later today when the time has not come
    func testNextFireLaterTodayWhenTheTimeHasNotCome() {
        let next = Reminder.nextFire(at("2026-09-09", 10), minuteOfDay: 18 * 60)
        XCTAssertEqual(next, at("2026-09-09", 18))
    }

    /// next fire is tomorrow when the time has passed
    func testNextFireIsTomorrowWhenTheTimeHasPassed() {
        let next = Reminder.nextFire(at("2026-09-09", 19), minuteOfDay: 18 * 60)
        XCTAssertEqual(next, at("2026-09-10", 18))
    }

    /// next fire is tomorrow when it is exactly the time
    func testNextFireIsTomorrowWhenItIsExactlyTheTime() {
        let next = Reminder.nextFire(at("2026-09-09", 18), minuteOfDay: 18 * 60)
        XCTAssertEqual(next, at("2026-09-10", 18))
    }

    /// next fire moves out of the spring forward gap
    func testNextFireMovesOutOfTheSpringForwardGap() {
        let now = at("2026-03-29", 1)
        XCTAssertEqual(now.offsetSeconds, 2 * 3600)
        let next = Reminder.nextFire(now, minuteOfDay: 3 * 60 + 30)
        XCTAssertEqual(next.hour, 4)
        XCTAssertEqual(next.minute, 30)
        XCTAssertEqual(next.offsetSeconds, 3 * 3600)
        XCTAssertEqual(next.localDate, LocalDate(2026, 3, 29))
    }

    /// next fire picks the earlier offset when fall back repeats the hour
    func testNextFirePicksTheEarlierOffsetWhenFallBackRepeatsTheHour() {
        let now = at("2026-10-25", 1)
        XCTAssertEqual(now.offsetSeconds, 3 * 3600)
        let next = Reminder.nextFire(now, minuteOfDay: 3 * 60 + 30)
        XCTAssertEqual(next.hour, 3)
        XCTAssertEqual(next.minute, 30)
        XCTAssertEqual(next.offsetSeconds, 3 * 3600)
    }

    // MARK: shouldPost

    /// posts on time
    func testPostsOnTime() {
        let t = millis("2026-09-09", 18)
        XCTAssertTrue(Reminder.shouldPost(t, t))
    }

    /// does not post three hours late
    func testDoesNotPostThreeHoursLate() {
        let t = millis("2026-09-09", 18)
        XCTAssertFalse(Reminder.shouldPost(t, t + 3 * 60 * 60 * 1000))
    }

    /// posts just after midnight when still inside the late limit
    func testPostsJustAfterMidnightWhenStillInsideTheLateLimit() {
        let t = millis("2026-09-09", 23, 50)
        XCTAssertTrue(Reminder.shouldPost(t, t + 15 * 60 * 1000))
    }

    /// does not post a day late
    func testDoesNotPostADayLate() {
        let t = millis("2026-09-09", 18)
        XCTAssertFalse(Reminder.shouldPost(t, t + 25 * 60 * 60 * 1000))
    }

    /// posts when thirty seconds early
    func testPostsWhenThirtySecondsEarly() {
        let t = millis("2026-09-09", 18)
        XCTAssertTrue(Reminder.shouldPost(t, t - 30_000))
    }

    /// does not post without a target
    func testDoesNotPostWithoutATarget() {
        XCTAssertFalse(Reminder.shouldPost(0, 1_000))
    }

    // MARK: message

    /// nothing to say when today is already trained
    func testNothingToSayWhenTodayIsAlreadyTrained() {
        XCTAssertNil(message(attempt("2026-09-09")))
    }

    /// first ever reminder invites the first Cindy
    func testFirstEverReminderInvitesTheFirstCindy() {
        let m = message()
        XCTAssertEqual(m?.title, "Time for your first Cindy")
        XCTAssertEqual(m?.body, "Twenty minutes: 5 pull-ups, 10 push-ups, 15 squats, as many rounds as you can.")
    }

    /// a running streak is named and the next number promised
    func testARunningStreakIsNamedAndTheNextNumberPromised() {
        let m = message(attempt("2026-09-07"), attempt("2026-09-08"))
        XCTAssertEqual(m?.title, "Keep your 2-day streak going")
        XCTAssertEqual(m?.body, "Train today and it's 3.")
    }

    /// one day of streak asks for a second
    func testOneDayOfStreakAsksForASecond() {
        let m = message(attempt("2026-09-08"))
        XCTAssertEqual(m?.title, "Make it two days in a row")
        XCTAssertEqual(m?.body, "You trained yesterday. Twenty minutes today starts a streak.")
    }

    /// last day of the week warns about the weekly streak
    func testLastDayOfTheWeekWarnsAboutTheWeeklyStreak() {
        // Sunday; weeks start on Monday; last week and the week before were trained, this not.
        let sunday = LocalDate(2026, 9, 13)
        let m = message(attempt("2026-08-26"), attempt("2026-09-02"), on: sunday)
        XCTAssertEqual(m?.title, "Last day to keep your 2-week streak")
        XCTAssertEqual(m?.body, "One session today and it's 3 weeks.")
    }

    /// the weekly warning waits for the last day of the week
    func testTheWeeklyWarningWaitsForTheLastDayOfTheWeek() {
        // Saturday, not Sunday: falls through to the general line.
        let saturday = LocalDate(2026, 9, 12)
        let m = message(attempt("2026-08-26"), attempt("2026-09-02"), on: saturday)
        XCTAssertEqual(m?.title, "Cindy's ready when you are")
    }

    /// otherwise the reminder quotes the best score in the latest category
    func testOtherwiseTheReminderQuotesTheBestScoreInTheLatestCategory() {
        let m = message(attempt("2026-09-01", rounds: 12, reps: 0), attempt("2026-09-03"))
        XCTAssertEqual(m?.title, "Cindy's ready when you are")
        XCTAssertEqual(m?.body, "Your best is 13 + 10. Twenty minutes to chase it.")
    }

    // MARK: preview

    /// preview is never null even when today is trained
    func testPreviewIsNeverNullEvenWhenTodayIsTrained() {
        let m = Reminder.preview([attempt("2026-09-09")], today: today, zone: zone, firstDayOfWeek: monday)
        XCTAssertEqual(m.title, "Time for your first Cindy")
    }

    /// preview ignores today and keeps earlier days
    func testPreviewIgnoresTodayAndKeepsEarlierDays() {
        let m = Reminder.preview([attempt("2026-09-08"), attempt("2026-09-09")], today: today, zone: zone, firstDayOfWeek: monday)
        XCTAssertEqual(m.title, "Make it two days in a row")
    }

    // MARK: formatTime

    /// formats a time on a 24 hour phone
    func testFormatsATimeOnA24HourPhone() {
        XCTAssertEqual(Reminder.formatTime(1080, is24Hour: true), "18:00")
        XCTAssertEqual(Reminder.formatTime(725, is24Hour: true), "12:05")
    }

    /// formats a time on a 12 hour phone
    func testFormatsATimeOnA12HourPhone() {
        XCTAssertEqual(Reminder.formatTime(1080, is24Hour: false), "6:00 PM")
        XCTAssertEqual(Reminder.formatTime(0, is24Hour: false), "12:00 AM")
        XCTAssertEqual(Reminder.formatTime(725, is24Hour: false), "12:05 PM")
    }
}
