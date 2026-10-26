import SwiftUI

/// Shared layout math for the vertical chord box, so drawing and tap-handling always agree.
struct DiagramGeometry {
    enum Hit: Equatable {
        case marker(Int)            // area above the nut, per string
        case cell(Int, Int)         // string, row (0 = first visible fret)
        case none
    }

    let size: CGSize
    let strings: Int
    let frets: Int
    let leftHanded: Bool
    let hasBottomLabels: Bool

    var markerHeight: CGFloat { size.height * 0.11 }
    var bottomHeight: CGFloat { hasBottomLabels ? size.height * 0.08 : size.height * 0.015 }
    // The fret-number column sits on the side of the low string.
    var leftInset: CGFloat { size.width * (leftHanded ? 0.07 : 0.17) }
    var rightInset: CGFloat { size.width * (leftHanded ? 0.17 : 0.07) }

    var grid: CGRect {
        CGRect(
            x: leftInset,
            y: markerHeight,
            width: max(1, size.width - leftInset - rightInset),
            height: max(1, size.height - markerHeight - bottomHeight)
        )
    }

    var stringGap: CGFloat { grid.width / CGFloat(max(strings - 1, 1)) }
    var fretGap: CGFloat { grid.height / CGFloat(max(frets, 1)) }
    var dotRadius: CGFloat { min(stringGap, fretGap) * 0.38 }
    var lineWidth: CGFloat { max(0.75, min(size.width, size.height) * 0.006) }

    func x(forString string: Int) -> CGFloat {
        let index = leftHanded ? strings - 1 - string : string
        return grid.minX + CGFloat(index) * stringGap
    }

    func y(forRow row: Int) -> CGFloat {
        grid.minY + (CGFloat(row) + 0.5) * fretGap
    }

    func hit(_ point: CGPoint) -> Hit {
        let column = Int(((point.x - grid.minX) / stringGap).rounded())
        guard column >= 0, column < strings, abs(point.x - (grid.minX + CGFloat(column) * stringGap)) <= stringGap * 0.6 else {
            return .none
        }
        let string = leftHanded ? strings - 1 - column : column
        if point.y < grid.minY {
            return .marker(string)
        }
        guard point.y <= grid.maxY else { return .none }
        let row = min(frets - 1, max(0, Int((point.y - grid.minY) / fretGap)))
        return .cell(string, row)
    }
}

/// Layout math for the horizontal fretboard: strings run left→right, highest string on top
/// (like tab). Fret 0 sits in a column left of the nut. Mirrored for left-handed players.
struct NeckGeometry {
    let size: CGSize
    let strings: Int
    let startFret: Int
    let frets: Int
    let leftHanded: Bool
    let showTuning: Bool

    var showsNut: Bool { startFret == 1 }
    private var labelUnits: CGFloat { showTuning ? 0.7 : 0.15 }
    private var openUnits: CGFloat { showsNut ? 0.9 : 0.35 }

    var fretGap: CGFloat { size.width / (labelUnits + openUnits + CGFloat(frets) + 0.25) }
    var stringGap: CGFloat { size.height / (CGFloat(max(strings - 1, 1)) + 1.6) }
    var gridMinX: CGFloat { (labelUnits + openUnits) * fretGap }
    var gridMaxX: CGFloat { gridMinX + CGFloat(frets) * fretGap }
    var gridMinY: CGFloat { stringGap * 0.55 }
    var gridMaxY: CGFloat { gridMinY + CGFloat(max(strings - 1, 1)) * stringGap }
    var dotRadius: CGFloat { min(stringGap * 0.42, fretGap * 0.36) }
    var lineWidth: CGFloat { max(0.75, min(size.width, size.height) * 0.006) }

    /// Mirrors an x position for left-handed players.
    func flip(_ x: CGFloat) -> CGFloat { leftHanded ? size.width - x : x }

    func y(forString string: Int) -> CGFloat {
        gridMinY + CGFloat(strings - 1 - string) * stringGap
    }

