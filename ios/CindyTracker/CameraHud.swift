import SwiftUI
import CindyCore

/// The camera screen's HUD: the two bands at the edges of the picture, the way a camera app does it.
/// Everything the athlete can touch lives in a band, and the bright middle is left alone for the body.
/// The bands are translucent, so the picture carries on underneath and a foot that has drifted low is
/// still visible, dimmed, but there. `activity_main.xml` is the reference for every measurement.
///
/// - The top band holds the clock, what changes mid-set (REC, and the menu), and the coaching line.
///   Its background runs under the status area; its content sits below it.
/// - The bottom band holds the metric and everything that acts on it: the progress bar as the band's
///   own top edge, the round and the movement, the count with its editors either side, and the action
///   row.
///
/// What each control is at each moment is `HudControls`'s to say; this draws it. `middle` is the room
/// between the bands, for what stands on the picture: the coach, the countdown, a toast.
struct CameraHud<Middle: View>: View {
    @ObservedObject var workout: WorkoutViewModel
    @ObservedObject var film: FilmModel
    let onMenu: () -> Void
    let onFlip: () -> Void
    let onStop: () -> Void
    let onStart: () -> Void
    let onSkip: () -> Void
    let onToggleDebug: () -> Void
    @ViewBuilder let middle: () -> Middle

    // Dynamic Type grows the bands rather than clipping them; the digits shrink to fit before they
    // would wrap, as Android's autosize does.
    @ScaledMetric(relativeTo: .title) private var clockSize: CGFloat = 30
    @ScaledMetric(relativeTo: .footnote) private var statusSize: CGFloat = 14
    @ScaledMetric(relativeTo: .largeTitle) private var repsSize: CGFloat = 56
    @ScaledMetric(relativeTo: .title) private var targetSize: CGFloat = 30

    private var controls: HudControls { workout.controls }

    var body: some View {
        VStack(spacing: 0) {
            topBand
            middle().frame(maxWidth: .infinity, maxHeight: .infinity)
            bottomBand
        }
    }

    // MARK: the top band

