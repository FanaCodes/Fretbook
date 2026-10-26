import SwiftUI

/// Draws one line of music: staff and/or tab, notes, beams, lyrics and chord names.
struct ScoreSystemView: View {
    let melody: Melody
    let system: ScoreSystem
    let metrics: ScoreMetrics
    let tab: [UUID: (string: Int, fret: Int)]
    var lyrics: [UUID: Syllable] = [:]
    var selected: UUID? = nil
    var playing: UUID? = nil

    var body: some View {
        Canvas { context, _ in
            draw(&context)
        }
        .frame(width: system.width, height: metrics.height)
    }

    private var s: CGFloat { metrics.s }
    private var lineWidth: CGFloat { max(0.6, s * 0.1) }
    private var ink: GraphicsContext.Shading { .color(.primary) }

    private func color(for note: MelodyNote) -> Color {
        if note.id == playing { return .orange }
        if note.id == selected { return .accentColor }
        return .primary
    }

    // MARK: Drawing

    private func draw(_ context: inout GraphicsContext) {
        let right = system.width - lineWidth
        let left = s * 0.2

        if metrics.showStaff {
            var lines = Path()
            for i in 0..<5 {
                let y = metrics.staffTop + CGFloat(i) * s
                lines.move(to: CGPoint(x: left, y: y))
                lines.addLine(to: CGPoint(x: right, y: y))
            }
            context.stroke(lines, with: ink, lineWidth: lineWidth)
            drawClef(&context, x: s * 1.5)
            drawKeySignature(&context, x: s * 3.5)
            if system.isFirst {
                drawTimeSignature(&context, x: system.headerWidth - s * 1.4)
            }
        }

        let stringCount = melody.tuning.count
        if metrics.showTab {
            var lines = Path()
            for string in 0..<stringCount {
                let y = metrics.tabY(string: string, strings: stringCount)
                lines.move(to: CGPoint(x: left, y: y))
                lines.addLine(to: CGPoint(x: right, y: y))
            }
            context.stroke(lines, with: .color(.secondary), lineWidth: lineWidth)
            let tabTop = metrics.tabY(string: stringCount - 1, strings: stringCount)
            let tabBottom = metrics.tabY(string: 0, strings: stringCount)
            for (k, letter) in ["T", "A", "B"].enumerated() {
                let y = tabTop + (tabBottom - tabTop) * (CGFloat(k) + 0.5) / 3
                context.draw(Text(letter).font(.system(size: s * 1.25, weight: .heavy)).foregroundColor(.primary), at: CGPoint(x: s * 1.3, y: y))
            }
        }

        drawBarlines(&context, left: left)

        // Stems direction and beam heights for beamed groups
        var beamInfo: [Int: (up: Bool, end: CGFloat)] = [:]
        let groups = metrics.showStaff ? ScoreLayout.beamGroups(system: system, melody: melody) : []
        for group in groups {
            let steps = group.map { melody.notes[$0.index].step }
            let up = Double(steps.reduce(0, +)) / Double(steps.count) < 6
            let ys = steps.map { metrics.y(step: $0) }
            let end = up ? (ys.min() ?? 0) - s * 3.3 : (ys.max() ?? 0) + s * 3.3
            for placed in group { beamInfo[placed.index] = (up, end) }
        }

        for placed in system.notes {
            let note = melody.notes[placed.index]
            let shade = GraphicsContext.Shading.color(color(for: note))
            if metrics.showStaff {
                if note.isRest {
                    drawRest(&context, note: note, x: placed.x, shade: shade)
                } else {
                    drawNote(&context, note: note, x: placed.x, shade: shade, beam: beamInfo[placed.index])
                }
            }
            if metrics.showTab, !note.isRest {
                drawTabNumber(&context, note: note, x: placed.x, strings: stringCount)
            }
            if !note.chord.isEmpty {
                let label = Text(note.chord).font(.system(size: s * 1.4, weight: .bold)).foregroundColor(color(for: note))
                context.draw(label, at: CGPoint(x: placed.x - s * 0.6, y: metrics.chordY), anchor: .leading)
            }
        }

        for group in groups {
            drawBeams(&context, group: group, info: beamInfo)
        }
        if metrics.showStaff {
            drawTies(&context, beamInfo: beamInfo)
            drawTriplets(&context, beamInfo: beamInfo)
        }
        drawLyrics(&context)
    }

