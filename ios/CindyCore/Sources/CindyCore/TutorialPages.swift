import Foundation

/// One thing on a page of the first-launch tour. The screen lays these out in order and decides
/// nothing about them.
public enum TutorialBlock: Equatable, Sendable {
    /// The three arcs, 270°, 180° and 90° of a circle: fifteen, ten and five.
    case mark
    case title(String)
    case body(String)
    case footnote(String)
    case bullet(String)
    /// The movements that count and the ones the athlete taps in, one row each.
    case movements([TutorialMovement])
    /// Prose in a card.
    case callout(String)
    /// The button that opens the movement sheet.
    case chooseMovements
    /// The placement diagram, drawn.
    case placementDiagram
    /// The placement facts, one row each.
    case placementFacts([PlacementFacts.Fact])
}

/// One movement and what the app does with it: counted, or left for the athlete to tap in.
public struct TutorialMovement: Equatable, Sendable {
    public let label: String
    public let counted: Bool

    /// What the row says on the right.
    public var status: String { counted ? "counted" : "you tap +1" }

    /// Read as a single sentence, with "+1" said as words, as the movement sheet says it: a bare
    /// glyph is not left to chance.
    public var spoken: String { "\(label), \(counted ? "counted" : "you tap plus one")" }
}

public struct TutorialPage: Equatable, Sendable {
    public let index: Int
    public let title: String
    public let blocks: [TutorialBlock]

    /// Every sentence the athlete reads on the page, in order.
    public var texts: [String] {
        blocks.flatMap { block -> [String] in
            switch block {
            case .mark, .chooseMovements, .placementDiagram: return []
            case .title(let t), .body(let t), .footnote(let t), .bullet(let t), .callout(let t): return [t]
            case .movements(let rows): return rows.map { $0.label }
            case .placementFacts(let facts): return facts.map { $0.text }
            }
        }
    }
}

/// What ending the pages does, which the screen carries out.
public enum TutorialExit: Equatable, Sendable {
    /// The first run: back to the camera screen that opened the pages, which goes on to ask for the
    /// camera.
    case dismiss
    /// A replay from Help: to the camera screen, closing the menu and the help above it so that the
    /// tour that follows has something to point at.
    case returnToCamera
}

/// Five pages that show a new athlete around before the camera opens. Port of `TutorialActivity`:
/// the pages, the buttons, the dots, the swipe, and what ending them does. The screen draws what
/// this returns.
///
/// They come before the camera's permission prompt rather than after it, for the reason a prompt
/// with no context gets refused: by the time iOS asks to use the camera, the athlete has just been
/// told what this app is, that the picture never leaves the phone, and why it wants to see them.
///
/// The second page is the one that matters most and is the only one with a control of its own.
/// Cindy is easy to read as a strict workout that an athlete who is not there yet cannot do, and an
/// app that counts nothing for them is an app that looks broken. So it says, before anything else,
/// that other movements count, which ones, and how to choose them.
///
/// The same pages are taken again from Help. `replay` tells the two apart: the first time they end
/// at the camera's permission prompt, and on a replay they go back to the camera screen.
public struct TutorialModel: Equatable, Sendable {

    /// The pages, and so the dots.
    public static let pageCount = 5

    /// How far a finger has to travel sideways, in points, and how much more than it travels up or
    /// down.
    public static let swipeDistance: Float = 64
    public static let swipeRatio: Float = 2

    public static let titles = [
        "Cindy, counted for you",
        "Your Cindy, your movements",
        "Where to stand",
        "Before the clock starts",
        "Nothing leaves your phone"
    ]

    /// What the second page says about the setting that spots heels-flat squats.
    static let smartSentence =
        "Squatting with your heels flat? That's a correct squat too. Choose Heels flat, " +
        "or turn on Spot heels-flat squats and Cindy switches to Adaptive Cindy by " +
        "itself after three of them, says so out loud, and counts them, the first " +
        "three included."

    static let adaptiveSentence =
        "Sessions with other movements are saved as an Adaptive Cindy and ranked against " +
        "your own sessions at the same movements."

    /// What the last page says on a first run, because only the first run is about to be asked;
    /// someone replaying the pages has answered.
    public static let cameraFootnote = "Next, iOS asks to use the camera."

    public let replay: Bool
    public private(set) var index: Int
    /// Whether the last move was towards the end, for the page to slide in from the right side.
    public private(set) var forward = true

    /// `index` is where a restored screen was left, kept inside the pages.
    public init(replay: Bool, index: Int = 0) {
        self.replay = replay
        self.index = min(max(index, 0), Self.pageCount - 1)
    }

    public var isFirst: Bool { index == 0 }
    public var isLast: Bool { index == Self.pageCount - 1 }

    // MARK: moving

    public mutating func goTo(_ target: Int) {
        guard (0..<Self.pageCount).contains(target), target != index else { return }
        forward = target > index
        index = target
    }

