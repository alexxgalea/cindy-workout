import CoreText
import SwiftUI
import UIKit

extension Color {
    /// A colour written as `colors.xml` writes it: `0xAARRGGBB`, in sRGB.
    init(argb: UInt32) {
        self.init(.sRGB,
                  red: Double((argb >> 16) & 0xFF) / 255,
                  green: Double((argb >> 8) & 0xFF) / 255,
                  blue: Double(argb & 0xFF) / 255,
                  opacity: Double((argb >> 24) & 0xFF) / 255)
    }
}

/// The palette of the Android app, `res/values/colors.xml`, as one place.
///
/// White at four opacities on black, three system colours that mean something, and one colour for
/// what the athlete has earned. Nothing is coloured for decoration. Green is the affirmative: this
/// rep would count, a tier reached. Red is blocked, unreadable, or stopping. Orange cautions.
/// Achievement orange means one thing only: you earned this.
///
/// The screens written before this existed (the camera screen, Progress, Results, the menu) keep
/// the colours they have; the screens of P14 are the first to use it.
enum Palette {
    static let background = Color(argb: 0xFF000000)

    // labels: the iOS dark-mode ramp
    static let label = Color(argb: 0xFFFFFFFF)
    static let labelSecondary = Color(argb: 0x9EEBEBF5)
    /// Reading prose sits between label and labelSecondary: dimmer than a title, brighter than a
    /// caption, because a screen of it at 62% is tiring to read.
    static let labelBody = Color(argb: 0xCCEBEBF5)
    static let labelTertiary = Color(argb: 0x52EBEBF5)
    static let labelQuaternary = Color(argb: 0x2EEBEBF5)

    // state
    static let stateOk = Color(argb: 0xFF30D158)
    static let stateAlert = Color(argb: 0xFFFF453A)
    static let stateCaution = Color(argb: 0xFFFF9F0A)

    /// Personal records, streaks, the best-so-far line, the best week. Nothing else.
    static let achievement = Color(argb: 0xFFFC4C02)
    /// Heart-rate data and nothing else.
    static let heart = Color(argb: 0xFFFF375F)

    // material
    static let surfaceGlass = Color(argb: 0x0EFFFFFF)
    static let surfaceGlassRaised = Color(argb: 0x17FFFFFF)
    static let hairline = Color(argb: 0x1FFFFFFF)
    static let hairlineStrong = Color(argb: 0x21FFFFFF)

    // the one filled control per screen
    static let primaryFill = Color(argb: 0xFFFFFFFF)
    static let onPrimary = Color(argb: 0xFF000000)

    /// Radii, in points, from `dimens.xml`.
    static let radiusCard: CGFloat = 20
    static let radiusControl: CGFloat = 27
    static let radiusPanel: CGFloat = 30
    static let hairlineWidth: CGFloat = 0.5
}

/// Manrope, the typeface of the Android app, in the five weights it ships.
///
/// Loaded from the files themselves and not registered by name: the five static instances were cut
/// from one variable font and all five carry the name table of its lightest instance, so asking
/// the system for "Manrope-Bold" would find whichever of them registered first. Each file is read
/// into a `CGFont` of its own, which needs no name at all. A file that cannot be read falls back to
/// the system font in the same weight, so a missing resource costs the typeface and nothing else.
enum Manrope {

    enum Weight: String, CaseIterable {
        case regular, medium, semibold, bold, extrabold

        var system: Font.Weight {
            switch self {
            case .regular: return .regular
            case .medium: return .medium
            case .semibold: return .semibold
            case .bold: return .bold
            case .extrabold: return .heavy
            }
        }
    }

    private static let lock = NSLock()
    private static var loaded: [Weight: CGFont] = [:]

    private static func graphicsFont(_ weight: Weight) -> CGFont? {
        lock.lock()
        defer { lock.unlock() }
        if let cached = loaded[weight] { return cached }
        guard let url = Bundle.main.url(forResource: "manrope_\(weight.rawValue)", withExtension: "ttf"),
              let provider = CGDataProvider(url: url as CFURL),
              let font = CGFont(provider) else { return nil }
        loaded[weight] = font
        return font
    }

    static func font(_ weight: Weight, size: CGFloat) -> Font {
        guard let cg = graphicsFont(weight) else { return .system(size: size, weight: weight.system) }
        return Font(CTFontCreateWithGraphicsFont(cg, size, nil, nil))
    }
}

/// The five sizes of `type.xml`, and the eyebrow and the buttons.
enum CindyType {
    case title, title2, headline, body, callout, footnote, eyebrow, button, buttonSmall

    var weight: Manrope.Weight {
        switch self {
        case .title, .title2: return .extrabold
        case .headline, .buttonSmall: return .semibold
        case .body, .callout, .footnote: return .regular
        case .eyebrow, .button: return .bold
        }
    }