    // MARK: Lyrics, ties, triplets

    private func drawLyrics(_ context: inout GraphicsContext) {
        guard metrics.hasLyrics else { return }
        let notes = system.notes
        for (k, placed) in notes.enumerated() {
            let note = melody.notes[placed.index]
            if let syllable = lyrics[note.id] {
                let label = Text(syllable.text).font(.system(size: metrics.lyricSize)).foregroundColor(color(for: note))
                context.draw(label, at: CGPoint(x: placed.x, y: metrics.lyricY))

                // Hyphen to the next sung syllable on this line
                if syllable.continues {
                    let next = notes[(k + 1)...].first { lyrics[melody.notes[$0.index].id] != nil }
                    let hyphenX = next.map { (placed.x + $0.x) / 2 } ?? placed.x + CGFloat(syllable.text.count) * metrics.lyricSize * 0.4 + s
                    let hyphen = Text("-").font(.system(size: metrics.lyricSize)).foregroundColor(.secondary)
                    context.draw(hyphen, at: CGPoint(x: hyphenX, y: metrics.lyricY))
                }
            } else if !note.isRest && (note.holdsSyllable || (k > 0 && melody.notes[notes[k - 1].index].tie)) {
                // Extender line under notes that keep singing the syllable
                let fromX = k > 0 ? notes[k - 1].x + s * 0.8 : placed.x - s * 2
                var line = Path()
                line.move(to: CGPoint(x: fromX, y: metrics.lyricY + metrics.lyricSize * 0.45))
                line.addLine(to: CGPoint(x: placed.x + s * 0.6, y: metrics.lyricY + metrics.lyricSize * 0.45))
                context.stroke(line, with: .color(.secondary), lineWidth: lineWidth)
            }
        }
    }

    private func drawTies(_ context: inout GraphicsContext, beamInfo: [Int: (up: Bool, end: CGFloat)]) {
        for (k, placed) in system.notes.enumerated() {
            let note = melody.notes[placed.index]
            guard note.tie, !note.isRest else { continue }
            let y = metrics.y(step: note.step)
            let up = beamInfo[placed.index]?.up ?? (note.step < 6)
            // Curve on the side away from the stem
            let direction: CGFloat = up ? 1 : -1
            let startX = placed.x + s * 0.5
            let endX: CGFloat
            if k + 1 < system.notes.count {
                endX = system.notes[k + 1].x - s * 0.5
            } else {
                endX = system.width - s * 0.5
            }
            let baseY = y + direction * s * 0.6
            var curve = Path()
            curve.move(to: CGPoint(x: startX, y: baseY))
            curve.addQuadCurve(to: CGPoint(x: endX, y: baseY), control: CGPoint(x: (startX + endX) / 2, y: baseY + direction * s * 1.1))
            curve.addQuadCurve(to: CGPoint(x: startX, y: baseY), control: CGPoint(x: (startX + endX) / 2, y: baseY + direction * s * 0.8))
            context.fill(curve, with: .color(color(for: note)))
        }
    }

