import SwiftUI

/// Shared layout math so drawing and tap-handling always agree.
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

/// Draws one fret diagram. Used on screen, in the editor, and for printing.
struct FretDiagramView: View {
    let diagram: FretDiagram
    var leftHanded = false
    var showTuning = true
    var showNoteNames = false
    var selection: UUID? = nil

    var body: some View {
        Canvas { context, size in
            draw(in: &context, size: size)
        }
    }

    static func aspectRatio(for diagram: FretDiagram) -> CGFloat {
        CGFloat(max(diagram.stringCount, 2)) / (CGFloat(diagram.fretCount) + 1.4)
    }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        let geo = DiagramGeometry(
            size: size,
            strings: diagram.stringCount,
            frets: diagram.fretCount,
            leftHanded: leftHanded,
            hasBottomLabels: showTuning
        )
        let grid = geo.grid
        let ink = GraphicsContext.Shading.color(.primary)
        let highlight = GraphicsContext.Shading.color(.accentColor)
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

        // Open / muted markers
        let markerSize = min(r * 0.75, geo.markerHeight * 0.32)
        let markerY = grid.minY - geo.markerHeight * 0.5 - (diagram.startFret == 1 ? geo.lineWidth * 2 : 0)
        for string in 0..<diagram.stringCount {
            let x = geo.x(forString: string)
            switch diagram.mark(string) {
            case .open:
                let ring = CGRect(x: x - markerSize, y: markerY - markerSize, width: markerSize * 2, height: markerSize * 2)
                context.stroke(Path(ellipseIn: ring), with: ink, lineWidth: geo.lineWidth * 1.4)
            case .muted:
                var cross = Path()
                cross.move(to: CGPoint(x: x - markerSize, y: markerY - markerSize))
                cross.addLine(to: CGPoint(x: x + markerSize, y: markerY + markerSize))
                cross.move(to: CGPoint(x: x + markerSize, y: markerY - markerSize))
                cross.addLine(to: CGPoint(x: x - markerSize, y: markerY + markerSize))
                context.stroke(cross, with: ink, lineWidth: geo.lineWidth * 1.4)
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
            let shape = Path(roundedRect: rect, cornerRadius: r)
            context.fill(shape, with: ink)
            if barre.id == selection {
                context.stroke(Path(roundedRect: rect.insetBy(dx: -r * 0.3, dy: -r * 0.3), cornerRadius: r * 1.3), with: highlight, lineWidth: geo.lineWidth * 2.5)
            }
            if !barre.label.isEmpty {
                drawLabel(barre.label, at: CGPoint(x: (x1 + x2) / 2, y: y), radius: r, color: .white, in: &context)
            }
        }

        // Dots
        for dot in diagram.dots where dot.fret >= diagram.startFret && dot.fret <= lastFret && dot.string < diagram.stringCount {
            let center = CGPoint(x: geo.x(forString: dot.string), y: geo.y(forRow: dot.fret - diagram.startFret))
            let rect = CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
            switch dot.style {
            case .normal:
                context.fill(Path(ellipseIn: rect), with: ink)
            case .root:
                context.fill(Path(roundedRect: rect, cornerRadius: r * 0.35), with: ink)
            case .ghost:
                context.fill(Path(ellipseIn: rect), with: .color(Color(uiColor: .systemBackground)))
                context.stroke(Path(ellipseIn: rect.insetBy(dx: geo.lineWidth, dy: geo.lineWidth)), with: ink, lineWidth: geo.lineWidth * 1.6)
            }
            if dot.id == selection {
                context.stroke(Path(ellipseIn: rect.insetBy(dx: -r * 0.35, dy: -r * 0.35)), with: highlight, lineWidth: geo.lineWidth * 2.5)
            }

            var text = dot.label
            if text.isEmpty && showNoteNames {
                text = diagram.noteName(string: dot.string, fret: dot.fret)
            }
            if !text.isEmpty {
                drawLabel(text, at: center, radius: r, color: dot.style == .ghost ? .primary : .white, in: &context)
            }
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
