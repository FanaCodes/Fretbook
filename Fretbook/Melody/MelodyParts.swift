import SwiftUI

/// Small drawn note symbol for the duration buttons.
struct NoteValueIcon: View {
    let value: NoteValue
    var isRest = false

    var body: some View {
        Canvas { context, size in
            let s = size.height / 5.2
            let x = size.width / 2 - s * 0.3
            let y = size.height - s * 1.1
            let ink = GraphicsContext.Shading.foreground
            if isRest {
                let label = Text(restSymbol).font(.system(size: size.height * 0.36, weight: .bold))
                context.draw(label, at: CGPoint(x: size.width / 2, y: size.height / 2))
                return
            }
            let oval = Path(ellipseIn: CGRect(x: -s * 0.62, y: -s * 0.42, width: s * 1.24, height: s * 0.84))
                .applying(CGAffineTransform(rotationAngle: -0.35).concatenating(CGAffineTransform(translationX: x, y: y)))
            if value.isFilled {
                context.fill(oval, with: ink)
            } else {
                context.stroke(oval, with: ink, lineWidth: s * 0.2)
            }
            guard value.hasStem else { return }
            let stemX = x + s * 0.56
            var stem = Path()
            stem.move(to: CGPoint(x: stemX, y: y))
            stem.addLine(to: CGPoint(x: stemX, y: y - s * 3.4))
            context.stroke(stem, with: ink, lineWidth: s * 0.16)
            for flag in 0..<value.flags {
                let top = y - s * 3.4 + CGFloat(flag) * s * 0.8
                var path = Path()
                path.move(to: CGPoint(x: stemX, y: top))
                path.addQuadCurve(to: CGPoint(x: stemX + s * 0.8, y: top + s * 1.8), control: CGPoint(x: stemX + s * 0.9, y: top + s * 0.6))
                context.stroke(path, with: ink, lineWidth: s * 0.22)
            }
        }
    }

    private var restSymbol: String {
        switch value {
        case .whole: return "R1"
        case .half: return "R½"
        case .quarter: return "R¼"
        case .eighth: return "R⅛"
        case .sixteenth: return "R16"
        }
    }
}

struct MelodyHeader: View {
    let melody: Melody
    var scale: CGFloat = 1

    var body: some View {
        VStack(spacing: 3 * scale) {
            Text(melody.title.isEmpty ? "Untitled" : melody.title)
                .font(.system(size: 22 * scale, weight: .bold))
            if !melody.subtitle.isEmpty {
                Text(melody.subtitle)
                    .font(.system(size: 12 * scale))
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text("♩ = \(melody.tempo)")
                    .font(.system(size: 11 * scale, weight: .semibold))
                Spacer()
                if melody.display.showsTab && melody.tuning != Tunings.standard {
                    Text("Tuning: \(Tunings.name(for: melody.tuning))")
                        .font(.system(size: 10 * scale))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - PDF

enum MelodyPDF {
    @MainActor
    static func make(_ melody: Melody) -> URL? {
        let paper = PaperSize.regionalDefault
        let width = paper.size.width - PDFPaginator.margin * 2
        let s: CGFloat = 6.4
        let metrics = ScoreMetrics(melody: melody, s: s)
        let tab = MusicTheory.tabPositions(for: melody)
        let systems = ScoreLayout.layout(melody: melody, width: width, s: s)
        let lyrics = melody.lyricAssignment.map

        var blocks: [AnyView] = [AnyView(MelodyHeader(melody: melody))]
        for system in systems {
            blocks.append(AnyView(ScoreSystemView(melody: melody, system: system, metrics: metrics, tab: tab, lyrics: lyrics)))
        }
        return PDFPaginator.make(
            fileName: melody.title.isEmpty ? "Melody" : melody.title,
            paper: paper,
            footer: melody.title,
            blocks: blocks
        )
    }
}