    private func drawTriplets(_ context: inout GraphicsContext, beamInfo: [Int: (up: Bool, end: CGFloat)]) {
        var run: [PlacedNote] = []
        func flush() {
            defer { run = [] }
            guard let first = run.first, let last = run.last else { return }
            let steps = run.map { melody.notes[$0.index].step }
            let highest = metrics.y(step: steps.max() ?? 6)
            let y = min(metrics.staffTop - s * 0.8, highest - s * 4.2)
            let x1 = first.x - s * 0.4
            let x2 = last.x + s * 0.9
            var bracket = Path()
            bracket.move(to: CGPoint(x: x1, y: y + s * 0.5))
            bracket.addLine(to: CGPoint(x: x1, y: y))
            bracket.addLine(to: CGPoint(x: (x1 + x2) / 2 - s * 0.6, y: y))
            bracket.move(to: CGPoint(x: (x1 + x2) / 2 + s * 0.6, y: y))
            bracket.addLine(to: CGPoint(x: x2, y: y))
            bracket.addLine(to: CGPoint(x: x2, y: y + s * 0.5))
            context.stroke(bracket, with: ink, lineWidth: lineWidth)
            let three = Text("3").font(.system(size: s * 1.3, weight: .bold).italic()).foregroundColor(.primary)
            context.draw(three, at: CGPoint(x: (x1 + x2) / 2, y: y))
        }
        var total = 0.0
        for placed in system.notes {
            let note = melody.notes[placed.index]
            if note.triplet {
                run.append(placed)
                total += note.value.quarters
                // A triplet is complete when three notes' worth of the written value is filled.
                if total >= (run.first.map { melody.notes[$0.index].value.quarters * 3 } ?? 0) - 0.0001 {
                    flush()
                    total = 0
                }
            } else {
                flush()
                total = 0
            }
        }
        flush()
    }

    private func drawBarlines(_ context: inout GraphicsContext, left: CGFloat) {
        let stringCount = melody.tuning.count
        let top = metrics.showStaff ? metrics.staffTop : metrics.tabY(string: stringCount - 1, strings: stringCount)
        let bottom = metrics.showTab ? metrics.tabY(string: 0, strings: stringCount) : metrics.staffBottom

        var path = Path()
        path.move(to: CGPoint(x: left, y: top))
        path.addLine(to: CGPoint(x: left, y: bottom))
        for (i, x) in system.barlines.enumerated() {
            let isFinal = system.isLast && i == system.barlines.count - 1
            let barX = min(x, system.width - lineWidth * 3)
            if isFinal {
                path.move(to: CGPoint(x: barX - s * 0.6, y: top))
                path.addLine(to: CGPoint(x: barX - s * 0.6, y: bottom))
                context.fill(Path(CGRect(x: barX - s * 0.35, y: top, width: s * 0.4, height: bottom - top)), with: ink)
            } else if metrics.showStaff && metrics.showTab {
                // Separate lines for staff and tab, like printed guitar music
                path.move(to: CGPoint(x: barX, y: metrics.staffTop))
                path.addLine(to: CGPoint(x: barX, y: metrics.staffBottom))
                path.move(to: CGPoint(x: barX, y: metrics.tabY(string: stringCount - 1, strings: stringCount)))
                path.addLine(to: CGPoint(x: barX, y: bottom))
            } else {
                path.move(to: CGPoint(x: barX, y: top))
                path.addLine(to: CGPoint(x: barX, y: bottom))
            }
        }
        context.stroke(path, with: ink, lineWidth: lineWidth * 1.2)
    }

    // MARK: Clef, key, time

