import SwiftUI

enum InputPanel: String, CaseIterable, Identifiable {
    case piano, fretboard, staff

    var id: String { rawValue }

    var label: String {
        switch self {
        case .piano: return "Piano"
        case .fretboard: return "Fretboard"
        case .staff: return "Tap staff"
        }
    }

    var symbol: String {
        switch self {
        case .piano: return "pianokeys"
        case .fretboard: return "guitars"
        case .staff: return "hand.tap"
        }
    }
}

/// Two-octave keyboard (written pitch). Tapping a key enters that note.
struct PianoKeyboard: View {
    let lowestOctave: Int
    var octaves = 2
    var highlighted: Int?
    let onKey: (Int) -> Void

    private static let whiteSemitones = [0, 2, 4, 5, 7, 9, 11]
    private static let blackAfter: Set<Int> = [0, 1, 3, 4, 5]   // C# D# F# G# A#

    private func whiteMidi(_ index: Int) -> Int {
        let octave = lowestOctave + index / 7
        return 12 * (octave + 1) + Self.whiteSemitones[index % 7]
    }

    var body: some View {
        GeometryReader { geo in
            let whiteCount = 7 * octaves + 1
            let keyWidth = geo.size.width / CGFloat(whiteCount)
            let height = geo.size.height

            ZStack(alignment: .topLeading) {
                HStack(spacing: 0) {
                    ForEach(0..<whiteCount, id: \.self) { index in
                        let midi = whiteMidi(index)
                        Button {
                            onKey(midi)
                        } label: {
                            ZStack(alignment: .bottom) {
                                Rectangle()
                                    .fill(highlighted == midi ? Color.accentColor.opacity(0.35) : Color.white)
                                Rectangle()
                                    .stroke(Color.black.opacity(0.35), lineWidth: 1)
                                if index % 7 == 0 {
                                    Text("C\(lowestOctave + index / 7)")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.gray)
                                        .padding(.bottom, 4)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .frame(width: keyWidth, height: height)
                    }
                }

                ForEach(0..<(whiteCount - 1), id: \.self) { index in
                    if Self.blackAfter.contains(index % 7) {
                        let midi = whiteMidi(index) + 1
                        Button {
                            onKey(midi)
                        } label: {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(highlighted == midi ? Color.accentColor : Color.black)
                        }
                        .buttonStyle(.plain)
                        .frame(width: keyWidth * 0.6, height: height * 0.6)
                        .offset(x: CGFloat(index + 1) * keyWidth - keyWidth * 0.3)
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

/// Strings × frets 0–12. Tapping a position enters that note on that string.
struct FretboardPad: View {
    let tuning: [String]
    var frets = 12
    var highlighted: (string: Int, fret: Int)?
    let onTap: (Int, Int) -> Void

    var body: some View {
        VStack(spacing: 2) {
            ForEach((0..<tuning.count).reversed(), id: \.self) { string in
                HStack(spacing: 2) {
                    Text(tuning[string])
                        .font(.caption.weight(.bold))
                        .frame(width: 24)
                    ForEach(0...frets, id: \.self) { fret in
                        let isOn = highlighted?.string == string && highlighted?.fret == fret
                        Button {
                            onTap(string, fret)
                        } label: {
                            Text("\(fret)")
                                .font(.caption2.weight(isOn ? .bold : .regular))
                                .foregroundStyle(isOn ? Color.white : Color.black.opacity(0.55))
                                .frame(maxWidth: .infinity, minHeight: 22)
                                .background(
                                    isOn ? Color.accentColor : (fret == 0 ? Color(white: 0.92) : FretDiagramView.wood),
                                    in: RoundedRectangle(cornerRadius: 3)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            HStack(spacing: 2) {
                Color.clear.frame(width: 24, height: 8)
                ForEach(0...frets, id: \.self) { fret in
                    Circle()
                        .fill([3, 5, 7, 9, 12].contains(fret) ? Color.secondary.opacity(0.5) : Color.clear)
                        .frame(width: 5, height: 5)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }
}