    var size: CGFloat {
        switch self {
        case .title: return 34
        case .title2: return 25
        case .headline: return 16
        case .body: return 15
        case .callout: return 14
        case .footnote: return 12
        case .eyebrow: return 11
        case .button: return 17
        case .buttonSmall: return 15
        }
    }

    /// Letter spacing in em, as `type.xml` gives it.
    var tracking: CGFloat {
        switch self {
        case .title: return -0.026
        case .title2: return -0.024
        case .headline: return -0.0125
        case .body, .callout, .footnote: return -0.007
        case .eyebrow: return 0.145
        case .button, .buttonSmall: return 0.018
        }
    }

    /// Android's line-spacing multiplier, less the line itself.
    var extraLeading: CGFloat {
        switch self {
        case .body, .callout: return 0.32
        case .footnote: return 0.4
        default: return 0
        }
    }

    var colour: Color {
        switch self {
        case .title, .title2, .headline, .button, .buttonSmall: return Palette.label
        case .body, .callout: return Palette.labelSecondary
        case .footnote, .eyebrow: return Palette.labelTertiary
        }
    }

    /// What Dynamic Type scales it against.
    var relativeTo: Font.TextStyle {
        switch self {
        case .title: return .largeTitle
        case .title2: return .title2
        case .headline: return .headline
        case .body, .button, .buttonSmall: return .body
        case .callout: return .callout
        case .footnote, .eyebrow: return .footnote
        }
    }
}

private struct CindyTextStyle: ViewModifier {
    let style: CindyType
    let colour: Color?
    @ScaledMetric private var size: CGFloat

    init(_ style: CindyType, colour: Color?) {
        self.style = style
        self.colour = colour
        _size = ScaledMetric(wrappedValue: style.size, relativeTo: style.relativeTo)
    }

    func body(content: Content) -> some View {
        content
            .font(Manrope.font(style.weight, size: size))
            .tracking(style.tracking * size)
            .lineSpacing(style.extraLeading * size * 1.2)
            .foregroundStyle(colour ?? style.colour)
    }
}

extension View {
    /// Sets the type: Manrope at the style's weight, size (scaled with Dynamic Type), spacing and
    /// colour. `colour` overrides the style's own.
    func cindy(_ style: CindyType, colour: Color? = nil) -> some View {
        modifier(CindyTextStyle(style, colour: colour))
    }

    /// A card of glass: a light film lifting off black, with a hairline round it.
    func glassCard(radius: CGFloat = Palette.radiusCard, raised: Bool = false) -> some View {
        background(
            RoundedRectangle(cornerRadius: radius)
                .fill(LinearGradient(
                    colors: [Color(argb: raised ? 0x33FFFFFF : 0x29FFFFFF),
                             raised ? Palette.surfaceGlassRaised : Palette.surfaceGlass],
                    startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.1)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: radius)
                .stroke(raised ? Palette.hairlineStrong : Palette.hairline, lineWidth: Palette.hairlineWidth)
        )
    }
}

/// The one filled control on a screen.
struct CindyPrimaryButtonStyle: ButtonStyle {
    var height: CGFloat = 54
    var small = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .cindy(small ? .buttonSmall : .button, colour: Palette.onPrimary)
            .frame(maxWidth: .infinity)
            .frame(minHeight: height)
            .background(Palette.primaryFill, in: RoundedRectangle(cornerRadius: Palette.radiusControl))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// A control of glass beside the filled one.
struct CindyGlassButtonStyle: ButtonStyle {
    var height: CGFloat = 54

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .cindy(.button)
            .frame(maxWidth: .infinity)
            .frame(minHeight: height)
            .glassCard(radius: Palette.radiusControl, raised: true)
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// The mark: three arcs, 270°, 180° and 90° of a circle, which is fifteen squats, ten push-ups and
/// five pull-ups at true proportion, each on its own faint track. Drawn from `mark_arcs.xml`.
struct MarkArcs: View {
    var body: some View {
        GeometryReader { geo in
            let k = min(geo.size.width, geo.size.height) / 112
            ZStack {
                ring(radius: 46, k: k, to: 1, opacity: 0.06)
                ring(radius: 34, k: k, to: 1, opacity: 0.06)
                ring(radius: 22, k: k, to: 1, opacity: 0.06)
                ring(radius: 46, k: k, to: 0.75, opacity: 0.30)
                ring(radius: 34, k: k, to: 0.5, opacity: 0.58)
                ring(radius: 22, k: k, to: 0.25, opacity: 1)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }

    /// A ring from twelve o'clock, clockwise, `to` of the way round.
    private func ring(radius: CGFloat, k: CGFloat, to: CGFloat, opacity: Double) -> some View {
        Circle()
            .trim(from: 0, to: to)
            .rotation(.degrees(-90))
            .stroke(Color.white.opacity(opacity), style: StrokeStyle(lineWidth: 6 * k, lineCap: .round))
            .frame(width: radius * 2 * k, height: radius * 2 * k)
    }
}
