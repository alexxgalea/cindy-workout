# iOS UI parity plan

> **For agentic workers:** this is the master plan. Each phase has its own task-level plan, `ios/ui-parity/U<n>.md`. U0's is written. A later phase's plan is written from `origin/main` when the phase starts, and is the first commit of that phase's pull request. Carry a phase plan out with the `subagent-driven-development` or `executing-plans` skill.

**Goal:** the iPhone app has the Android app's shape. Every screen shares the layout, tokens, words, icons and section order, so that two captures side by side read as one product.

**Architecture:** the Android app is the reference and does not move. The Swift design system that already exists (`Palette.swift`: `Palette`, `Manrope`, `CindyType`, `glassCard`, the two button styles, `MarkArcs`) becomes the only styling on iOS. U0 adds the rest of Android's vocabulary: `CindyViews.kt`, `CindySheet.kt` and the `ic_*` icons. Each later phase rebuilds one screen out of it. The page models in CindyCore (`MenuBuilder`, `ResultsPageBuilder`, `ProgressPageBuilder`, …) already hold Android's words and decisions. A phase changes what the SwiftUI layer draws, and changes a model only where its words or order differ from the Kotlin.

**Tech stack:** SwiftUI (iOS 17.0 deployment target), CindyCore (Swift package; its tests run on Linux), XcodeGen, and XCUITest with the `-CindyReplay` pose source.

**Spec:** `docs/adr/0003-ios-follows-android-ui.md` and the decisions below.

## Decisions

1. **Android is the source of truth.** iOS changes. Android changes only to fix a bug the port exposes (see *Found on Android*).
2. **"Same shape"** means the same layout, tokens, words, icons and order, judged by captures side by side, not by pixel identity.
3. **Every visible screen is in scope**, in this order: the camera HUD, the session page, Progress, Menu + Account, the menu's sheets, the placement guide. Help, the tutorial, the tour and the Strava sheets already use the design system and only have their remaining differences fixed.
4. **In-app questions and the menu's choice sheets use the Cindy sheet**, not the system's alerts or `Form` sheets. The photo and file pickers, permission prompts, the share sheet and swipe gestures stay native.
5. **The camera screen gets** a separate SKIP button (the long press on +1 goes), the start-position coach and the launch view.
6. **Menu and the session page are full-screen** and close with DONE. Navigation inside the menu is by push.
7. **The camera screen hides** the status bar and the home indicator.
8. **Verification is by captures in pairs.**
   - The Android references are in `ios/ui-parity/android/` (see *Android references*).
   - The iOS captures come from the `CaptureTests` UI tests, which CI uploads as the `ios-captures` artifact (built in U0).
   - Each pull request lists its pairs and every difference it leaves, with the reason.
   - A check on a real iPhone, at the smallest and largest text sizes, is owed at the end and blocks nothing.
9. **One pull request per phase**, branched from `origin/main` and targeting `main` (never stacked), made of small commits. Phases in the same wave can run in parallel, one session each.
10. **The glossary's words**: *Session page* and *Progress* are the names in code comments and pull requests.
11. **The App Store submission waits** until at least U1 and U2 have merged.

## Global constraints

- **iOS 17.0 is the floor.** Use no iOS 18-only API (`ForEach(subviews:)`, `Group(subviews:)` and the like) without an `#available` fallback that looks the same.
- **Glass is the three-layer recipe in `glassCard`.** No runtime blur, `.ultraThinMaterial`, `.glassEffect` or system Liquid Glass backgrounds.
- **Colours come only from `Palette`.** Green (`stateOk`) is the affirmative, red (`stateAlert`) blocked or stopping, orange (`stateCaution`) caution, `achievement` earned. The skeleton is white.
- **Type comes only from `CindyType`** through `.cindy(_:)`. A number that ticks uses tabular figures.
- **Icons come from `CindyIcon`**, which holds Android's `ic_*` drawables. The one exception is a system control that draws its own.
- **Words are copied verbatim** from the Kotlin on `origin/main` when the phase starts. Where a CindyCore model holds the words, its tests pin them.
- **Code and comments describe the app, not this plan.** No phase ids. `ios/PARITY.md` rows say what iOS does, in that file's style.
- **Commit subjects are plain sentences** in the repository's voice, with no attribution lines.
- **The accessibility identifiers that `CindyTrackerUITests` uses keep working**, or the test changes in the same commit.
- **Android keeps changing.** A phase reads it from `origin/main` when it starts. An Android change that lands later is a follow-up, not a reason to stall.