    /// Unflipped x of the middle of a fret space (fret 0 = left of the nut).
    func rawX(forFret fret: Int) -> CGFloat {
        if fret == 0 { return gridMinX - openUnits * fretGap * 0.5 }
        return gridMinX + (CGFloat(fret - startFret) + 0.5) * fretGap
    }

    func x(forFret fret: Int) -> CGFloat { flip(rawX(forFret: fret)) }
    func lineX(_ index: Int) -> CGFloat { flip(gridMinX + CGFloat(index) * fretGap) }

    /// Returns (string, fret) for a touch, or nil.
    func hit(_ point: CGPoint) -> (string: Int, fret: Int)? {
        let x = flip(point.x)
        let row = Int(((point.y - gridMinY) / stringGap).rounded())
        guard row >= 0, row < strings, abs(point.y - (gridMinY + CGFloat(row) * stringGap)) <= stringGap * 0.6 else { return nil }
        let string = strings - 1 - row
        if x < gridMinX {
            if showsNut && x > gridMinX - openUnits * fretGap {
                return (string, 0)
            }
            return nil
        }
        guard x <= gridMaxX else { return nil }
        let fret = startFret + min(frets - 1, max(0, Int((x - gridMinX) / fretGap)))
        return (string, fret)
    }
}

/// Draws one diagram (chord box or fretboard). Used on screen, in the editor, and for printing.
struct FretDiagramView: View {
    let diagram: FretDiagram
    var leftHanded = false
    var showTuning = true
    var showNoteNames = false
    var selection: UUID? = nil

    var body: some View {
        Canvas { context, size in
            if diagram.kind == .neck {
                drawNeck(in: &context, size: size)
            } else {
                drawBox(in: &context, size: size)
            }
        }
    }

    static func aspectRatio(for diagram: FretDiagram) -> CGFloat {
        if diagram.kind == .neck {
            return (CGFloat(diagram.fretCount) + 1.8) / (CGFloat(max(diagram.stringCount - 1, 1)) * 0.62 + 1.0)
        }
        return CGFloat(max(diagram.stringCount, 2)) / (CGFloat(diagram.fretCount) + 1.4)
    }

    private var ink: GraphicsContext.Shading { .color(.primary) }
    private var highlight: GraphicsContext.Shading { .color(.accentColor) }

    // MARK: Chord box