    private func drawClef(_ context: inout GraphicsContext, x cx: CGFloat) {
        let gy = metrics.y(step: 4)     // the G line
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: cx + x * s, y: gy + y * s) }
        var path = Path()
        path.move(to: p(0.25, 0.05))
        path.addCurve(to: p(-0.05, -0.6), control1: p(0.6, -0.05), control2: p(0.35, -0.6))
        path.addCurve(to: p(-0.75, 0.25), control1: p(-0.5, -0.6), control2: p(-0.8, -0.2))
        path.addCurve(to: p(0.1, 1.15), control1: p(-0.7, 0.85), control2: p(-0.3, 1.15))
        path.addCurve(to: p(1.0, 0.1), control1: p(0.6, 1.15), control2: p(1.0, 0.7))
        path.addCurve(to: p(-0.15, -2.0), control1: p(1.0, -0.8), control2: p(0.0, -1.2))
        path.addCurve(to: p(0.45, -4.4), control1: p(-0.45, -2.9), control2: p(0.0, -4.3))
        path.addCurve(to: p(0.35, -3.1), control1: p(0.85, -4.5), control2: p(0.8, -3.6))
        path.addCurve(to: p(0.1, 2.3), control1: p(-0.3, -2.0), control2: p(0.25, 0.5))
        path.addCurve(to: p(-0.55, 2.2), control1: p(0.05, 2.9), control2: p(-0.5, 2.8))
        context.stroke(path, with: ink, style: StrokeStyle(lineWidth: s * 0.17, lineCap: .round, lineJoin: .round))
        let ball = p(-0.42, 2.05)
        context.fill(Path(ellipseIn: CGRect(x: ball.x - s * 0.3, y: ball.y - s * 0.3, width: s * 0.6, height: s * 0.6)), with: ink)
    }

    private func drawKeySignature(_ context: inout GraphicsContext, x: CGFloat) {
        let count = abs(melody.keySignature)
        guard count > 0 else { return }
        let sharps = [10, 7, 11, 8, 5, 9, 6]
        let flats = [6, 9, 5, 8, 4, 7, 3]
        let isSharp = melody.keySignature > 0
        for i in 0..<min(count, 7) {
            let step = isSharp ? sharps[i] : flats[i]
            let symbol = Text(isSharp ? "♯" : "♭").font(.system(size: s * 2.1)).foregroundColor(.primary)
            context.draw(symbol, at: CGPoint(x: x + CGFloat(i) * s * 0.95, y: metrics.y(step: step) - (isSharp ? 0 : s * 0.35)))
        }
    }

    private func drawTimeSignature(_ context: inout GraphicsContext, x: CGFloat) {
        let font = Font.system(size: s * 2.3, weight: .black)
        context.draw(Text("\(melody.beatsPerBar)").font(font).foregroundColor(.primary), at: CGPoint(x: x, y: metrics.staffTop + s))
        context.draw(Text("\(melody.beatUnit)").font(font).foregroundColor(.primary), at: CGPoint(x: x, y: metrics.staffTop + s * 3))
    }

    // MARK: Notes

    private func drawNote(_ context: inout GraphicsContext, note: MelodyNote, x: CGFloat, shade: GraphicsContext.Shading,
                          beam: (up: Bool, end: CGFloat)?) {
        let y = metrics.y(step: note.step)

        // Ledger lines
        var ledgers = Path()
        if note.step <= 0 {
            for step in stride(from: 0, through: note.step, by: -2) {
                let ly = metrics.y(step: step)
                ledgers.move(to: CGPoint(x: x - s * 0.95, y: ly))
                ledgers.addLine(to: CGPoint(x: x + s * 0.95, y: ly))
            }
        } else if note.step >= 12 {
            for step in stride(from: 12, through: note.step, by: 2) {
                let ly = metrics.y(step: step)
                ledgers.move(to: CGPoint(x: x - s * 0.95, y: ly))
                ledgers.addLine(to: CGPoint(x: x + s * 0.95, y: ly))
            }
        }
        context.stroke(ledgers, with: ink, lineWidth: lineWidth)

        // Head
        if note.value == .whole {
            let rect = CGRect(x: x - s * 0.72, y: y - s * 0.46, width: s * 1.44, height: s * 0.92)
            context.stroke(Path(ellipseIn: rect.insetBy(dx: s * 0.1, dy: s * 0.08)), with: shade, lineWidth: s * 0.22)
        } else {
            let oval = Path(ellipseIn: CGRect(x: -s * 0.62, y: -s * 0.42, width: s * 1.24, height: s * 0.84))
                .applying(CGAffineTransform(rotationAngle: -0.35).concatenating(CGAffineTransform(translationX: x, y: y)))
            if note.value.isFilled {
                context.fill(oval, with: shade)
            } else {
                context.stroke(oval, with: shade, lineWidth: s * 0.17)
            }
        }

        // Accidental and dot
        if note.accidental != .none {
            let symbol = Text(note.accidental.symbol).font(.system(size: s * 2.1)).foregroundColor(color(for: note))
            context.draw(symbol, at: CGPoint(x: x - s * 1.55, y: y - (note.accidental == .flat ? s * 0.35 : 0)))
        }
        if note.dotted {
            let dotY = note.step % 2 == 0 ? y - s / 2 : y
            context.fill(Path(ellipseIn: CGRect(x: x + s * 0.95, y: dotY - s * 0.17, width: s * 0.34, height: s * 0.34)), with: shade)
        }

        // Stem and flags
        guard note.value.hasStem else { return }
        let up = beam?.up ?? (note.step < 6)
        let stemX = up ? x + s * 0.56 : x - s * 0.56
        let stemStart = up ? y - s * 0.15 : y + s * 0.15
        let stemEnd = beam?.end ?? (up ? y - s * 3.4 : y + s * 3.4)
        var stem = Path()
        stem.move(to: CGPoint(x: stemX, y: stemStart))
        stem.addLine(to: CGPoint(x: stemX, y: stemEnd))
        context.stroke(stem, with: shade, lineWidth: lineWidth * 1.1)

        if beam == nil {
            for flag in 0..<note.value.flags {
                let direction: CGFloat = up ? 1 : -1
                let start = CGPoint(x: stemX, y: stemEnd + direction * CGFloat(flag) * s * 0.8)
                var path = Path()
                path.move(to: start)
                path.addCurve(
                    to: CGPoint(x: stemX + s * 0.8, y: start.y + direction * s * 2.2),
                    control1: CGPoint(x: stemX + s * 0.05, y: start.y + direction * s * 0.9),
                    control2: CGPoint(x: stemX + s * 1.0, y: start.y + direction * s * 1.2)
                )
                context.stroke(path, with: shade, style: StrokeStyle(lineWidth: s * 0.24, lineCap: .round))
            }
        }
    }

    private func drawBeams(_ context: inout GraphicsContext, group: [PlacedNote], info: [Int: (up: Bool, end: CGFloat)]) {
        guard let first = group.first, let last = group.last, let style = info[first.index] else { return }
        let thickness = s * 0.5
        let offset: CGFloat = style.up ? s * 0.56 : -s * 0.56
        let x1 = first.x + offset
        let x2 = last.x + offset
        let y = style.up ? style.end : style.end - thickness
        context.fill(Path(CGRect(x: x1 - lineWidth / 2, y: y, width: x2 - x1 + lineWidth, height: thickness)), with: ink)

        // Second beam between neighbouring 16ths
        let secondY = style.up ? y + thickness * 1.6 : y - thickness * 1.6
        for (k, placed) in group.enumerated() where melody.notes[placed.index].value == .sixteenth {
            let x = placed.x + offset
            if k + 1 < group.count, melody.notes[group[k + 1].index].value == .sixteenth {
                let nx = group[k + 1].x + offset
                context.fill(Path(CGRect(x: x - lineWidth / 2, y: secondY, width: nx - x + lineWidth, height: thickness)), with: ink)
            } else if k == 0 || melody.notes[group[k - 1].index].value != .sixteenth {
                // Lone 16th: short stub towards its neighbour
                let stub = k == 0 ? s * 1.0 : -s * 1.0
                context.fill(Path(CGRect(x: min(x, x + stub), y: secondY, width: abs(stub), height: thickness)), with: ink)
            }
        }
    }

    private func drawRest(_ context: inout GraphicsContext, note: MelodyNote, x: CGFloat, shade: GraphicsContext.Shading) {
        switch note.value {
        case .whole:
            context.fill(Path(CGRect(x: x - s * 0.6, y: metrics.y(step: 8), width: s * 1.2, height: s * 0.5)), with: shade)
        case .half:
            context.fill(Path(CGRect(x: x - s * 0.6, y: metrics.y(step: 6) - s * 0.5, width: s * 1.2, height: s * 0.5)), with: shade)
        case .quarter:
            let c = CGPoint(x: x, y: metrics.y(step: 6))
            var path = Path()
            path.move(to: CGPoint(x: c.x - s * 0.3, y: c.y - s * 1.5))
            path.addLine(to: CGPoint(x: c.x + s * 0.35, y: c.y - s * 0.7))
            path.addLine(to: CGPoint(x: c.x - s * 0.25, y: c.y))
            path.addLine(to: CGPoint(x: c.x + s * 0.35, y: c.y + s * 0.65))
            path.addQuadCurve(to: CGPoint(x: c.x + s * 0.05, y: c.y + s * 1.45), control: CGPoint(x: c.x - s * 0.6, y: c.y + s * 0.6))
            context.stroke(path, with: shade, style: StrokeStyle(lineWidth: s * 0.28, lineCap: .round, lineJoin: .round))
        case .eighth, .sixteenth:
            let hooks = note.value == .eighth ? 1 : 2
            let top = metrics.y(step: 7)
            var path = Path()
            path.move(to: CGPoint(x: x + s * 0.4, y: top))
            path.addLine(to: CGPoint(x: x - s * 0.1, y: top + s * (hooks == 1 ? 2.2 : 3.1)))
            context.stroke(path, with: shade, lineWidth: s * 0.16)
            for hook in 0..<hooks {
                let hy = top + CGFloat(hook) * s
                let hx = x + s * 0.4 - CGFloat(hook) * s * 0.2
                var curve = Path()
                curve.move(to: CGPoint(x: hx - s * 0.75, y: hy + s * 0.05))
                curve.addQuadCurve(to: CGPoint(x: hx, y: hy), control: CGPoint(x: hx - s * 0.35, y: hy + s * 0.45))
                context.stroke(curve, with: shade, lineWidth: s * 0.14)
                context.fill(Path(ellipseIn: CGRect(x: hx - s * 0.95, y: hy - s * 0.2, width: s * 0.4, height: s * 0.4)), with: shade)
            }
        }
        if note.dotted {
            let dotY = metrics.y(step: 7)
            context.fill(Path(ellipseIn: CGRect(x: x + s * 0.8, y: dotY - s * 0.17, width: s * 0.34, height: s * 0.34)), with: shade)
        }
    }

    private func drawTabNumber(_ context: inout GraphicsContext, note: MelodyNote, x: CGFloat, strings: Int) {
        let y: CGFloat
        let text: String
        if let position = tab[note.id] {
            y = metrics.tabY(string: position.string, strings: strings)
            text = "\(position.fret)"
        } else {
            y = metrics.tabY(string: 0, strings: strings)
            text = "?"
        }
        let size = s * 1.25
        let width = CGFloat(text.count) * size * 0.62 + s * 0.2
        context.fill(Path(CGRect(x: x - width / 2, y: y - size * 0.5, width: width, height: size)), with: .color(Color(uiColor: .systemBackground)))
        let label = Text(text).font(.system(size: size, weight: .bold)).foregroundColor(color(for: note))
        context.draw(label, at: CGPoint(x: x, y: y))
    }
}