## Review focus

The cases most likely to break for a person using the app, which no single task's tests exercise. Each phase adds a test for the ones its screens can meet.

- **The largest Dynamic Type size.** Every rebuilt screen and sheet keeps its primary action on screen and reachable at `accessibility-XXXL`. Android caps sheet content at 60% of the height for the same reason.
- **The keyboard over a sheet.** The body-weight and name fields stay visible above the keyboard, together with their SAVE button.
- **VoiceOver under a sheet or a cover.** What is beneath leaves the accessibility tree while a sheet or a full-screen cover is up.
- **The smallest phone (375×667) and the Dynamic Island.** The two bands and the rep count fit without overlapping the island or each other.
- **A dismissal that is not a button.** A tap on the dim, a swipe down or the VoiceOver escape gesture does exactly what the "keep" answer does. For the stop question, that means the clock runs again.

---

## Phases

| Id | Branch | Screen | Android reference | iOS files owned | Wave |
|---|---|---|---|---|---|
| U0 | `ios-ui-u0-foundation` | Shared vocabulary, icons, the Cindy sheet, the three questions, the capture tests | `CindyViews.kt`, `CindySheet.kt`, `res/drawable/ic_*.xml`, `res/values/{colors,dimens,type}.xml` | new `CindyViews.swift`, `CindySheet.swift`, `CindyIcon.swift`, `Assets.xcassets/Icons/`, `tools/ios_icons.py`, `CaptureTests.swift`; `Palette.swift`; `HelpScreen.swift` (rows and icons only); the three questions in `ContentView.swift` and `ResultsView.swift`; the test step of `.github/workflows/ios-app.yml` | 0, alone |
| U1 | `ios-ui-u1-camera` | Camera HUD | `activity_main.xml`, `MainActivity.kt` (`renderControls`, `primary`, `renderChips`, the coach card), `StartPoseView.kt`, `LaunchView.kt`, `CountdownView.kt`, `HudTour.kt` | `ContentView.swift`, `WorkoutViewModel.swift`, `FilmModel.swift` (titles only), new `StartPoseView.swift` and `LaunchView.swift`, `SpotlightOverlay.swift` (the SKIP target), the SKIP wording in CindyCore `HelpPage`/`HudTour` | 1 |
| U2 | `ios-ui-u2-session-page` | Session page | `activity_results.xml`, `ResultsActivity.kt` | `ResultsView.swift`, `ResultsCharts.swift`, `ResultsViewModel.swift`, and the one line in `ContentView` that presents it | 1 |
| U3 | `ios-ui-u3-progress` | Progress | `activity_records.xml`, `RecordsActivity.kt`, `CalendarView.kt`, `ProgressChartView.kt`, `WeekStripView.kt` | `ProgressScreen.swift`, `ProgressCharts.swift`, `ProgressViewModel.swift` | 1 |
| U4 | `ios-ui-u4-menu-account` | Menu and Account | `activity_menu.xml`, `MenuActivity.kt` (the page, not its sheets), `activity_account.xml`, `AccountActivity.kt`, `AvatarView.kt` | `MenuScreen.swift`, `AccountScreen.swift`, `AvatarView.swift`, and the one line in `ContentView` that presents the menu | 2 |
| U5 | `ios-ui-u5-sheets` | The menu's sheets | `MenuActivity.kt` (every `CindySheet`), `Dialogs.kt`, `HeartRateScanner.kt`, `StravaConsent.kt`, `LanguageGroup.kt` | `ProfileSheets.swift`, `VoiceSheet.swift`, `MusicSheet.swift`, `HeartRateSheet.swift`, `ReminderSheet.swift`, `StravaSheets.swift`, the photo sheet in `AccountScreen.swift` | 3, after U4 |
| U6 | `ios-ui-u6-placement` | Placement guide | `PlacementGuideView.kt` and its `CindySheet` call in `MainActivity.kt` | `PlacementGuideView.swift`, `PlacementDiagram.swift` | 2, after U1 |
| U7 | `ios-ui-u7-cleanup` | Retire the old styling | — | the `Color.accent`/`dim`/`warn` extension, `Chip`, `PrimaryButton` and `GhostButton` in `ContentView.swift`; the comment in `Palette.swift` that says older screens keep their colours; `ios/PARITY.md`; `ios/README.md` | 4, last |

