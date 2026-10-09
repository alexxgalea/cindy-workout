import SwiftUI
import UIKit
import CindyCore

/// What the Progress screen opens in its sheet: a trained day's sessions, or one session reopened.
enum ProgressRoute: Identifiable {
    case day(DaySheet)
    case session(ResultsRequest)

    var id: String {
        switch self {
        case .day(let sheet): return "day \(sheet.title)"
        case .session(let request): return "session \(request.id)"
        }
    }
}

/// The Progress screen with its state, for SwiftUI: wraps `ProgressModel`, which decides
/// everything, and the chart and calendar models, which own the touch. It publishes what the views
/// must redraw for and does nothing of its own to the page.
@MainActor
final class ProgressViewModel: ObservableObject {

    private(set) var progress: ProgressModel
    let chart = ProgressChartModel()
    let calendar: CalendarModel

    @Published private(set) var page: ProgressPage
    @Published private(set) var selected: Int?
    @Published private(set) var revision = 0
    @Published var route: ProgressRoute?
    @Published var asksToClear = false
    @Published private(set) var toast: String?

    private let store = RecordStore()
    /// What the chart was last given, so paging the calendar does not throw its selection away.
    private var shown: (metric: ProgressMetric, range: ProgressRange, points: [ProgressPoint])?

    init() {
        let zone = Zone(TimeZone.current.identifier)
        let first = Self.firstDay()
        calendar = CalendarModel(firstDayOfWeek: first, monthName: { month in
            let symbols = DateFormatter().standaloneMonthSymbols ?? CalendarModel.fullMonths
            return symbols[month.month - 1]
        })
        let name = UserDefaults.standard.string(forKey: "display_name")?.trimmingCharacters(in: .whitespaces)
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        progress = ProgressModel(ProgressInput(
            attempts: store.all(), today: zone.localDate(epochMs: now), nowMs: now, zone: zone, firstDayOfWeek: first,
            displayName: (name?.isEmpty ?? true) ? nil : name, is24Hour: Self.is24Hour()))
        page = progress.page

        chart.onSelect = { [weak self] in self?.selected = $0 }
        chart.onTick = { UISelectionFeedbackGenerator().selectionChanged() }
        calendar.onDayTap = { [weak self] date in
            guard let self, let sheet = self.progress.daySheet(date) else { return }
            self.route = .day(sheet)
        }
        progress.onChange = { [weak self] in self?.reload() }
        reload()
    }

    // MARK: what the page asks for

    func chooseMetric(_ i: Int) { progress.chooseMetric(i) }
    func chooseRange(_ i: Int) { progress.chooseRange(i) }
    func chooseCategory(_ i: Int) { progress.chooseCategory(i) }
    func previousMonth() { progress.showPreviousMonth() }
    func nextMonth() { progress.showNextMonth() }

    var readout: Readout { progress.readout(selected: selected) }

    /// The session OPEN reopens, when a line point is selected.
    var openTarget: Int64? { progress.openTarget(selected: selected) }

    /// Reopens a saved session on the results page, as it looked the day it happened. The sheet
    /// that was up gets out of the way, rather than leaving the athlete to dismiss a day they are no
    /// longer looking at.
    func open(session atMillis: Int64) {
        if let request = ResultsRequest.reopening(atMillis) { route = .session(request) }
    }

    /// The one irreversible thing in the app, after it has asked twice. A trace or a rep log with
    /// nothing left to sit beside is not a record of anything.
    func clear() {
        store.clear()
        HeartRateStore().clear()
        RepTimesStore(directory: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("rep_times", isDirectory: true)).clear()
        progress.reload([])
        toast = ProgressPageBuilder.clearedToast
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            self?.toast = nil
        }
    }

    // MARK: the models

    private func reload() {
        page = progress.page
        if let section = page.calendar {
            calendar.show(section.month, trained: section.trained, today: section.today, streak: section.currentRun)
        }
        if let card = page.progress {
            feedChart(card)
        } else {
            shown = nil
        }
        revision += 1
    }

    private func feedChart(_ card: ProgressCard) {
        guard let data = card.chart else {
            shown = nil
            return
        }
        let metric = progress.metric
        let range = progress.range
        let points: [ProgressPoint]
        switch data {
        case .line(let p, _, _, _, _, _): points = p
        case .bars(let p, _): points = p
        }
        // The same data again (the calendar paged) keeps the selection; anything else starts over.
        if let last = shown, last.metric == metric, last.range == range, last.points == points { return }
        shown = (metric, range, points)
        let spoken: (Int) -> String = { [weak self] in self?.progress.spoken(point: $0) ?? "" }
        switch data {
        case .line(let points, let best, let xStart, let xEnd, let invertY, let edges):
            chart.showLine(points: points, best: best, xStart: xStart, xEnd: xEnd, invertY: invertY, edgeLabels: edges,
                           axisLabel: { metric == .pace ? formatDuration(Int64($0 * 1000)) : "\(JavaText.roundToInt($0))" },
                           describe: spoken)
        case .bars(let points, let edges):
            chart.showBars(points: points, edgeLabels: edges,
                           axisLabel: { Progress.formatReps(JavaText.roundToInt($0)) }, describe: spoken)
        }
        selected = nil
    }

    // MARK: the phone

    private static func firstDay() -> DayOfWeek {
        DayOfWeek(rawValue: (Calendar.current.firstWeekday + 5) % 7 + 1) ?? .monday
    }

    private static func is24Hour() -> Bool {
        let format = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current) ?? ""
        return !format.contains("a")
    }
}
