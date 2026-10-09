import SwiftUI
import CindyCore

/// Where to stand, drawn rather than described. Port of `PlacementGuideView`.
///
/// The setup check can already tell an athlete that something is wrong, but only once they are in
/// front of the camera getting it wrong. That is a slow way to learn a thing a picture settles in a
/// second, and it is worst for exactly the person least sure of what the app wants from them.
///
/// A side elevation is the only view that carries the two facts that matter at once: how far back to
/// stand, and that the phone wants to be up off the floor. A photo of a room would carry neither,
/// because it would be someone else's room.
///
/// Why 2–3 metres: a phone in portrait sees roughly 60–65 degrees vertically. Fitting a 1.8 m
/// athlete plus the headroom a pull-up bar needs, call it 2.4 m of wall, puts the camera about
/// `1.2 / tan(31°) ≈ 2 m` away, and three gives margin for a taller athlete and a higher bar.
/// Deliberately a range, and confirmed by the setup check rather than trusted: the exact field of
/// view is a property of the handset, which this cannot know.
struct PlacementDiagram: View {

    // The floor, and everything else, as fractions of the view, so it scales anywhere.
    private let ground: CGFloat = 0.78
    private let phoneX: CGFloat = 0.09
    private let lensY: CGFloat = 0.435
    private let athleteX: CGFloat = 0.66
    private let dimensionY: CGFloat = 0.90
    /// Where the upper edge of the shot leaves the top of the drawing: the ray from the lens to
    /// (0.823, 0.03), continued to y = 0.
    private let topExit: CGFloat = 0.877

    private let ink = Palette.label
    private let dim = Palette.labelSecondary
    private let faint = Palette.labelQuaternary

