import SwiftUI
import CindyCore

// The results page's four charts, drawn in `Canvas` over the models in CindyCore. The models own
// the geometry and the touch; these only paint what they say and pass the finger through.

/// White for pull-ups, then ever fainter for push-ups and squats: the movements are told apart by
/// weight of ink, as on Android, so no colour has to be learned.
enum Ink {
    static let label = Color.white
    static let secondary = Color.white.opacity(0.62)
    static let tertiary = Color.white.opacity(0.32)
    static let quaternary = Color.white.opacity(0.18)
    static let hairline = Color.white.opacity(0.12)
    static let heart = Color(red: 1, green: 0.216, blue: 0.373)
    static let achievement = Color(red: 0.988, green: 0.298, blue: 0.008)

    static func movement(_ m: Exercise) -> Color {
        switch m {
        case .pullup: return label
        case .pushup: return secondary
        case .squat: return tertiary
        }
    }

    static func tint(_ t: TimelineTint) -> Color {
        switch t {
        case .reps: return label
        case .heart: return heart
        case .energy: return secondary
        }
    }
}

/// Hands a finger's down, move and up to a chart model. A vertical gesture never becomes a drag in
/// the model, so the scroll view around the chart keeps it.
struct ChartTouch: ViewModifier {
    let down: (CGPoint) -> Void
    let move: (CGPoint) -> Void
    let up: (CGPoint) -> Void
    @State private var active = false

    func body(content: Content) -> some View {
        content.simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { v in
                    if !active {
                        active = true
                        down(v.startLocation)
                    }
                    move(v.location)
                }
                .onEnded { v in
                    active = false
                    up(v.location)
                })
    }
}

extension View {
    func chartTouch(down: @escaping (CGPoint) -> Void, move: @escaping (CGPoint) -> Void,
                    up: @escaping (CGPoint) -> Void) -> some View {
        modifier(ChartTouch(down: down, move: move, up: up))
    }
}

func rect(_ r: ChartRect) -> CGRect {
    CGRect(x: r.left, y: r.top, width: r.width, height: r.height)
}

// MARK: - the round track

/// One pill per round, ten to a row.
struct RoundTrackView: View {
    @ObservedObject var vm: ResultsViewModel

    var body: some View {
        GeometryReader { geo in
            let width = Double(geo.size.width)
            Canvas { context, _ in
                _ = vm.revision
                draw(&context, width: width)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .chartTouch(
                down: { vm.track.touchDown(x: Double($0.x), y: Double($0.y)) },
                move: { vm.track.touchMove(x: Double($0.x), y: Double($0.y), in: width) },
                up: { vm.track.touchUp(x: Double($0.x), y: Double($0.y), in: width) })
        }
        .frame(height: vm.track.height)
        // One stop for each round, which activating selects.
        .accessibilityRepresentation {
            VStack {
                ForEach(Array(vm.track.stops.enumerated()), id: \.offset) { i, text in
                    Button(text) { vm.track.activate(stop: i) }
                        .accessibilityAddTraits(vm.trackSelected == i ? .isSelected : [])
                }
            }
        }
    }

    private func draw(_ context: inout GraphicsContext, width: Double) {
        let model = vm.track
        for i in 0..<model.pillCount {
            let pill = rect(model.pill(i, in: width))
            let shape = Path(roundedRect: pill, cornerRadius: RoundTrackModel.corner)
            let selected = vm.trackSelected == i
            let dimmed = vm.trackSelected != nil && !selected
            var inner = context
            inner.opacity = dimmed ? 0.4 : 1
            inner.fill(shape, with: .color(Ink.quaternary.opacity(0.4)))
            inner.drawLayer { layer in
                layer.clip(to: shape)
                for s in model.segments(round: i, pillWidth: Double(pill.width)) {
                    let filled = CGRect(x: pill.minX + s.start, y: pill.minY,
                                        width: s.length * s.reached, height: pill.height)
                    layer.fill(Path(filled), with: .color(Ink.movement(s.movement)))
                    // A hairline where one movement gives way to the next.
                    if s.start > 0 {
                        layer.fill(Path(CGRect(x: pill.minX + s.start - 0.5, y: pill.minY, width: 1, height: pill.height)),
                                   with: .color(Color.black))
                    }
                }
            }
            inner.stroke(shape, with: .color(selected ? Ink.label : Ink.tertiary), lineWidth: selected ? 2 : 1)
        }
    }
}

// MARK: - the heart-rate zone bar

struct ZoneBarView: View {
    @ObservedObject var vm: ResultsViewModel

