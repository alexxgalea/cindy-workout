import Foundation

/// When a new athlete is shown around, and where that is remembered.
///
/// The pages and the tour of the camera screen are for someone who has never used the app. Someone
/// who has, who has finished a session or who has read the placement guide and asked never to see it
/// again, has nothing to learn from a welcome and would only be kept from the camera by one. So they
/// are marked as having seen it without being shown it. A tour that greeted every returning athlete
/// after an update would be the first thing this app ever did to them that was not about their
/// workout. Port of `Onboarding.kt`; `FirstRun` holds the flags.
public enum Onboarding {

    /// Set once the pages have been shown, finished or skipped. They do not come back by themselves.
    public static let keyTutorialSeen = "tutorial_seen"

    /// Set when the pages are done and the tour of the camera screen has not yet been taken.
    public static let keyHudTourPending = "hud_tour_pending"

    /// Where "Don't show this again" on the placement guide is kept.
    ///
    /// It lived with the camera screen until it became evidence of something else too: an athlete who
    /// has dismissed the guide has used the app before, whatever the records say. One owner for the
    /// key means the two readers cannot disagree about what it is called.
    public static let keyPlacementSeen = "placement_guide_dismissed"

    /// Whether to show the pages before the camera opens.
    ///
    /// Only to a new install: nothing seen, no session on record, the placement guide never
    /// dismissed, and the camera's permission not already held. Each of the last three is proof
    /// enough that the app is not new to them, and the records alone are not: a person can dismiss
    /// the guide, or only ever run the setup check, and close the app before finishing anything.
    ///
    /// The permission is the evidence that reaches furthest back. A fresh install starts without
    /// it, while an athlete who updated from a version that predates these pages has held it since
    /// the first time they opened the camera.
    public static func shouldShowTutorial(seen: Bool, hasHistory: Bool, placementDismissed: Bool,
                                          cameraGranted: Bool) -> Bool {
        !seen && !hasHistory && !placementDismissed && !cameraGranted
    }
}

/// The first-launch flags, kept with every other preference.
///
/// Apart from the settings on purpose, because they are not settings. Nobody edits them from a
/// screen: they record what has already happened to this install, so that the pages and the tour of
/// the camera screen each happen once. When they happen at all is decided by `Onboarding`.
public final class FirstRun {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    /// Whether the pages are dealt with: shown and finished or skipped, or never needed because the
    /// athlete had already used the app. Set either way, so that clearing the records later does not
    /// make an existing athlete look new.
    public var tutorialSeen: Bool {
        get { defaults.bool(forKey: Onboarding.keyTutorialSeen) }
        set { defaults.set(newValue, forKey: Onboarding.keyTutorialSeen) }
    }

    /// Whether the tour of the camera screen is still to come.
    public var hudTourPending: Bool {
        get { defaults.bool(forKey: Onboarding.keyHudTourPending) }
        set { defaults.set(newValue, forKey: Onboarding.keyHudTourPending) }
    }

    /// Whether the athlete has asked never to see the placement guide again. Nobody does that
    /// without having met the app before, which is why it counts as history.
    public var placementDismissed: Bool { defaults.bool(forKey: Onboarding.keyPlacementSeen) }

    /// Whether to show the pages now. `hasHistory` is whether any session is on record, and
    /// `cameraGranted` whether the camera's permission is already held.
    public func shouldShowTutorial(hasHistory: Bool, cameraGranted: Bool) -> Bool {
        Onboarding.shouldShowTutorial(seen: tutorialSeen, hasHistory: hasHistory,
                                      placementDismissed: placementDismissed, cameraGranted: cameraGranted)
    }

    /// The end of the pages, however they ended: they will not come back, and the tour is next.
    public func finishPages() {
        tutorialSeen = true
        hudTourPending = true
    }
}
