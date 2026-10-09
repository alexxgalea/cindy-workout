import SwiftUI
import CindyCore

// The Progress screen's three drawn views, in `Canvas` over the models in CindyCore. The models own
// the geometry and the touch; these only paint what they say and pass the finger through.

// MARK: - the week strip

/// One week as seven circles.
struct WeekStripView: View {
    let weekStart: LocalDate
    let trained: Set<LocalDate>
    let today: LocalDate

    var body: some View {
        let days = WeekStrip.days(weekStart: weekStart, trained: trained, today: today)
        let initials = Calendar.current.veryShortWeekdaySymbols
        Canvas { context, size in
            let column = size.width / 7
            let radius = min(column * 0.30, 14)
            let cy = 36.0
            for (i, day) in days.enumerated() {
                let cx = column * (Double(i) + 0.5)
                // Calendar's symbols start on Sunday; DayOfWeek counts Monday as 1.
                let initial = initials[day.date.dayOfWeek.rawValue % 7]
                context.draw(Text(initial).font(.system(size: 11, weight: .semibold)).foregroundStyle(Ink.tertiary),
                             at: CGPoint(x: cx, y: 12))
                let circle = CGRect(x: cx - radius, y: cy - radius, width: radius * 2, height: radius * 2)
                switch day.state {
                case .trained(let isToday):
                    context.fill(Path(ellipseIn: circle), with: .color(Ink.achievement))
                    if isToday {
                        context.stroke(Path(ellipseIn: circle.insetBy(dx: -3, dy: -3)), with: .color(Ink.label), lineWidth: 2)
                    }
                case .today:
                    context.stroke(Path(ellipseIn: circle), with: .color(Ink.label), lineWidth: 2)
                case .missed:
                    context.stroke(Path(ellipseIn: circle), with: .color(Ink.quaternary), lineWidth: 1.5)
                case .coming:
                    context.fill(Path(ellipseIn: CGRect(x: cx - 2, y: cy - 2, width: 4, height: 4)),
                                 with: .color(Ink.quaternary))
                }
            }
        }
        .frame(height: 56)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(WeekStrip.describe(weekStart: weekStart, trained: trained))
    }
}

// MARK: - the month calendar

/// A month with the trained days filled in.
struct CalendarGridView: View {
    @ObservedObject var vm: ProgressViewModel

    var body: some View {
        GeometryReader { geo in
            let width = Double(geo.size.width)
            Canvas { context, size in
                _ = vm.revision
                draw(&context, width: width)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .chartTouch(
                down: { vm.calendar.touchDown(x: Double($0.x), y: Double($0.y)) },
                move: { _ in },
                up: { vm.calendar.touchUp(x: Double($0.x), y: Double($0.y), width: width) })
        }
        .aspectRatio(CGFloat(7) / CGFloat(CalendarModel.weeksShown + 1), contentMode: .fit)
        .accessibilityRepresentation {
            VStack {
                ForEach(Array(vm.calendar.stops.enumerated()), id: \.offset) { i, stop in
                    Button(stop.spoken) { vm.calendar.activate(stop: i) }
                }
            }
            .accessibilityLabel(vm.calendar.summary)
        }
    }

    private func draw(_ context: inout GraphicsContext, width: Double) {
        let m = vm.calendar
        let cell = m.cellSize(width: width)
        let radius = cell * 0.34
        let initials = Calendar.current.veryShortWeekdaySymbols

        for (i, day) in m.headerDays().enumerated() {
            context.draw(Text(initials[day.rawValue % 7]).font(.system(size: 11)).foregroundStyle(Ink.secondary),
                         at: CGPoint(x: cell * (Double(i) + 0.5), y: cell * 0.5))
        }
        for c in m.cells() {
            let cx = cell * (Double(c.column) + 0.5)
            let cy = cell * (Double(c.row) + 0.5)
            let circle = CGRect(x: cx - radius, y: cy - radius, width: radius * 2, height: radius * 2)
            let ink: Color
            switch c.state {
            case .streak:
                context.fill(Path(ellipseIn: circle), with: .color(Ink.achievement))
                ink = .black
            case .trained:
                context.fill(Path(ellipseIn: circle), with: .color(.white))
                ink = .black
            case .today:
                context.stroke(Path(ellipseIn: circle), with: .color(.white), lineWidth: 2)
                ink = .white
            case .future: ink = Ink.quaternary
            case .past: ink = .white
            }
            let weight: Font.Weight = c.trained || c.isToday ? .bold : .regular
            context.draw(Text("\(c.day)").font(.system(size: 13, weight: weight)).foregroundStyle(ink),
                         at: CGPoint(x: cx, y: cy))
        }
    }
}

// MARK: - the progress chart

/// A line of attempts with a step line for the best so far, or one bar per week.
struct ProgressChartView: View {
    @ObservedObject var vm: ProgressViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var reveal: CGFloat = 1
    static let height = 200.0