    var body: some View {
        GeometryReader { geo in
            let width = Double(geo.size.width)
            Canvas { context, size in
                _ = vm.revision
                let model = vm.zones
                let top = (size.height - ZoneBarModel.barHeight) / 2
                for (z, span) in model.spans(in: width).enumerated() where span.right > span.left {
                    let selected = vm.zoneSelected
                    let alpha = ZoneBarModel.alpha[z] * ((selected == nil || selected == z) ? 1 : ZoneBarModel.dim)
                    let gap = ZoneBarModel.gap / 2
                    let r = CGRect(x: span.left + gap, y: top, width: max(span.right - span.left - gap * 2, 1),
                                   height: ZoneBarModel.barHeight)
                    context.fill(Path(roundedRect: r, cornerRadius: 4), with: .color(Ink.heart.opacity(alpha)))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .chartTouch(
                down: { vm.zones.touchDown(x: Double($0.x), y: Double($0.y)) },
                move: { vm.zones.touchMove(x: Double($0.x), y: Double($0.y), in: width) },
                up: { vm.zones.touchUp(x: Double($0.x), y: Double($0.y), in: width) })
        }
        .frame(height: ZoneBarModel.touchHeight)
        .accessibilityRepresentation {
            VStack {
                ForEach(Array(vm.zones.stops.enumerated()), id: \.offset) { i, text in
                    Button(text) { vm.zones.activate(stop: i) }
                }
            }
        }
    }
}

// MARK: - the round splits

struct RoundSplitsView: View {
    @ObservedObject var vm: ResultsViewModel
    static let height = 200.0

    var body: some View {
        GeometryReader { geo in
            let width = Double(geo.size.width)
            Canvas { context, size in
                _ = vm.revision
                draw(&context, width: width, height: Double(size.height))
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .chartTouch(
                down: { vm.splits.touchDown(x: Double($0.x), y: Double($0.y)) },
                move: { vm.splits.touchMove(x: Double($0.x), y: Double($0.y), width: width) },
                up: { vm.splits.touchUp(x: Double($0.x), y: Double($0.y), width: width) })
        }
        .frame(height: Self.height)
        .accessibilityRepresentation {
            VStack {
                ForEach(Array(vm.splits.stops.enumerated()), id: \.offset) { i, text in
                    Button(text) { vm.splits.activate(stop: i) }
                        .accessibilityAddTraits(vm.splitsSelected == i ? .isSelected : [])
                }
            }
        }
    }

    private func draw(_ context: inout GraphicsContext, width: Double, height: Double) {
        let m = vm.splits
        guard m.barCount > 0 else { return }
        let plot = m.plot(width: width, height: height)
        let slot = m.slot(width: width)
        let barWidth = max(slot * 0.62, 2)
        let selected = vm.splitsSelected

        // The dashed average, labelled at its right.
        if m.averageLabel != nil {
            let y = m.y(forMs: m.averageMs, plot: plot)
            var line = Path()
            line.move(to: CGPoint(x: 0, y: y))
            line.addLine(to: CGPoint(x: width, y: y))
            context.stroke(line, with: .color(Ink.tertiary), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
        }

        for (i, bar) in m.bars.enumerated() {
            let cx = m.centreX(i, width: width)
            let fade = (selected == nil || selected == i) ? 1.0 : 0.4
            let top = m.y(forMs: bar.ms, plot: plot)
            let frame = CGRect(x: cx - barWidth / 2, y: top, width: barWidth, height: plot.bottom - top)
            if bar.unfinished {
                // The round still under way is an outline: it has no finishing time to stand for.
                context.stroke(Path(roundedRect: frame, cornerRadius: 3), with: .color(Ink.secondary.opacity(fade)),
                               lineWidth: 1.5)
            } else if let sets = bar.sets, !sets.isEmpty {
                // Stacked by movement, pull-ups at the bottom.
                var y = plot.bottom
                for (k, ms) in sets.enumerated() {
                    let h = Double(ms) / Double(m.maxMs) * plot.height
                    let part = CGRect(x: frame.minX, y: y - h, width: frame.width, height: h)
                    let ink = Exercise.allCases.indices.contains(k) ? Ink.movement(Exercise.allCases[k]) : Ink.label
                    context.fill(Path(part), with: .color(ink.opacity(fade)))
                    y -= h
                }
            } else {
                context.fill(Path(roundedRect: frame, cornerRadius: 3),
                             with: .color((i == m.fastest ? Color.accent : Ink.secondary).opacity(fade)))
            }
            if i < m.reference.count, let ms = m.reference[i] {
                let y = m.y(forMs: ms, plot: plot)
                var tick = Path()
                tick.move(to: CGPoint(x: cx - barWidth / 2 - 3, y: y))
                tick.addLine(to: CGPoint(x: cx + barWidth / 2 + 3, y: y))
                context.stroke(tick, with: .color(Ink.achievement.opacity(fade)), lineWidth: 2)
            }
        }

        for i in m.numberIndices(width: width) {
            let text = Text(m.roundLabels[i]).font(.system(size: 11, design: .monospaced))
                .foregroundStyle(i == selected ? Ink.label : Ink.tertiary)
            context.draw(text, at: CGPoint(x: m.centreX(i, width: width), y: height - 8))
        }
    }
}

// MARK: - the session timeline

struct SessionTimelineView: View {
    @ObservedObject var vm: ResultsViewModel

    var body: some View {
        GeometryReader { geo in
            let width = Double(geo.size.width)
            Canvas { context, _ in
                _ = vm.revision
                draw(&context, width: width)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .chartTouch(
                down: { vm.timeline.touchDown(x: Double($0.x), y: Double($0.y)) },
                move: { vm.timeline.touchMove(x: Double($0.x), y: Double($0.y), width: width) },
                up: { vm.timeline.touchUp(x: Double($0.x), y: Double($0.y), width: width) })
        }
        .frame(height: vm.timeline.height)
        .accessibilityRepresentation {
            VStack {
                ForEach(Array(vm.timeline.stops.enumerated()), id: \.offset) { i, stop in
                    Button(stop.description) { vm.timeline.activate(stop: i) }
                }
            }
        }
    }

    private func draw(_ context: inout GraphicsContext, width: Double) {
        let m = vm.timeline
        guard m.laneCount > 0 else { return }
        let plot = m.plot(width: width)
        let bounds = m.laneBounds()

        for (i, lane) in m.lanes.enumerated() {
            let b = bounds[i]
            let label = Text(lane.label).font(.system(size: 10, weight: .bold)).foregroundStyle(Ink.tertiary)
            context.draw(label, at: CGPoint(x: plot.left, y: b.top - 9), anchor: .leading)

            for tick in m.laneTicks[i] {
                var line = Path()
                let y = m.y(lane: i, value: tick)
                line.move(to: CGPoint(x: plot.left, y: y))
                line.addLine(to: CGPoint(x: plot.right, y: y))
                context.stroke(line, with: .color(Ink.hairline), lineWidth: 0.5)
            }
            let low = Text(m.tickLabelLow[i]).font(.system(size: 10, design: .monospaced)).foregroundStyle(Ink.tertiary)
            let high = Text(m.tickLabelHigh[i]).font(.system(size: 10, design: .monospaced)).foregroundStyle(Ink.tertiary)
            context.draw(low, at: CGPoint(x: width, y: b.bottom), anchor: .trailing)
            context.draw(high, at: CGPoint(x: width, y: b.top), anchor: .trailing)

            // Round ends run through every lane.
            for end in m.roundEnds {
                var line = Path()
                let x = m.x(forClock: end, width: width)
                line.move(to: CGPoint(x: x, y: b.top))
                line.addLine(to: CGPoint(x: x, y: b.bottom))
                context.stroke(line, with: .color(Ink.hairline), lineWidth: 0.5)
            }

            // The dashed comparison, then this session over it.
            if !lane.comparison.isEmpty {
                context.stroke(series(lane.comparison, lane: i, stepped: lane.stepped, hold: false, width: width),
                               with: .color(Ink.tertiary), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            }
            for (r, run) in lane.runs.enumerated() {
                let hold = lane.stepped && r == lane.runs.count - 1
                let path = series(run.points, lane: i, stepped: lane.stepped, hold: hold, width: width)
                context.stroke(path, with: .color(Ink.tint(lane.tint)),
                               style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round,
                                                  dash: run.dashed ? [5, 4] : []))
                if lane.markPoints {
                    for p in run.points {
                        let c = CGPoint(x: m.x(forClock: p.clockMs, width: width), y: m.y(lane: i, value: p.value))
                        context.fill(Path(ellipseIn: CGRect(x: c.x - 2.5, y: c.y - 2.5, width: 5, height: 5)),
                                     with: .color(Ink.tint(lane.tint)))
                    }
                }
            }
        }

        // The axis under the lanes: nought, and where the session ended.
        let axisY = m.height - SessionTimelineChartModel.axisHeight / 2
        context.draw(Text("0:00").font(.system(size: 10, design: .monospaced)).foregroundStyle(Ink.tertiary),
                     at: CGPoint(x: plot.left, y: axisY), anchor: .leading)
        context.draw(Text(m.endLabel).font(.system(size: 10, design: .monospaced)).foregroundStyle(Ink.tertiary),
                     at: CGPoint(x: plot.right, y: axisY), anchor: .trailing)

        // One cursor through every lane, with a dot where each line crosses it.
        if let at = vm.cursorMs {
            let x = m.x(forClock: at, width: width)
            var line = Path()
            line.move(to: CGPoint(x: x, y: bounds.first?.top ?? 0))
            line.addLine(to: CGPoint(x: x, y: bounds.last?.bottom ?? 0))
            context.stroke(line, with: .color(Ink.label), lineWidth: 1)
            for (i, lane) in m.lanes.enumerated() {
                if let v = m.value(lane: i, at: at) {
                    let c = CGPoint(x: x, y: m.y(lane: i, value: v))
                    context.fill(Path(ellipseIn: CGRect(x: c.x - 4, y: c.y - 4, width: 8, height: 8)),
                                 with: .color(Ink.tint(lane.tint)))
                }
            }
        }
    }

    /// A line through `points`: stepped (a value is held until the next one) or straight. A held
    /// last run goes on to the end of the clock.
    private func series(_ points: [TimelinePoint], lane: Int, stepped: Bool, hold: Bool, width: Double) -> Path {
        let m = vm.timeline
        var path = Path()
        for (k, p) in points.enumerated() {
            let x = m.x(forClock: p.clockMs, width: width)
            let y = m.y(lane: lane, value: p.value)
            if k == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                if stepped { path.addLine(to: CGPoint(x: x, y: m.y(lane: lane, value: points[k - 1].value))) }
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        if hold, let last = points.last {
            path.addLine(to: CGPoint(x: m.x(forClock: m.durationMs, width: width), y: m.y(lane: lane, value: last.value)))
        }
        return path
    }
}
