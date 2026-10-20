import SwiftUI
import CindyCore

/// A control that dims while it has nothing to act on and presses to 70%, as the camera screen's
/// buttons do. It keeps its place when dimmed: a band that empties out reads as a band that has lost
/// its buttons.
private struct HudPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// A circle of glass holding a mark: the editors either side of the count, FLIP or END, and SKIP.
/// `btn_glass` with a circular shape on Android. Its spoken name is `label`, and its identifier the
/// Android view's id, which is what the UI tests look for since there is no word to find it by.
struct GlassCircleButton: View {
    let icon: CindyIcon
    var size: CGFloat = 52
    /// What the icon is inset by, so the mark is `size - 2 * inset` across.
    let inset: CGFloat
    var tint: Color = Palette.label
    let label: String
    let identifier: String
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(icon)
                .resizable()
                .scaledToFit()
                .foregroundStyle(tint)
                .padding(inset)
                .frame(width: size, height: size)
                .glassCard(radius: size / 2, raised: true)
                .contentShape(Circle())
        }
        .buttonStyle(HudPressStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : HudControls.dimmed)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }
}

/// The run control: the one filled control on the screen, round, a shutter and not a pill with a word
/// in it. Play, pause, again: the states it takes are ones a player already draws, and what the mark
/// cannot say on its own is said twice over, by the status line above it and by the spoken name.
struct ShutterButton: View {
    let mark: ShutterMark
    let enabled: Bool
    let label: String
    let action: () -> Void

    private var icon: CindyIcon {
        switch mark {
        case .play: return .play
        case .pause: return .pause
        case .again: return .again
        }
    }

    var body: some View {
        Button(action: action) {
            Image(icon)
                .resizable()
                .scaledToFit()
                .foregroundStyle(Palette.onPrimary)
                .padding(19)
                .frame(width: 68, height: 68)
                .background(Circle().fill(Palette.primaryFill))
                .contentShape(Circle())
        }
        .buttonStyle(HudPressStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : HudControls.dimmed)
        .accessibilityLabel(label)
        .accessibilityIdentifier("btnStart")
    }
}

/// A mark in the top band, a pill 44 by 40 that is lit while it carries live state (`icon_pill_active`
/// on Android): REC while it films.
struct IconPillButton: View {
    let icon: CindyIcon
    let tint: Color
    var lit = false
    let label: String
    let identifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(icon)
                .resizable()
                .scaledToFit()
                .foregroundStyle(tint)
                .padding(11)
                .frame(width: 44, height: 40)
                .background(lit ? Color(argb: 0x24FFFFFF) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 20))
                .contentShape(Rectangle())
        }
        .buttonStyle(HudPressStyle())
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }
}
