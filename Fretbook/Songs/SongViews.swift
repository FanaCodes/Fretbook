import SwiftUI

/// Places views left to right and wraps to the next row when they don't fit.
struct WrapLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                y += rowHeight + lineSpacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }
        let width = proposal.width.map { $0.isFinite ? $0 : widest } ?? widest
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                y += rowHeight + lineSpacing
                x = bounds.minX
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// One lyric line with its chords written above the right syllables.
struct SongLineView: View {
    let line: ChordLine
    let fontSize: CGFloat
    var chordColor: Color = .accentColor
    var interactive = false
    var onTapWord: (Int) -> Void = { _ in }
    var onTapChord: (Int) -> Void = { _ in }

    var body: some View {
        let words = line.words()
        let hasChords = !line.chords.isEmpty

        WrapLayout(spacing: fontSize * 0.32, lineSpacing: fontSize * 0.2) {
            ForEach(words) { word in
                HStack(alignment: .bottom, spacing: 0) {
                    ForEach(word.pieces) { piece in
                        VStack(alignment: .leading, spacing: 0) {
                            if hasChords {
                                chordLabel(piece)
                            }
                            Text(piece.text.isEmpty ? " " : piece.text)
                                .font(.system(size: fontSize))
                        }
                        .fixedSize()
                    }
                }
                .padding(.horizontal, interactive ? 2 : 0)
                .background {
                    if interactive {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.accentColor.opacity(0.06))
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { onTapWord(word.id) }
            }

            if interactive {
                Image(systemName: "plus.circle")
                    .font(.system(size: fontSize * 0.9))
                    .foregroundStyle(Color.accentColor.opacity(0.6))
                    .padding(.top, hasChords ? fontSize : 0)
                    .contentShape(Rectangle())
                    .onTapGesture { onTapWord(line.plain.count) }
            }
        }
    }

    @ViewBuilder
    private func chordLabel(_ piece: SongPiece) -> some View {
        let label = Text(piece.chord ?? " ")
            .font(.system(size: fontSize * 0.92, weight: .bold))
            .foregroundStyle(chordColor)
            .padding(.trailing, piece.chord == nil ? 0 : fontSize * 0.4)
        if interactive, let index = piece.chordIndex {
            label
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 3))
                .onTapGesture { onTapChord(index) }
        } else {
            label
        }
    }
}

struct SongSectionTitle: View {
    let title: String
    let fontSize: CGFloat

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: fontSize * 0.78, weight: .heavy))
            .tracking(1.2)
            .foregroundStyle(.secondary)
            .padding(.top, fontSize * 0.4)
    }
}

/// A run of lines (whole song, or one stanza for printing).
struct SongLinesView: View {
    let entries: [(index: Int, kind: SongLineKind)]
    let fontSize: CGFloat
    var chordColor: Color = .accentColor
    var interactive = false
    var onTapWord: (Int, Int) -> Void = { _, _ in }
    var onTapChord: (Int, Int) -> Void = { _, _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: fontSize * 0.3) {
            ForEach(entries, id: \.index) { entry in
                switch entry.kind {
                case .blank:
                    Color.clear.frame(height: fontSize * 0.5)
                case .section(let title):
                    SongSectionTitle(title: title, fontSize: fontSize)
                case .lyric(let line):
                    SongLineView(
                        line: line,
                        fontSize: fontSize,
                        chordColor: chordColor,
                        interactive: interactive,
                        onTapWord: { onTapWord(entry.index, $0) },
                        onTapChord: { onTapChord(entry.index, $0) }
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SongHeaderView: View {
    let song: SongSheet
    var scale: CGFloat = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 3 * scale) {
            Text(song.title.isEmpty ? "Untitled" : song.title)
                .font(.system(size: 24 * scale, weight: .bold))
            if !song.artist.isEmpty {
                Text(song.artist)
                    .font(.system(size: 14 * scale, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            if !song.metaLine.isEmpty {
                Text(song.metaLine)
                    .font(.system(size: 11 * scale, weight: .semibold))
                    .padding(.top, 2 * scale)
            }
        }
    }
}

/// Small diagrams for every chord in the song.
struct ChordDiagramStrip: View {
    let song: SongSheet
    var cardWidth: CGFloat = 62
    var onTap: ((String) -> Void)? = nil

    var body: some View {
        WrapLayout(spacing: cardWidth * 0.18, lineSpacing: cardWidth * 0.15) {
            ForEach(song.uniqueChords, id: \.self) { name in
                Group {
                    if let diagram = song.diagram(for: name) {
                        DiagramCard(diagram: diagram, showTuning: false, nameSize: cardWidth * 0.21)
                    } else {
                        VStack(spacing: 4) {
                            Text(name)
                                .font(.system(size: cardWidth * 0.21, weight: .bold))
                            Text("no shape")
                                .font(.system(size: cardWidth * 0.13))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(width: cardWidth, height: cardWidth * 1.45)
                .contentShape(Rectangle())
                .onTapGesture { onTap?(name) }
            }
        }
    }
}
