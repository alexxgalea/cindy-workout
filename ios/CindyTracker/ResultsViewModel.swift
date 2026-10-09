import CoreText
import SwiftUI
import UIKit
import CindyCore

/// What the results sheet is asked to show: the attempt, and what the record cannot say itself.
struct ResultsRequest: Identifiable, Equatable {
    let attempt: Attempt
    let stoppedEarly: Bool
    let heelsFlatSpotted: Bool
    /// A saved session reopened from Progress rather than one that has just ended.
    let reviewing: Bool
    var id: Int64 { attempt.atMillis }
}

extension ResultsRequest {
    /// The saved session filed at `atMillis`, to reopen as it looked the day it happened. Nil when
    /// the board no longer has it, in which case nothing opens.
    static func reopening(_ atMillis: Int64) -> ResultsRequest? {
        ResultsModel.session(at: atMillis, in: RecordStore().all()).map {
            ResultsRequest(attempt: $0, stoppedEarly: false, heelsFlatSpotted: false, reviewing: true)
        }
    }
}

/// The results page with its state, for SwiftUI: wraps `ResultsModel`, which decides everything,
/// and the four chart models, which own the touch. It publishes what the views must redraw for
/// and does nothing of its own to the page.
@MainActor
final class ResultsViewModel: ObservableObject {

    let results: ResultsModel
    let profile: BodyProfile

    let track = RoundTrackModel()
    let splits = RoundSplitsChartModel()
    let timeline = SessionTimelineChartModel()
    let zones = ZoneBarModel()

    @Published private(set) var page: ResultsPage
    @Published private(set) var trackSelected: Int?
    @Published private(set) var splitsSelected: Int?
    @Published private(set) var cursorMs: Int64?
    @Published private(set) var zoneSelected: Int?
    /// Bumped whenever a chart model was given new data, so its canvas draws again.
    @Published private(set) var revision = 0

    init(_ request: ResultsRequest, profile: BodyProfile = BodyProfile()) {
        let all = RecordStore().all()
        let zone = Zone(TimeZone.current.identifier)
        let trace = HeartRateStore().load(atMillis: request.attempt.atMillis)
        let repTimes = RepTimesStore(directory: FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("rep_times", isDirectory: true))
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let input = ResultsInput(
            attempt: request.attempt, stoppedEarly: request.stoppedEarly, reviewing: request.reviewing,
            heelsFlatSpotted: request.heelsFlatSpotted, records: all,
            body: profile.body(nowYear: Self.year(now, zone)), heartTrace: trace,
            repMarks: repTimes.load(atMillis: request.attempt.atMillis),
            marksFor: { repTimes.load(atMillis: $0) },
            zone: zone, firstDayOfWeek: Self.firstDay(), today: zone.localDate(epochMs: now),
            font: AppleEmojiFont(), is24Hour: Self.is24Hour())
        self.profile = profile
        results = ResultsModel(input)
        page = results.page

        track.onSelect = { [weak self] in self?.trackSelected = $0 }
        splits.onSelect = { [weak self] in self?.splitsSelected = $0 }
        timeline.onSelect = { [weak self] in self?.cursorMs = $0 }
        zones.onSelect = { [weak self] in self?.zoneSelected = $0 }
        let tick = { UISelectionFeedbackGenerator().selectionChanged() }
        track.onTick = tick
        splits.onTick = tick
        timeline.onTick = tick
        zones.onTick = tick
        // A scrub that lands in another round is announced, so a screen reader follows the cursor.
        timeline.onStopChanged = { [weak self] i in
            guard let stops = self?.timeline.stops, stops.indices.contains(i) else { return }
            UIAccessibility.post(notification: .announcement, argument: stops[i].description)
        }
        results.onChange = { [weak self] in self?.reload() }
        reload()
    }

    // MARK: what the page asks for

    /// The saved session filed at `atMillis`, to reopen from the comparison card. Nil when the
    /// board no longer has it, in which case nothing opens.
    func reopen(_ atMillis: Int64) -> ResultsRequest? { ResultsRequest.reopening(atMillis) }

    func chooseComparison(_ i: Int) { results.chooseComparison(i) }

    /// Builds the page again after the weight, age or sex changed.
    func bodyChanged() {
        let zone = results.input.zone
        let year = Self.year(Int64(Date().timeIntervalSince1970 * 1000), zone)
        results.update { $0.body = self.profile.body(nowYear: year) }
    }

    var trackCaption: String { results.trackCaption(selected: trackSelected) }
    var splitsReadout: SplitsReadout? { results.splitsReadout(selected: splitsSelected) }
    var timelineReadout: (title: String, detail: String)? { results.timelineReadout(clockMs: cursorMs) }

    // MARK: the charts

    private func reload() {
        page = results.page
        if let section = page.track {
            if track.rounds != section.rounds {
                track.show(section.rounds) { [weak self] in self?.page.track?.caption($0) ?? "" }
                trackSelected = nil
            }
        }
        if let section = page.splits {
            if splits.bars != section.split.bars {
                splits.show(bars: section.split.bars, fastest: section.split.fastest,
                            averageMs: section.split.averageMs, averageLabel: section.averageLabel) { [weak self] in
                    self?.results.splitsSpoken($0) ?? ""
                }
                splitsSelected = nil
            }
            // Choosing another comparison moves the ticks and keeps the bar the finger was on.
            splits.setReference(section.reference)
        }
        if let section = page.timeline {
            timeline.setLanes(section.lanes, durationMs: section.timeline.durationMs,
                              roundEndsMs: section.timeline.roundEnds, stops: section.stops)
        }
        if let heart = page.heart, let times = heart.zoneTimes, let rows = heart.zones {
            zones.setZones(times, descriptions: rows.map { $0.spoken })
        }
        revision += 1
    }

    // MARK: the phone

    private static func year(_ epochMs: Int64, _ zone: Zone) -> Int { zone.localDate(epochMs: epochMs).year }

    private static func firstDay() -> DayOfWeek {
        // Calendar counts Sunday as 1; DayOfWeek counts Monday as 1.
        DayOfWeek(rawValue: (Calendar.current.firstWeekday + 5) % 7 + 1) ?? .monday
    }

    private static func is24Hour() -> Bool {
        let format = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current) ?? ""
        return !format.contains("a")
    }
}

/// Whether the phone can draw an animal: asks the system font whether it has the glyph.
struct AppleEmojiFont: EmojiFont {
    func canDraw(_ emoji: String) -> Bool {
        let font = CTFontCreateWithName("AppleColorEmoji" as CFString, 12, nil)
        let characters = Array(emoji.utf16)
        var glyphs = [CGGlyph](repeating: 0, count: characters.count)
        return CTFontGetGlyphsForCharacters(font, characters, &glyphs, characters.count)
    }
}
