import SwiftUI

// MARK: - Chord shape

/// A chord shape parsed from text like "x32010" or "8 10 10 9 8 8" (low string first).
struct ChordShape: Equatable {
    let frets: [Int?]   // nil = muted, 0 = open

    init?(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return nil }

        let tokens: [String]
        if trimmed.contains(where: { $0 == " " || $0 == "," || $0 == "-" }) {
            tokens = trimmed.split(whereSeparator: { $0 == " " || $0 == "," || $0 == "-" }).map(String.init)
        } else {
            tokens = trimmed.map { String($0) }
        }
        guard (4...8).contains(tokens.count) else { return nil }

        var parsed: [Int?] = []
        for token in tokens {
            if token == "x" {
                parsed.append(nil)
            } else if let fret = Int(token), (0...24).contains(fret) {
                parsed.append(fret)
            } else {
                return nil
            }
        }
        frets = parsed
    }

    private var fretted: [Int] { frets.compactMap { $0 }.filter { $0 > 0 } }

    /// First fret shown in the diagram (1 = show the nut).
    var baseFret: Int {
        let highest = fretted.max() ?? 0
        return highest <= 4 ? 1 : (fretted.min() ?? 1)
    }

    /// How many fret rows to draw.
    var rows: Int {
        let highest = fretted.max() ?? 0
        return max(4, highest - baseFret + 1)
    }
}

struct ChordDiagram: View {
    let shape: ChordShape

    var body: some View {
        Canvas { context, size in
            let strings = shape.frets.count
            let rows = shape.rows
            let top: CGFloat = size.height * 0.16
            let left: CGFloat = size.width * 0.2
            let right: CGFloat = size.width * 0.06
            let bottom: CGFloat = 2
            let gridWidth = size.width - left - right
            let gridHeight = size.height - top - bottom
            let stringGap = gridWidth / CGFloat(strings - 1)
            let fretGap = gridHeight / CGFloat(rows)
            let dot = min(stringGap, fretGap) * 0.36
            let marker = max(3, dot * 0.7)

            // Grid
            var grid = Path()
            for s in 0..<strings {
                let x = left + CGFloat(s) * stringGap
                grid.move(to: CGPoint(x: x, y: top))
                grid.addLine(to: CGPoint(x: x, y: top + gridHeight))
            }
            for f in 0...rows {
                let y = top + CGFloat(f) * fretGap
                grid.move(to: CGPoint(x: left, y: y))
                grid.addLine(to: CGPoint(x: left + gridWidth, y: y))
            }
            context.stroke(grid, with: .color(.secondary), lineWidth: 1)

            // Nut or starting fret label
            if shape.baseFret == 1 {
                let nut = CGRect(x: left - 0.5, y: top - 2.5, width: gridWidth + 1, height: 3.5)
                context.fill(Path(nut), with: .color(.primary))
            } else {
                let label = Text("\(shape.baseFret)fr")
                    .font(.system(size: max(8, fretGap * 0.42), weight: .medium))
                    .foregroundColor(.secondary)
                context.draw(label, at: CGPoint(x: left * 0.45, y: top + fretGap / 2))
            }

            // Open / muted markers and finger dots
            for (s, fret) in shape.frets.enumerated() {
                let x = left + CGFloat(s) * stringGap
                let markerY = top * 0.45
                switch fret {
                case nil:
                    var cross = Path()
                    cross.move(to: CGPoint(x: x - marker, y: markerY - marker))
                    cross.addLine(to: CGPoint(x: x + marker, y: markerY + marker))
                    cross.move(to: CGPoint(x: x + marker, y: markerY - marker))
                    cross.addLine(to: CGPoint(x: x - marker, y: markerY + marker))
                    context.stroke(cross, with: .color(.secondary), lineWidth: 1.3)
                case 0?:
                    let ring = CGRect(x: x - marker, y: markerY - marker, width: marker * 2, height: marker * 2)
                    context.stroke(Path(ellipseIn: ring), with: .color(.primary), lineWidth: 1.3)
                case let value?:
                    let row = CGFloat(value - shape.baseFret)
                    let y = top + (row + 0.5) * fretGap
                    let circle = CGRect(x: x - dot, y: y - dot, width: dot * 2, height: dot * 2)
                    context.fill(Path(ellipseIn: circle), with: .color(NoteCategory.chord.color))
                }
            }
        }
        .accessibilityLabel("Chord diagram")
    }
}

// MARK: - Strumming

struct StrumView: View {
    let pattern: String

    private var strokes: [Character] {
        pattern.filter { !$0.isWhitespace && $0 != "|" }.map { $0 }
    }

    private var counts: [String]? {
        let n = strokes.count
        if n == 16 {
            return (0..<16).map { i in ["\(i / 4 + 1)", "e", "&", "a"][i % 4] }
        }
        if n > 0, n <= 16, n % 2 == 0 {
            return (0..<n).map { i in i % 2 == 0 ? "\(i / 2 + 1)" : "&" }
        }
        return nil
    }

    var body: some View {
        let labels = counts
        HStack(spacing: 4) {
            ForEach(Array(strokes.enumerated()), id: \.offset) { pair in
                VStack(spacing: 3) {
                    symbol(for: pair.element)
                        .frame(width: 22, height: 24)
                    if let labels {
                        Text(labels[pair.offset])
                            .font(.caption2.weight(pair.offset % 2 == 0 ? .semibold : .regular))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(NoteCategory.rhythm.color.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    @ViewBuilder
    private func symbol(for stroke: Character) -> some View {
        switch stroke {
        case "D", "d":
            Image(systemName: "arrow.down")
                .font(.system(size: 18, weight: .bold))
        case "U", "u":
            Image(systemName: "arrow.up")
                .font(.system(size: 18, weight: .bold))
        case "X", "x":
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(NoteCategory.rhythm.color)
        default:
            Circle()
                .fill(Color.secondary.opacity(0.5))
                .frame(width: 5, height: 5)
        }
    }
}

// MARK: - Tab

struct TabText: View {
    let text: String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Text(text)
                .font(.system(.callout, design: .monospaced))
                .fixedSize()
                .textSelection(.enabled)
                .padding(10)
        }
        .background(NoteCategory.tab.color.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