A phase that needs a component U0 did not build adds it to a **new** file named after the component. `CindyViews.swift` is edited only by U0 and U7, so parallel phases never collide there. U7 folds the new files into it.

### Every phase's definition of done

- [ ] CindyCore's tests are green. On a Mac, run `swift test --package-path ios/CindyCore`. In a Linux or cloud session, run `docker run --rm -v "$PWD":/w -w /w swift:6.1.2-noble swift test --package-path ios/CindyCore`.
- [ ] The app builds and its UI tests are green. On a Mac, run `cd ios && xcodegen generate && cd .. && xcodebuild test -project ios/CindyTracker.xcodeproj -scheme CindyTracker -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO`. In a cloud session, read the pull request's `Build Cindy iOS` check.
- [ ] The phase's captures in `ios-captures` are compared with the matching files in `ios/ui-parity/android/`. Each difference is fixed, or listed in the pull request with its reason.
- [ ] The phase's rows in `ios/PARITY.md` say what iOS now does.
- [ ] The pull request targets `main`. After it merges, `git merge-base --is-ancestor <head> origin/main` holds.

## Running a phase in a cloud session

1. **Once per cloud environment:** put `docker pull swift:6.1.2-noble` in the environment's setup script (claude.ai/code → the environment's settings), so the image is in the environment's cache and is not downloaded again in every session.
2. **Start the session on `main`**, with the task "Carry out U<n> of `ios/ui-parity/PLAN.md`". Run sessions for the same wave in parallel, never one from a later wave.
3. **The session's first commit is the phase plan** `ios/ui-parity/U<n>.md` (skip this for U0, whose plan exists). It is written with the `writing-plans` skill, from the Android sources on `origin/main` and from the phase's row and notes here.
4. **The session pushes, opens the pull request against `main`**, and works until the checks are green and the captures are compared.

## Android references

Captures of the Android app, one file per screen and state, named `<screen>-<state>.png`, taken on a phone with `adb exec-out screencap -p` and scaled to 540 px wide. They are taken locally, because a cloud session has no phone, and committed before the phase that needs them starts. Every iOS capture with the same name is compared with its reference.

| Phase | Captures |
|---|---|
| U0 | `help-links`, `help-tiers`, `question-stop`, `question-skip`, `question-discard` |
| U1 | `camera-idle`, `camera-setup`, `camera-running`, `camera-paused`, `camera-coach`, `camera-countdown`, `camera-launch` |
| U2 | `session-finished`, `session-stopped`, `session-reopened-compared`, `session-heart-rate` |
| U3 | `progress-empty`, `progress-history`, `progress-point`, `progress-day` |
| U4 | `menu-idle`, `menu-live`, `account-badges`, `account-empty` |
| U5 | one per sheet (`sheet-<row>`), and `sheet-body-weight-keyboard` |
| U6 | `placement-guide` |

---

### U0: foundation

Task-level plan: `ios/ui-parity/U0.md`.

### U1: camera HUD

**Known differences** (`ContentView.swift` against `activity_main.xml`):
- **The retired mint `#00E5A0`** still colours the bones, the movement label, the progress bar and the primary button. Android's skeleton and primary are white.
- **Layout.** Black capsules float over a full-bleed preview. Android has two translucent bands:
  - the top band, about 104 pt (`Palette.bandTop`), holds the clock, the REC and MENU icons, and the status line;
  - the bottom band, about 200 pt (`Palette.bandBottom`), holds the round · movement eyebrow, the rep count with −/+ beside it, and the action row.