    var body: some View {
        GeometryReader { geo in
            let width = Double(geo.size.width)
            let height = Double(geo.size.height)
            Canvas { context, _ in
                _ = vm.revision
                draw(&context, width: width, height: height)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .chartTouch(
                down: { vm.chart.touchDown(x: Double($0.x), y: Double($0.y)) },
                move: { vm.chart.touchMove(x: Double($0.x), y: Double($0.y), width: width, height: height) },
                up: { vm.chart.touchUp(x: Double($0.x), y: Double($0.y), width: width, height: height) })
        }
        .frame(height: Self.height)
        // The line draws itself in from the left; the phone's reduced-motion setting skips that.
        .mask(alignment: .leading) {
            GeometryReader { geo in Rectangle().frame(width: geo.size.width * reveal) }
        }
        .onChange(of: vm.revision) { _, _ in
            guard !reduceMotion, vm.page.progress?.chart != nil else { return }
            reveal = 0
            withAnimation(.easeOut(duration: 0.65)) { reveal = 1 }
        }
        .accessibilityRepresentation {
            VStack {
                ForEach(Array(vm.chart.stops.enumerated()), id: \.offset) { i, text in
                    Button(text) { vm.chart.activate(stop: i) }
                        .accessibilityAddTraits(vm.selected == i ? .isSelected : [])
                }
            }
            .accessibilityLabel(vm.page.progress?.spoken ?? "")
        }
    }

    private func draw(_ context: inout GraphicsContext, width: Double, height: Double) {
        let m = vm.chart
        guard m.pointCount > 0 else { return }
        let plot = m.plot(width: width, height: height)
        guard plot.width > 0, plot.height > 0 else { return }
        let xs = m.xs(width: width, height: height)
        let ys = m.ys(width: width, height: height)

        // The axes: a hairline and a label for each tick, and the dates at the two edges.
        for tick in m.ticks {
            let y = m.y(forValue: tick, plot: plot)
            var line = Path()
            line.move(to: CGPoint(x: plot.left, y: y))
            line.addLine(to: CGPoint(x: plot.right, y: y))
            context.stroke(line, with: .color(Ink.hairline), lineWidth: 0.5)
            context.draw(Text(m.label(forTick: tick)).font(.system(size: 11, weight: .semibold)).foregroundStyle(Ink.tertiary),
                         at: CGPoint(x: width, y: y), anchor: .trailing)
        }
        let baseline = height - 8
        context.draw(Text(m.edgeLabels.first).font(.system(size: 11, weight: .semibold)).foregroundStyle(Ink.tertiary),
                     at: CGPoint(x: plot.left, y: baseline), anchor: .leading)
        context.draw(Text(m.edgeLabels.second).font(.system(size: 11, weight: .semibold)).foregroundStyle(Ink.tertiary),
                     at: CGPoint(x: plot.right, y: baseline), anchor: .trailing)

        if m.mode == .line {
            drawLine(&context, m, plot, xs, ys, width: width, height: height)
        } else {
            drawBars(&context, m, width: width, height: height)
        }

        if m.mode == .line, let s = vm.selected, xs.indices.contains(s) {
            var cursor = Path()
            cursor.move(to: CGPoint(x: xs[s], y: plot.top))
            cursor.addLine(to: CGPoint(x: xs[s], y: plot.bottom))
            context.stroke(cursor, with: .color(Ink.tertiary), lineWidth: 1)
            let dot = CGRect(x: xs[s] - 6, y: ys[s] - 6, width: 12, height: 12)
            context.fill(Path(ellipseIn: dot), with: .color(Ink.label))
            context.stroke(Path(ellipseIn: dot), with: .color(Color.appBackground), lineWidth: 2)
        }
    }

    private func drawLine(_ context: inout GraphicsContext, _ m: ProgressChartModel, _ plot: ChartRect,
                          _ xs: [Double], _ ys: [Double], width: Double, height: Double) {
        let n = xs.count
        if !m.invertY && n > 1 {
            var fill = Path()
            fill.move(to: CGPoint(x: xs[0], y: plot.bottom))
            for i in 0..<n { fill.addLine(to: CGPoint(x: xs[i], y: ys[i])) }
            fill.addLine(to: CGPoint(x: xs[n - 1], y: plot.bottom))
            fill.closeSubpath()
            context.fill(fill, with: .linearGradient(
                Gradient(colors: [Color.white.opacity(0.18), Color.white.opacity(0)]),
                startPoint: CGPoint(x: 0, y: plot.top), endPoint: CGPoint(x: 0, y: plot.bottom)))
        }
        if n > 1 {
            var line = Path()
            line.move(to: CGPoint(x: xs[0], y: ys[0]))
            for i in 1..<n { line.addLine(to: CGPoint(x: xs[i], y: ys[i])) }
            context.stroke(line, with: .color(Ink.label), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
        let steps = m.bestSteps(width: width, height: height)
        if let first = steps.first {
            var best = Path()
            best.move(to: CGPoint(x: first.x, y: first.y))
            for s in steps.dropFirst() { best.addLine(to: CGPoint(x: s.x, y: s.y)) }
            context.stroke(best, with: .color(Ink.achievement),
                           style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
        for i in 0..<n {
            switch m.mark(i) {
            case .ring:
                context.stroke(Path(ellipseIn: CGRect(x: xs[i] - 3.5, y: ys[i] - 3.5, width: 7, height: 7)),
                               with: .color(Ink.secondary), lineWidth: 1.5)
            case .record:
                context.fill(Path(ellipseIn: CGRect(x: xs[i] - 4.5, y: ys[i] - 4.5, width: 9, height: 9)),
                             with: .color(Ink.achievement))
            case .plain:
                context.fill(Path(ellipseIn: CGRect(x: xs[i] - 3, y: ys[i] - 3, width: 6, height: 6)),
                             with: .color(Ink.label))
            }
        }
    }

    private func drawBars(_ context: inout GraphicsContext, _ m: ProgressChartModel, width: Double, height: Double) {
        for case let bar? in m.bars(width: width, height: height) {
            let ink: Color
            switch bar.tone {
            case .selected: ink = Ink.label
            case .best: ink = Ink.achievement
            case .other: ink = Ink.tertiary
            }
            let r = CGRect(x: bar.left, y: bar.top, width: bar.right - bar.left, height: bar.bottom - bar.top)
            // Only the top corners are rounded; the foot sits flat on the axis.
            context.fill(Path(roundedRect: r, cornerRadii: RectangleCornerRadii(
                topLeading: bar.radius, bottomLeading: 0, bottomTrailing: 0, topTrailing: bar.radius)), with: .color(ink))
        }
    }
}