/// All lines of a melody stacked. Tap to add/select notes; long-press a note and drag to change its pitch.
struct ScoreView: View {
    let melody: Melody
    let width: CGFloat
    var s: CGFloat = 9
    var selected: UUID? = nil
    var playing: UUID? = nil
    var onTap: ((ScoreSystem, CGPoint) -> Void)? = nil
    /// (system, start point, current point, finished)
    var onDrag: ((ScoreSystem, CGPoint, CGPoint, Bool) -> Void)? = nil

    var body: some View {
        let systems = ScoreLayout.layout(melody: melody, width: width, s: s)
        let metrics = ScoreMetrics(melody: melody, s: s)
        let tab = MusicTheory.tabPositions(for: melody)
        let lyrics = melody.lyricAssignment.map

        VStack(alignment: .leading, spacing: s * 0.8) {
            ForEach(systems) { system in
                ScoreSystemView(
                    melody: melody,
                    system: system,
                    metrics: metrics,
                    tab: tab,
                    lyrics: lyrics,
                    selected: selected,
                    playing: playing
                )
                .contentShape(Rectangle())
                .gesture(
                    SpatialTapGesture()
                        .onEnded { value in onTap?(system, value.location) }
                )
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.25)
                        .sequenced(before: DragGesture(minimumDistance: 0))
                        .onChanged { value in
                            if case .second(true, let drag?) = value {
                                onDrag?(system, drag.startLocation, drag.location, false)
                            }
                        }
                        .onEnded { value in
                            if case .second(true, let drag?) = value {
                                onDrag?(system, drag.startLocation, drag.location, true)
                            }
                        }
                )
            }
        }
    }
}