    var body: some View {
        Canvas { context, size in
            func x(_ f: CGFloat) -> CGFloat { f * size.width }
            func y(_ f: CGFloat) -> CGFloat { f * size.height }
            func line(_ a: CGPoint, _ b: CGPoint, _ colour: Color, _ width: CGFloat) {
                var path = Path()
                path.move(to: a)
                path.addLine(to: b)
                context.stroke(path, with: .color(colour), style: StrokeStyle(lineWidth: width, lineCap: .round))
            }
            func label(_ text: String, at point: CGPoint, anchor: UnitPoint, colour: Color, size: CGFloat) {
                context.draw(Text(text).font(Manrope.font(.regular, size: size)).foregroundColor(colour),
                             at: point, anchor: anchor)
            }

            // The wedge goes down first so everything else sits inside the shot rather than under it.
            var wedge = Path()
            wedge.move(to: CGPoint(x: x(phoneX), y: y(lensY)))
            wedge.addLine(to: CGPoint(x: x(topExit), y: 0))
            wedge.addLine(to: CGPoint(x: size.width, y: 0))
            wedge.addLine(to: CGPoint(x: size.width, y: y(ground)))
            wedge.addLine(to: CGPoint(x: x(0.34), y: y(ground)))
            wedge.closeSubpath()
            context.fill(wedge, with: .color(Color.white.opacity(14.0 / 255)))
            line(CGPoint(x: x(phoneX), y: y(lensY)), CGPoint(x: x(0.823), y: y(0.03)), dim, 1)
            line(CGPoint(x: x(phoneX), y: y(lensY)), CGPoint(x: x(0.34), y: y(ground)), dim, 1)
            label("head and feet both in shot", at: CGPoint(x: x(0.60), y: y(0.155)), anchor: .center,
                  colour: dim, size: 11)

            // The floor.
            line(CGPoint(x: x(0.04), y: y(ground)), CGPoint(x: x(0.97), y: y(ground)), faint, 1.5)

            // The phone, stood on something rather than lying on the floor.
            context.fill(Path(CGRect(x: x(0.055), y: y(0.68), width: x(0.125) - x(0.055), height: y(ground) - y(0.68))),
                         with: .color(Color(argb: 0x3CFFFFFF)))
            let shell = CGRect(x: x(0.072), y: y(0.40), width: x(0.108) - x(0.072), height: y(0.68) - y(0.40))
            context.fill(Path(roundedRect: shell, cornerRadius: 3), with: .color(Color(argb: 0xE6FFFFFF)))
            context.fill(Path(CGRect(x: x(0.076), y: y(0.42), width: x(0.104) - x(0.076), height: y(0.66) - y(0.42))),
                         with: .color(Color(argb: 0xFF16191E)))
            context.fill(Path(ellipseIn: CGRect(x: x(phoneX) - 2.5, y: y(lensY) - 2.5, width: 5, height: 5)),
                         with: .color(ink))
            label("waist high or more", at: CGPoint(x: x(0.02), y: y(0.36)), anchor: .leading, colour: dim, size: 11)

            // The athlete.
            let cx = x(athleteX)
            let head = 0.047 * size.height
            context.stroke(Path(ellipseIn: CGRect(x: cx - head, y: y(0.22) - head, width: head * 2, height: head * 2)),
                           with: .color(.white), lineWidth: 2)
            line(CGPoint(x: cx, y: y(0.275)), CGPoint(x: cx, y: y(0.53)), .white, 2)
            line(CGPoint(x: cx, y: y(0.31)), CGPoint(x: x(athleteX - 0.055), y: y(0.45)), .white, 2)
            line(CGPoint(x: cx, y: y(0.31)), CGPoint(x: x(athleteX + 0.055), y: y(0.45)), .white, 2)
            line(CGPoint(x: cx, y: y(0.53)), CGPoint(x: x(athleteX - 0.05), y: y(ground)), .white, 2)
            line(CGPoint(x: cx, y: y(0.53)), CGPoint(x: x(athleteX + 0.05), y: y(ground)), .white, 2)

            // The dimension line: how far back to stand, with the figure that answers the question.
            line(CGPoint(x: x(phoneX), y: y(ground + 0.02)), CGPoint(x: x(phoneX), y: y(dimensionY + 0.03)), faint, 1)
            line(CGPoint(x: cx, y: y(ground + 0.02)), CGPoint(x: cx, y: y(dimensionY + 0.03)), faint, 1)
            arrow(context, from: x(0.30), to: x(phoneX), y: y(dimensionY), colour: dim)
            arrow(context, from: x(0.45), to: cx, y: y(dimensionY), colour: dim)
            label("2–3 m  ·  7–10 ft", at: CGPoint(x: x(0.375), y: y(dimensionY + 0.02)), anchor: .bottom,
                  colour: ink, size: 13)
        }
        .accessibilityElement()
        .accessibilityLabel("A side view: the phone stands waist high or more, two to three metres from you, "
                            + "with your head and feet both in shot.")
    }

    /// One half of the dimension line, with a head at the `to` end.
    private func arrow(_ context: GraphicsContext, from: CGFloat, to: CGFloat, y: CGFloat, colour: Color) {
        var path = Path()
        path.move(to: CGPoint(x: from, y: y))
        path.addLine(to: CGPoint(x: to, y: y))
        // The head is two short strokes back from the tip, 0.4 radians either side of the line.
        let head: CGFloat = 5
        let angle: CGFloat = to >= from ? 0 : .pi
        for turn in [CGFloat(-0.4), 0.4] {
            path.move(to: CGPoint(x: to, y: y))
            path.addLine(to: CGPoint(x: to - head * cos(angle + turn), y: y - head * sin(angle + turn)))
        }
        context.stroke(path, with: .color(colour), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
    }
}

/// The three placement facts, one per row, in the type of the first-launch pages. They come from
/// `PlacementFacts`, which the sheet that opens before the first setup check also draws, so the
/// two cannot give different advice about the one thing the athlete has to get right.
struct PlacementFactRows: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(PlacementFacts.all, id: \.text) { fact in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: fact.symbol)
                        .foregroundStyle(fact.warning ? Palette.stateAlert : Palette.labelSecondary)
                        .frame(width: 22)
                        .accessibilityHidden(true)
                    Text(fact.text).cindy(.body, colour: Palette.labelBody)
                }
            }
        }
    }
}
