import SwiftUI
import UIKit
import CindyCore

/// The name of the coordinate space the camera screen's controls are measured in, and the tour is
/// laid out in.
enum TourSpace {
    static let name = "hud"
}

/// Where the camera screen's controls are, in `TourSpace`, collected as they are laid out. A control
/// that is not on the screen reports nothing, and the tour leaves it out.
struct TourFramesKey: PreferenceKey {
    static var defaultValue: [HudTour.Target: CGRect] = [:]

    static func reduce(value: inout [HudTour.Target: CGRect], nextValue: () -> [HudTour.Target: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

extension View {
    /// Marks a control as one the tour can point at.
    func tourTarget(_ target: HudTour.Target) -> some View {
        background(
            GeometryReader { geo in
                Color.clear.preference(key: TourFramesKey.self,
                                       value: [target: geo.frame(in: .named(TourSpace.name))])
            }
        )
    }
}

private struct CaptionHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// A tour of the camera screen: the screen dimmed, one control left bright, and a card that says
/// what it is for. `SpotlightTour` decides which control, and where the card goes; this draws it.
///
/// It is a layer over the camera screen and not a screen of its own, because the camera is what it
/// points at. While it is showing it takes every touch: a tap anywhere moves on, so nothing it
/// highlights can be pressed by accident, START least of all.
///
/// The window is worked out from where the control is on every pass, so a status line that wraps, or
/// a band that resizes, moves the light with it.
struct SpotlightOverlay: View {
    let tour: SpotlightTour
    let frames: [HudTour.Target: CGRect]
    let advance: () -> Void
    let skip: () -> Void

    @State private var captionHeight: CGFloat = 160

    var body: some View {
        GeometryReader { geo in
            let origin = geo.frame(in: .named(TourSpace.name)).origin
            let screen = SpotlightRect(x: 0, y: 0, width: Float(geo.size.width), height: Float(geo.size.height))
            let window = windowRect(origin: origin, screen: screen)
            let top = CGFloat(SpotlightTour.captionTop(
                window: window.map(spotlight) ?? SpotlightRect(x: 0, y: 0, width: 0, height: 0),
                captionHeight: Float(captionHeight), screenHeight: screen.height))
            ZStack(alignment: .top) {
                dim(window)
                if let step = tour.current {
                    caption(step)
                        .offset(y: top)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture(perform: advance)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape, skip)
        .onAppear { announce() }
        .onChange(of: tour.stepIndex) { _, _ in announce() }
        .accessibilityIdentifier("tour")
    }

    /// Said on every step rather than left to be found: a screen reader cannot see where the light
    /// has gone.
    private func announce() {
        if let text = tour.announcement {
            UIAccessibility.post(notification: .announcement, argument: text)
        }
    }

    private func spotlight(_ rect: CGRect) -> SpotlightRect {
        SpotlightRect(x: Float(rect.minX), y: Float(rect.minY), width: Float(rect.width), height: Float(rect.height))
    }

    /// The bright window around the current control, in this layer's own coordinates, which start at
    /// `origin` in the camera screen's.
    private func windowRect(origin: CGPoint, screen: SpotlightRect) -> CGRect? {
        guard let step = tour.current, let frame = frames[step.target] else { return nil }
        let control = SpotlightRect(x: Float(frame.minX - origin.x), y: Float(frame.minY - origin.y),
                                    width: Float(frame.width), height: Float(frame.height))
        let w = SpotlightTour.window(around: control, in: screen)
        return CGRect(x: CGFloat(w.x), y: CGFloat(w.y), width: CGFloat(w.width), height: CGFloat(w.height))
    }

    /// Everything but the window: two shapes, filled where exactly one of them is.
    private func dim(_ window: CGRect?) -> some View {
        Canvas { context, size in
            var path = Path(CGRect(origin: .zero, size: size))
            var ring = Path()
            if let window {
                let radius = CGFloat(SpotlightTour.cornerRadius(of: spotlight(window)))
                let corner = CGSize(width: radius, height: radius)
                path.addRoundedRect(in: window, cornerSize: corner)
                ring.addRoundedRect(in: window, cornerSize: corner)
            }
            context.fill(path, with: .color(Color(argb: 0xC8000000)), style: FillStyle(eoFill: true))
            context.stroke(ring, with: .color(Palette.label), lineWidth: 2)
        }
        .accessibilityHidden(true)
    }

    private func caption(_ step: HudTour.Step) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(step.title).cindy(.headline)
            Text(step.body).cindy(.callout, colour: Palette.labelBody).padding(.top, 6)
            HStack {
                Button(action: skip) {
                    Text(SpotlightTour.skipLabel).cindy(.eyebrow, colour: Palette.labelSecondary)
                        .frame(minHeight: 48)
                }
                .accessibilityLabel(SpotlightTour.skipDescription)
                Spacer()
                Button(tour.nextLabel, action: advance)
                    .buttonStyle(CindyPrimaryButtonStyle(height: 44, small: true))
                    .frame(width: 110)
            }
            .padding(.top, 8)
        }
        .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 10)
        .background(RoundedRectangle(cornerRadius: Palette.radiusPanel).fill(Color(argb: 0xF2141518)))
        .overlay(RoundedRectangle(cornerRadius: Palette.radiusPanel)
            .stroke(Palette.hairlineStrong, lineWidth: Palette.hairlineWidth))
        .padding(.horizontal, 16)
        .background(
            GeometryReader { geo in
                Color.clear.preference(key: CaptionHeightKey.self, value: geo.size.height)
            }
        )
        .onPreferenceChange(CaptionHeightKey.self) { captionHeight = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(SpotlightTour.paneTitle)
    }
}
