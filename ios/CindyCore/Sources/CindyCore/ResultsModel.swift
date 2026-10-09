import Foundation

/// How much room a line keeps while it has nothing to say: gone, or kept empty so the chart under
/// it does not move.
public enum LineVisibility: Sendable { case gone, invisible, visible }

/// The line above the splits for the bar the finger is on.
public struct SplitsReadout: Equatable, Sendable {
    public let title: String
    public let detail: String
    public let versus: String?
    /// Whether the versus line is faster than the comparison, or nil when level or absent.
    public let faster: Bool?
    /// Invisible, not gone, while a comparison exists: a line that comes and goes as the finger
    /// crosses a round the comparison never played would move the chart under it.
    public let versusVisibility: LineVisibility
}

/// The results page with its state: what it is measured against, and where the athlete's fingers
/// are on its charts. The page itself is built again, whole, whenever the weight or the heart-rate
/// details change, which is what turns an invitation into a card; the comparison chosen survives.
public final class ResultsModel {

    public private(set) var input: ResultsInput
    public private(set) var page: ResultsPage

    /// Called after the page has been built again.
    public var onChange: (() -> Void)?

    /// The session on the board filed at `atMillis`, to reopen. Nil when nothing on the board
    /// matches (the board was cleared while the request was in flight), in which case the screen
    /// closes rather than showing an empty page: inventing a score would be the same lie in
    /// a different place.
    public static func session(at atMillis: Int64, in records: [Attempt]) -> Attempt? {
        records.first { $0.atMillis == atMillis }
    }

    public init(_ input: ResultsInput) {
        self.input = input
        page = ResultsPageBuilder.build(input)
    }

    /// Builds the page again from `input`, keeping the comparison chosen if it is still there.
    public func update(_ change: (inout ResultsInput) -> Void) {
        var next = input
        change(&next)
        next.comparisonAtMillis = page.comparison?.atMillis ?? next.comparisonAtMillis
        input = next
        page = ResultsPageBuilder.build(next)
        onChange?()
    }

    /// A tap on the comparison chip at `index`.
    public func chooseComparison(_ index: Int) {
        guard let compare = page.compare else { return }
        let options = Comparisons.options(input.records.filter { $0.atMillis <= input.attempt.atMillis }, of: input.attempt)
        guard options.indices.contains(index), index != compare.chosen else { return }
        input.comparisonAtMillis = options[index].attempt.atMillis
        page = ResultsPageBuilder.build(input)
        onChange?()
    }

    // MARK: words that follow the fingers

    /// What a selected pill says, or the hint with none selected.
    public func trackCaption(selected: Int?) -> String {
        guard let track = page.track else { return "" }
        return selected.map { track.caption($0) } ?? track.hint
    }

    /// The line above the splits for bar `selected`, or the fastest and the average for none.
    public func splitsReadout(selected: Int?) -> SplitsReadout? {
        guard let splits = page.splits else { return nil }
        let r = RoundSplits.readout(input.attempt, splits.split, selected: selected,
                                    reference: page.comparison, kind: page.comparisonKind)
        let visibility: LineVisibility = page.comparison == nil ? .gone : (r.versus == nil ? .invisible : .visible)
        return SplitsReadout(title: r.title, detail: r.detail, versus: r.versus?.text, faster: r.versus?.faster,
                             versusVisibility: visibility)
    }

    /// What a screen reader says for splits bar `i`.
    public func splitsSpoken(_ i: Int) -> String {
        guard let splits = page.splits else { return "" }
        return RoundSplits.readout(input.attempt, splits.split, selected: i, reference: page.comparison,
                                   kind: page.comparisonKind).spoken()
    }

    /// The two lines above the timeline: with nothing selected the whole session in a line.
    public func timelineReadout(clockMs: Int64?) -> (title: String, detail: String)? {
        guard let section = page.timeline else { return nil }
        guard let clockMs else {
            return (section.timeline.idleReadout().title, ResultsPageBuilder.timelineHint)
        }
        let r = section.timeline.readout(section.timeline.at(clockMs))
        return (r.title, r.detail ?? "")
    }
}