- **The actions are words** (START, PAUSE, STOP, FLIP). On Android:
  - the shutter is a mark only (`ic_play`, `ic_pause`, `ic_again`, `ic_skip`), with a spoken name;
  - FLIP and END are icons, and the left slot changes hands between them.
- **Skipping.** iOS skips on a long press on +1, while Android has `btnSkipExercise`. The tour regains its SKIP step, and Help goes back to Android's wording: `HelpPageTests` expects "Hold +1" today, and that flips.
- **Idle controls dim in place and never hide**, by the rule in `renderControls`.
- **The status bar and the home indicator are hidden.**
- **New on iOS:** the start-position coach card (`coachCard`, `coachPose`) and the launch view (`launch`).
- **The ROUND chip** moves into the bottom band's eyebrow.

**The analysis frame stays as it is.** The bands are an overlay. The capture session, the Vision crop and the film are untouched.

**UI tests that change:**
- A lookup by a word that becomes a mark (`START`, `PAUSE`, `RESUME`, `STOP`, `RESET`) uses the control's accessibility label or an identifier instead.
- `testALongPressOnPlusOneSkipsToTheNextMovement` becomes a test of the SKIP button.

### U2: session page

- **Presentation.** Full-screen (`fullScreenCover`), closed with DONE.
- **Content.** Rebuilt from `InsetGroup` and `ValueRow` in the card order of `activity_results.xml`, with the charts restyled to the tokens.
- **The heels-flat question.** `HeelsFlatSheet`'s `.alert` becomes a Cindy sheet.

### U3: Progress

`ProgressScreen` is rebuilt from the shared components, in the Kotlin's order: the habit, THIS WEEK, the PROGRESS chart card (its chips inside it), PEAKS, the calendar, then the LEADERBOARD of `RankRow`s. It has Android's title and line under it and a DONE pinned below the scroll; a trained day lists its sessions in a Cindy sheet whose rows open the session, and a reopened session is full-screen.

### U4: Menu and Account

`MenuScreen` is a full-screen cover with Android's title and line under it, the profile row (`AvatarRow`) and the rows (`NavRow`) in grouped cards, the live-workout footnote, and a DONE pinned below the scroll. `AccountScreen` has the same shell, the header card, the badge families three to a row drawn by `BadgeDisc`, and a badge opening a Cindy sheet. The avatar's figure is drawn as Android draws it. The menu's own sheets, the name sheet and the photo dialog are U5's and are still the system's.

### U5: the menu's sheets

- **Become Cindy sheets**, with Android's toggles, sliders and fields:
  - every `NavigationStack`/`Form` sheet with Save and Cancel;
  - the `.alert`s in `ReminderSheet` and `VoiceSheet`;
  - the photo `confirmationDialog`.
- **Strava.** `StravaConsentSheet` loses its system fonts, and `StravaConnectedSheet` loses its `List`.
- **The pickers stay the system's.**

### U6: placement guide

A Cindy sheet over the live preview, as on Android, not a system sheet.

### U7: cleanup

- Delete the old styling once `grep -rn "Color.accent\|Color.dim\|Color.warn\|\.chip()\|PrimaryButton()\|GhostButton(" ios/CindyTracker` finds nothing outside the definitions.
- Fold any component files the phases added into `CindyViews.swift`.
- Make a final pass on `ios/PARITY.md` and `ios/README.md`.

## Found on Android

Bugs the port exposed. Each is fixed in a pull request of its own on Android, not in a phase.

- **`MainActivity.confirmStop` leaves the clock parked after the back gesture.** It parks the clock and resumes it only from KEEP GOING, so closing the question with the back gesture leaves the workout paused, with nothing on screen saying so. On iOS, every way out of the question is KEEP GOING. A one-line `onDismiss` fixes it.

## After U7

- The App Store build, with the listing's screenshots retaken from the new interface.
- The real-iPhone check: every capture state once, at the smallest and the largest text size.