    private func drawBox(in context: inout GraphicsContext, size: CGSize) {
        let geo = DiagramGeometry(
            size: size,
            strings: diagram.stringCount,
            frets: diagram.fretCount,
            leftHanded: leftHanded,
            hasBottomLabels: showTuning
        )
        let grid = geo.grid
        let r = geo.dotRadius
        let lastFret = diagram.startFret + diagram.fretCount - 1

        // Frets and strings
        var lines = Path()
        for row in 0...diagram.fretCount {
            let y = grid.minY + CGFloat(row) * geo.fretGap
            lines.move(to: CGPoint(x: grid.minX, y: y))
            lines.addLine(to: CGPoint(x: grid.maxX, y: y))
        }
        for string in 0..<diagram.stringCount {
            let x = geo.x(forString: string)
            lines.move(to: CGPoint(x: x, y: grid.minY))
            lines.addLine(to: CGPoint(x: x, y: grid.maxY))
        }
        context.stroke(lines, with: ink, lineWidth: geo.lineWidth)

        // Nut, or the starting fret number
        if diagram.startFret == 1 {
            let nut = CGRect(x: grid.minX - geo.lineWidth / 2, y: grid.minY - geo.lineWidth * 4, width: grid.width + geo.lineWidth, height: geo.lineWidth * 4.5)
            context.fill(Path(nut), with: ink)
        } else {
            let label = Text("\(diagram.startFret)fr")
                .font(.system(size: max(7, geo.fretGap * 0.38), weight: .semibold))
                .foregroundColor(.primary)
            let x = leftHanded ? grid.maxX + geo.rightInset * 0.5 : grid.minX - geo.leftInset * 0.5
            context.draw(label, at: CGPoint(x: x, y: geo.y(forRow: 0)))
        }

        // Open / muted markers (an open-string dot, e.g. from a scale, replaces the plain ring)
        let markerSize = min(r * 0.75, geo.markerHeight * 0.32)
        let markerY = grid.minY - geo.markerHeight * 0.5 - (diagram.startFret == 1 ? geo.lineWidth * 2 : 0)
        for string in 0..<diagram.stringCount {
            let x = geo.x(forString: string)
            if let openDot = diagram.dots.first(where: { $0.string == string && $0.fret == 0 }) {
                let size = min(r * 0.9, geo.markerHeight * 0.42)
                drawDot(openDot, at: CGPoint(x: x, y: markerY), radius: size, lineWidth: geo.lineWidth, in: &context)
                continue
            }
            switch diagram.mark(string) {
            case .open:
                let ring = CGRect(x: x - markerSize, y: markerY - markerSize, width: markerSize * 2, height: markerSize * 2)
                context.stroke(Path(ellipseIn: ring), with: ink, lineWidth: geo.lineWidth * 1.4)
            case .muted:
                drawCross(at: CGPoint(x: x, y: markerY), size: markerSize, lineWidth: geo.lineWidth * 1.4, in: &context)
            case .none:
                break
            }
        }

        // Barres
        for barre in diagram.barres where barre.fret >= diagram.startFret && barre.fret <= lastFret {
            let y = geo.y(forRow: barre.fret - diagram.startFret)
            let x1 = geo.x(forString: barre.fromString)
            let x2 = geo.x(forString: barre.toString)
            let rect = CGRect(x: min(x1, x2) - r, y: y - r, width: abs(x2 - x1) + r * 2, height: r * 2)
            drawBarre(barre, rect: rect, radius: r, lineWidth: geo.lineWidth, in: &context)
        }

        // Dots
        for dot in diagram.dots where dot.fret >= diagram.startFret && dot.fret <= lastFret && dot.string < diagram.stringCount {
            let center = CGPoint(x: geo.x(forString: dot.string), y: geo.y(forRow: dot.fret - diagram.startFret))
            drawDot(dot, at: center, radius: r, lineWidth: geo.lineWidth, in: &context)
        }

        // Tuning under the strings
        if showTuning {
            let fontSize = max(6, min(geo.stringGap * 0.45, geo.bottomHeight * 0.6))
            for string in 0..<diagram.stringCount where string < diagram.tuning.count {
                let label = Text(diagram.tuning[string])
                    .font(.system(size: fontSize, weight: .medium))
                    .foregroundColor(.secondary)
                context.draw(label, at: CGPoint(x: geo.x(forString: string), y: grid.maxY + geo.bottomHeight * 0.55))
            }
        }
    }

    // MARK: Fretboard