    /// NEXT, or LET'S GO / DONE on the last page. Returns what ending does, or nil while there are
    /// more pages.
    public mutating func next() -> TutorialExit? {
        if isLast { return exit }
        goTo(index + 1)
        return nil
    }

    public mutating func back() { goTo(index - 1) }

    /// The system's back gesture steps back through the pages, and out of the first one ends them as
    /// skipping does.
    public mutating func systemBack() -> TutorialExit? {
        if index > 0 { goTo(index - 1); return nil }
        return exit
    }

    /// A sideways swipe turns the page: far enough, and a good deal more across than up or down, so
    /// that a scroll is never mistaken for one. Left is forward.
    public mutating func swipe(dx: Float, dy: Float) {
        guard let step = Self.swipeStep(dx: dx, dy: dy) else { return }
        goTo(index + step)
    }

    /// `+1` for a swipe to the left, `-1` for one to the right, nil for anything that is not a swipe.
    public static func swipeStep(dx: Float, dy: Float) -> Int? {
        guard abs(dx) > swipeDistance, abs(dx) > swipeRatio * abs(dy) else { return nil }
        return dx < 0 ? 1 : -1
    }

    /// However the pages end, they do not come back by themselves, and the tour of the camera screen
    /// is next.
    public func finish(_ firstRun: FirstRun) -> TutorialExit {
        firstRun.finishPages()
        return exit
    }

    private var exit: TutorialExit { replay ? .returnToCamera : .dismiss }

    // MARK: what the screen shows

    public var title: String { Self.titles[index] }

    /// The button on the right.
    public var nextLabel: String {
        if !isLast { return "NEXT" }
        return replay ? "DONE" : "LET'S GO"
    }

    /// The button on the left, absent on the first page.
    public var backLabel: String? { isFirst ? nil : "BACK" }

    public static let skipDescription = "Skip the introduction"

    /// What the row of dots says, which is all a screen reader gets of them.
    public var dotsDescription: String { "Page \(index + 1) of \(Self.pageCount)" }

    /// Said on every page change rather than left to be discovered: a screen reader lands on it
    /// silent.
    public var announcement: String { title }

    /// The page being shown. `stravaAvailable` is whether this build has Strava at all.
    public func page(stravaAvailable: Bool) -> TutorialPage {
        TutorialPage(index: index, title: title, blocks: Self.blocks(index, replay: replay, stravaAvailable: stravaAvailable))
    }

    private static func blocks(_ index: Int, replay: Bool, stravaAvailable: Bool) -> [TutorialBlock] {
        switch index {
        case 0:
            return [
                .mark, .title(titles[0]),
                .body("Twenty minutes, as many rounds as you can of 5 pull-ups, 10 push-ups and 15 air " +
                      "squats. Prop up your phone and the camera counts every rep.")
            ]
        case 1:
            return [
                .title(titles[1]),
                .body("Not doing strict pull-ups, full push-ups or deep squats yet? Pick the movements " +
                      "you actually do — Cindy counts those too."),
                .movements([
                    TutorialMovement(label: "Band-assisted pull-ups", counted: true),
                    TutorialMovement(label: "Push-ups from the knees", counted: true),
                    TutorialMovement(label: "Heels-flat, on-toes or box squats", counted: true),
                    TutorialMovement(label: "Inverted rows, incline push-ups and more", counted: false)
                ]),
                .callout(smartSentence),
                .footnote(adaptiveSentence),
                .chooseMovements
            ]
        case 2:
            return [
                .title(titles[2]),
                .body("The one thing you have to get right before the camera can help."),
                .placementDiagram,
                .placementFacts(PlacementFacts.all)
            ]
        case 3:
            return [
                .title(titles[3]),
                .bullet("START checks your framing, then asks for two slow pull-ups so Cindy learns your " +
                        "range. The clock starts itself once it has."),
                .bullet("The dot on the status line turns green when the next rep will count. When one " +
                        "won't, the line says why — out loud too."),
                .bullet("−1 and +1 fix a miscount any time. Hold +1 to move on to the next movement.")
            ]
        default:
            var blocks: [TutorialBlock] = [
                .title(titles[4]),
                .bullet("Counting happens on this phone. The picture is never uploaded."),
                .bullet("REC films only when you tap it, and saves to your phone.")
            ]
            if stravaAvailable { blocks.append(.bullet("Strava stays off until you connect it in the menu.")) }
            if !replay { blocks.append(.footnote(cameraFootnote)) }
            return blocks
        }
    }

    /// The athlete's choice on the second page is kept as it is made, and said back in the words the
    /// movement sheet uses.
    public static func choose(_ chosen: CindyProfile, in profile: Profile) -> String {
        profile.movements = chosen
        return chosen.label()
    }
}