    private var topBand: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text(workout.clockText)
                    .font(Manrope.font(.extrabold, size: clockSize).monospacedDigit())
                    .tracking(-0.034 * clockSize)
                    .foregroundStyle(Palette.label)
                    .lineLimit(1)
                    .minimumScaleFactor(20.0 / 30.0)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel(workout.clockSpoken)
                    .accessibilityIdentifier("clock")
                    .padding(.leading, 20)
                // Icons, not words, and two of them: REC carries live state the athlete changes
                // mid-session, which is the whole test for this row. Music and the voice live in the
                // menu, where they can be chosen with a tap.
                let look = FilmFlow.look(for: film.state)
                IconPillButton(icon: .rec, tint: look.alert ? Palette.stateAlert : Palette.labelTertiary,
                               lit: look.lit, label: FilmFlow.label(for: film.state),
                               identifier: "btnRec", action: { film.tap() })
                    .tourTarget(.record)
                IconPillButton(icon: .menu, tint: Palette.labelSecondary, label: HudControls.menuLabel,
                               identifier: "btnMenu", action: onMenu)
                    .tourTarget(.menu)
                    .padding(.trailing, 12)
            }
            .frame(minHeight: 48)

            statusRow
        }
        .padding(.top, 14)
        .padding(.bottom, 11)
        .frame(maxWidth: .infinity)
        .background(Palette.bandTop.ignoresSafeArea(edges: .top))
    }

    /// The coaching line. It sat in a pill over the athlete; on the band it needs no pill. While the
    /// start-position coach is up the line steps aside, so the cue is never given twice, but it keeps
    /// its room, so the card hangs from the same place.
    private var statusRow: some View {
        HStack(spacing: 8) {
            Circle().fill(dotColour).frame(width: 7, height: 7).accessibilityHidden(true)
            Text(workout.status)
                .font(Manrope.font(.semibold, size: statusSize))
                .tracking(-0.0125 * statusSize)
                .foregroundStyle(Palette.label)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("status")
        }
        .frame(maxWidth: .infinity, minHeight: 22)
        .padding(.horizontal, 20)
        .padding(.top, 4)
        .opacity(workout.coachShowing == nil ? 1 : 0)
        .accessibilityHidden(workout.coachShowing != nil)
        // A long press on the status line is the way to the debug readout, as on Android.
        .onLongPressGesture { onToggleDebug() }
        .tourTarget(.status)
    }

    /// Whether a rep would count right now is said by the dot, not the text: a sentence that changes
    /// colour as you read it is harder to read, and white on glass is the most legible thing here.
    private var dotColour: Color {
        switch workout.dot {
        case .ok: return Palette.stateOk
        case .neutral: return Palette.labelTertiary
        case .alert: return Palette.stateAlert
        }
    }

    // MARK: the bottom band

    private var bottomBand: some View {
        VStack(spacing: 0) {
            progressEdge
            roundRow
            repRow
            actionRow
        }
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity)
        .background(Palette.bandBottom.ignoresSafeArea(edges: .bottom))
    }

    /// Edge to edge, and the band's own top edge: readable from across the room when the digits are
    /// not, and it draws the line the picture ends on.
    private var progressEdge: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.labelQuaternary)
                Capsule().fill(Palette.primaryFill)
                    .frame(width: geo.size.width * CGFloat(min(max(workout.repProgress, 0), 100)) / 100)
            }
        }
        .frame(height: 3)
        .accessibilityHidden(true)
    }

    private var roundRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text("ROUND").cindy(.eyebrow).accessibilityHidden(true)
            Text("\(workout.rounds + 1)")
                .cindy(.eyebrow, colour: Palette.labelSecondary)
                .padding(.leading, 6)
                .accessibilityLabel(HudSpeech.round(workout.rounds + 1))
                .accessibilityIdentifier("round")
            Spacer(minLength: 8)
            Text(workout.exerciseText)
                .cindy(.eyebrow, colour: Palette.labelSecondary)
                .lineLimit(1)
                .minimumScaleFactor(8.0 / 11.0)
                .accessibilityIdentifier("exerciseLabel")
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
    }

    /// Rep edits sit either side of the number they change, not lost among the actions.
    private var repRow: some View {
        HStack(spacing: 0) {
            GlassCircleButton(icon: .minus, inset: 15, label: HudControls.undoLabel,
                              identifier: "btnUndo", enabled: controls.editorsEnabled,
                              action: { workout.undoRep() })
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(workout.repsText)
                    .font(Manrope.font(.extrabold, size: repsSize).monospacedDigit())
                    .tracking(-0.048 * repsSize)
                    .foregroundStyle(Palette.label)
                    .lineLimit(1)
                    .minimumScaleFactor(30.0 / 56.0)
                    .accessibilityLabel(workout.repsSpoken)
                    .accessibilityIdentifier("repCount")
                // Drops back a weight and a shade so the eye lands on the number that moves.
                Text(workout.targetText)
                    .font(Manrope.font(.bold, size: targetSize).monospacedDigit())
                    .tracking(-0.048 * targetSize)
                    .foregroundStyle(Palette.labelTertiary)
                    .lineLimit(1)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 10)
            .tourTarget(.reps)
            GlassCircleButton(icon: .plus, inset: 15, label: HudControls.addLabel,
                              identifier: "btnAddRep", enabled: controls.editorsEnabled,
                              action: { workout.manualRep() })
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
    }

    /// The action row, laid out the way a camera lays one out: the shutter dead centre with a
    /// satellite parked at a fixed inset from either edge, so the middle of the band stays the middle
    /// at any width. SKIP is its own control and is there in every state, because it means one thing:
    /// leave this movement. The left slot holds one control at a time.
    private var actionRow: some View {
        ZStack {
            HStack(spacing: 0) {
                leftSlot
                Spacer(minLength: 0)
                GlassCircleButton(icon: .skip, inset: 14, label: controls.skipLabel,
                                  identifier: "btnSkipExercise", enabled: controls.skipEnabled,
                                  action: onSkip)
                    .tourTarget(.skip)
            }
            ShutterButton(mark: controls.shutter, enabled: controls.shutterEnabled,
                          label: controls.shutterLabel, action: onStart)
                .tourTarget(.start)
        }
        .frame(height: 68)
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    @ViewBuilder private var leftSlot: some View {
        switch controls.leftSlot {
        case .flip:
            GlassCircleButton(icon: .flip, inset: 14, label: HudControls.flipLabel,
                              identifier: "btnFlip", action: onFlip)
                .tourTarget(.flip)
        case .end:
            GlassCircleButton(icon: .stop, inset: 15, tint: Palette.stateAlert,
                              label: HudControls.endLabel, identifier: "btnEnd", action: onStop)
        }
    }
}