    private func drawNeck(in context: inout GraphicsContext, size: CGSize) {
        let geo = NeckGeometry(
            size: size,
            strings: diagram.stringCount,
            startFret: diagram.startFret,
            frets: diagram.fretCount,
            leftHanded: leftHanded,
            showTuning: showTuning
        )
        let r = geo.dotRadius
        let lastFret = diagram.startFret + diagram.fretCount - 1
        let left = min(geo.lineX(0), geo.lineX(diagram.fretCount))
        let right = max(geo.lineX(0), geo.lineX(diagram.fretCount))

        // Position markers (inlays) between the middle strings
        let inlayRadius = r * 0.32
        let midY = (geo.gridMinY + geo.gridMaxY) / 2
        for fret in diagram.startFret...lastFret where [3, 5, 7, 9, 12, 15, 17, 19, 21, 24].contains(fret) {
            let x = geo.x(forFret: fret)
            let offsets: [CGFloat] = fret % 12 == 0 ? [-geo.stringGap, geo.stringGap] : [0]
            for offset in offsets {
                let y = midY + offset
                let rect = CGRect(x: x - inlayRadius, y: y - inlayRadius, width: inlayRadius * 2, height: inlayRadius * 2)
                context.fill(Path(ellipseIn: rect), with: .color(.secondary.opacity(0.3)))
            }
        }

        // Strings and frets
        var lines = Path()
        for string in 0..<diagram.stringCount {
            let y = geo.y(forString: string)
            lines.move(to: CGPoint(x: left, y: y))
            lines.addLine(to: CGPoint(x: right, y: y))
        }
        for index in 0...diagram.fretCount {
            let x = geo.lineX(index)
            lines.move(to: CGPoint(x: x, y: geo.gridMinY))
            lines.addLine(to: CGPoint(x: x, y: geo.gridMaxY))
        }
        context.stroke(lines, with: ink, lineWidth: geo.lineWidth)

        if geo.showsNut {
            let x = geo.lineX(0)
            let width = geo.lineWidth * 4.5
            let nut = CGRect(x: leftHanded ? x - geo.lineWidth / 2 : x - width + geo.lineWidth / 2, y: geo.gridMinY, width: width, height: geo.gridMaxY - geo.gridMinY)
            context.fill(Path(nut), with: ink)
        }

        // Fret numbers underneath
        let numberSize = max(6, min(geo.fretGap * 0.32, geo.stringGap * 0.42))
        for fret in diagram.startFret...lastFret where fret == diagram.startFret || [3, 5, 7, 9, 12, 15, 17, 19, 21, 24].contains(fret) {
            let label = Text("\(fret)")
                .font(.system(size: numberSize, weight: .semibold))
                .foregroundColor(.secondary)
            context.draw(label, at: CGPoint(x: geo.x(forFret: fret), y: geo.gridMaxY + geo.stringGap * 0.6))
        }

        // Tuning beside the strings
        if showTuning {
            for string in 0..<diagram.stringCount where string < diagram.tuning.count {
                let label = Text(diagram.tuning[string])
                    .font(.system(size: max(6, geo.stringGap * 0.42), weight: .medium))
                    .foregroundColor(.secondary)
                let x = geo.flip(geo.fretGap * 0.35)
                context.draw(label, at: CGPoint(x: x, y: geo.y(forString: string)))
            }
        }

        // Muted / open markers in the open column (when no open dot is placed)
        if geo.showsNut {
            for string in 0..<diagram.stringCount where !diagram.dots.contains(where: { $0.string == string && $0.fret == 0 }) {
                let point = CGPoint(x: geo.x(forFret: 0), y: geo.y(forString: string))
                switch diagram.mark(string) {
                case .open:
                    let ring = CGRect(x: point.x - r * 0.6, y: point.y - r * 0.6, width: r * 1.2, height: r * 1.2)
                    context.stroke(Path(ellipseIn: ring), with: ink, lineWidth: geo.lineWidth * 1.4)
                case .muted:
                    drawCross(at: point, size: r * 0.55, lineWidth: geo.lineWidth * 1.4, in: &context)
                case .none:
                    break
                }
            }
        }

        // Barres (vertical across strings)
        for barre in diagram.barres where barre.fret >= diagram.startFret && barre.fret <= lastFret {
            let x = geo.x(forFret: barre.fret)
            let y1 = geo.y(forString: barre.fromString)
            let y2 = geo.y(forString: barre.toString)
            let rect = CGRect(x: x - r, y: min(y1, y2) - r, width: r * 2, height: abs(y2 - y1) + r * 2)
            drawBarre(barre, rect: rect, radius: r, lineWidth: geo.lineWidth, in: &context)
        }

        // Dots
        for dot in diagram.dots where dot.string < diagram.stringCount {
            let visible = (dot.fret == 0 && geo.showsNut) || (dot.fret >= diagram.startFret && dot.fret <= lastFret)
            guard visible else { continue }
            let center = CGPoint(x: geo.x(forFret: dot.fret), y: geo.y(forString: dot.string))
            drawDot(dot, at: center, radius: r, lineWidth: geo.lineWidth, in: &context)
        }
    }

    // MARK: Shared pieces

    private func drawDot(_ dot: Dot, at center: CGPoint, radius r: CGFloat, lineWidth: CGFloat, in context: inout GraphicsContext) {
        let rect = CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
        switch dot.style {
        case .normal:
            context.fill(Path(ellipseIn: rect), with: ink)
        case .root:
            context.fill(Path(roundedRect: rect, cornerRadius: r * 0.35), with: ink)
        case .ghost:
            context.fill(Path(ellipseIn: rect), with: .color(Color(uiColor: .systemBackground)))
            context.stroke(Path(ellipseIn: rect.insetBy(dx: lineWidth, dy: lineWidth)), with: ink, lineWidth: lineWidth * 1.6)
        }
        if dot.id == selection {
            context.stroke(Path(ellipseIn: rect.insetBy(dx: -r * 0.35, dy: -r * 0.35)), with: highlight, lineWidth: lineWidth * 2.5)
        }

        var text = dot.label
        if text.isEmpty && showNoteNames {
            text = diagram.noteName(string: dot.string, fret: dot.fret)
        }
        if !text.isEmpty {
            drawLabel(text, at: center, radius: r, color: dot.style == .ghost ? .primary : .white, in: &context)
        }
    }

    private func drawBarre(_ barre: Barre, rect: CGRect, radius r: CGFloat, lineWidth: CGFloat, in context: inout GraphicsContext) {
        context.fill(Path(roundedRect: rect, cornerRadius: r), with: ink)
        if barre.id == selection {
            context.stroke(Path(roundedRect: rect.insetBy(dx: -r * 0.3, dy: -r * 0.3), cornerRadius: r * 1.3), with: highlight, lineWidth: lineWidth * 2.5)
        }
        if !barre.label.isEmpty {
            drawLabel(barre.label, at: CGPoint(x: rect.midX, y: rect.midY), radius: r, color: .white, in: &context)
        }
    }

    private func drawCross(at point: CGPoint, size: CGFloat, lineWidth: CGFloat, in context: inout GraphicsContext) {
        var cross = Path()
        cross.move(to: CGPoint(x: point.x - size, y: point.y - size))
        cross.addLine(to: CGPoint(x: point.x + size, y: point.y + size))
        cross.move(to: CGPoint(x: point.x + size, y: point.y - size))
        cross.addLine(to: CGPoint(x: point.x - size, y: point.y + size))
        context.stroke(cross, with: ink, lineWidth: lineWidth)
    }

    private func drawLabel(_ text: String, at point: CGPoint, radius: CGFloat, color: Color, in context: inout GraphicsContext) {
        let size = text.count > 2 ? radius * 0.8 : radius * 1.15
        let label = Text(text)
            .font(.system(size: max(5, size), weight: .bold))
            .foregroundColor(color)
        context.draw(label, at: point)
    }
}

/// Chord name + diagram + optional caption, as shown in chart tiles and on paper.
struct DiagramCard: View {
    let diagram: FretDiagram
    var leftHanded = false
    var showTuning = true
    var showNoteNames = false
    var nameSize: CGFloat = 18

    var body: some View {
        VStack(spacing: nameSize * 0.25) {
            Text(diagram.name.isEmpty ? " " : diagram.name)
                .font(.system(size: nameSize, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            FretDiagramView(
                diagram: diagram,
                leftHanded: leftHanded,
                showTuning: showTuning,
                showNoteNames: showNoteNames
            )
            .aspectRatio(FretDiagramView.aspectRatio(for: diagram), contentMode: .fit)
            if !diagram.caption.isEmpty {
                Text(diagram.caption)
                    .font(.system(size: nameSize * 0.55))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
        }
    }
}
