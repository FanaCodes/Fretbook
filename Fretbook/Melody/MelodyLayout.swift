import SwiftUI

/// Vertical layout of one line of music, in points. `s` is the distance between staff lines.
struct ScoreMetrics {
    let s: CGFloat
    let showStaff: Bool
    let showTab: Bool
    let hasChords: Bool
    let hasLyrics: Bool

    let chordY: CGFloat
    let staffTop: CGFloat
    let lyricY: CGFloat
    let tabTop: CGFloat
    let height: CGFloat

    var staffBottom: CGFloat { staffTop + 4 * s }
    var tabSpacing: CGFloat { s * 1.35 }
    var tabBottom: CGFloat { tabTop + tabSpacing * 5 }
    var lyricSize: CGFloat { s * 1.45 }

    init(melody: Melody, s: CGFloat) {
        self.s = s
        showStaff = melody.display.showsStaff
        showTab = melody.display.showsTab
        hasChords = melody.hasChords
        hasLyrics = melody.hasLyrics

        var y: CGFloat = hasChords ? s * 2.4 : s * 0.6
        chordY = s * 1.2
        var staffTop: CGFloat = 0
        var lyricY: CGFloat = 0
        var tabTop: CGFloat = 0
        if showStaff {
            staffTop = y + s * 2.4             // room for notes above the staff
            y = staffTop + 4 * s + s * 3.0     // and below it
            if hasLyrics {
                lyricY = y + s * 0.5
                y += s * 2.2
            }
        }
        if showTab {
            tabTop = y + s * (showStaff ? 0.8 : 1.6)
            y = tabTop + s * 1.35 * 5 + s * 1.4
            if hasLyrics && !showStaff {
                lyricY = y + s * 0.5
                y += s * 2.2
            }
        }
        self.staffTop = staffTop
        self.lyricY = lyricY
        self.tabTop = tabTop
        height = y
    }

    /// y of a staff step (0 = middle C, 10 = top line F5).
    func y(step: Int) -> CGFloat {
        staffTop + CGFloat(10 - step) * s / 2
    }

    /// Nearest staff step for a touch.
    func step(atY y: CGFloat) -> Int {
        Int((10 - (y - staffTop) / (s / 2)).rounded())
    }

    /// y of a tab string line (0 = lowest string, drawn at the bottom).
    func tabY(string: Int, strings: Int) -> CGFloat {
        tabTop + CGFloat(strings - 1 - string) * tabSpacing
    }
}

struct PlacedNote {
    let index: Int          // index into melody.notes
    let x: CGFloat          // notehead centre
    let start: Double       // position in the bar, in quarter notes
}

struct ScoreSystem: Identifiable {
    let id: Int
    let notes: [PlacedNote]
    let barlines: [CGFloat]
    let headerWidth: CGFloat
    let width: CGFloat
    let isFirst: Bool
    let isLast: Bool
    let firstNoteIndex: Int   // where a tap at the very start inserts
}

enum ScoreLayout {
    static func headerWidth(melody: Melody, s: CGFloat, first: Bool) -> CGFloat {
        if !melody.display.showsStaff {
            return s * 3.2
        }
        var width = s * 3.6 + CGFloat(abs(melody.keySignature)) * s * 1.0
        if first { width += s * 2.4 }
        return width
    }

    private static func space(for note: MelodyNote, s: CGFloat, lyricSize: CGFloat) -> CGFloat {
        let base: CGFloat
        switch note.value {
        case .whole: base = 5.2
        case .half: base = 3.8
        case .quarter: base = 2.8
        case .eighth: base = 2.1
        case .sixteenth: base = 1.7
        }
        var width = base * s * (note.dotted ? 1.2 : 1)
        if note.accidental != .none && !note.isRest { width += s * 1.1 }
        if !note.lyric.isEmpty {
            width = max(width, CGFloat(note.lyric.count) * lyricSize * 0.58 + s * 1.0)
        }
        if !note.chord.isEmpty {
            width = max(width, CGFloat(note.chord.count) * s * 0.95 + s * 0.6)
        }
        return width
    }

    /// Splits the melody into bars and lines that fit `width`.
    static func layout(melody: Melody, width: CGFloat, s: CGFloat) -> [ScoreSystem] {
        let metrics = ScoreMetrics(melody: melody, s: s)
        let capacity = max(melody.barQuarters, 0.25)

        // 1. Bars
        struct Bar {
            var indices: [Int] = []
            var starts: [Double] = []
            var widths: [CGFloat] = []
        }
        var bars: [Bar] = []
        var current = Bar()
        var position = 0.0
        for (index, note) in melody.notes.enumerated() {
            current.indices.append(index)
            current.starts.append(position)
            current.widths.append(space(for: note, s: s, lyricSize: metrics.lyricSize))
            position += note.quarters
            if position >= capacity - 0.0001 {
                bars.append(current)
                current = Bar()
                position = 0
            }
        }
        if !current.indices.isEmpty || bars.isEmpty {
            bars.append(current)
        }

        let padLeft = s * 1.2
        let padRight = s * 0.8
        func natural(_ bar: Bar) -> CGFloat {
            padLeft + bar.widths.reduce(0, +) + padRight + (bar.indices.isEmpty ? s * 6 : 0)
        }

        // 2. Lines
        var lines: [[Bar]] = []
        var line: [Bar] = []
        var used: CGFloat = 0
        for bar in bars {
            let available = width - headerWidth(melody: melody, s: s, first: lines.isEmpty)
            let barWidth = natural(bar)
            if !line.isEmpty && used + barWidth > available {
                lines.append(line)
                line = []
                used = 0
            }
            line.append(bar)
            used += barWidth
        }
        if !line.isEmpty { lines.append(line) }

        // 3. Positions (justify every line except the last)
        var systems: [ScoreSystem] = []
        for (lineIndex, bars) in lines.enumerated() {
            let isFirst = lineIndex == 0
            let isLast = lineIndex == lines.count - 1
            let header = headerWidth(melody: melody, s: s, first: isFirst)
            let available = width - header
            let total = bars.map(natural).reduce(0, +)
            let stretch: CGFloat = (!isLast || total > available) && total > 0 ? available / total : 1

            var x = header
            var placed: [PlacedNote] = []
            var barlines: [CGFloat] = []
            for bar in bars {
                x += padLeft * stretch
                for (k, index) in bar.indices.enumerated() {
                    let w = bar.widths[k] * stretch
                    placed.append(PlacedNote(index: index, x: x + min(w * 0.35, s * 1.6), start: bar.starts[k]))
                    x += w
                }
                if bar.indices.isEmpty { x += s * 6 * stretch }
                x += padRight * stretch
                barlines.append(x)
            }
            systems.append(ScoreSystem(
                id: lineIndex,
                notes: placed,
                barlines: barlines,
                headerWidth: header,
                width: width,
                isFirst: isFirst,
                isLast: isLast,
                firstNoteIndex: bars.first?.indices.first ?? melody.notes.count
            ))
        }
        return systems
    }

    /// Groups of consecutive eighths/16ths that share a beat, to be beamed together.
    static func beamGroups(system: ScoreSystem, melody: Melody) -> [[PlacedNote]] {
        let group = melody.beamGroupQuarters
        var groups: [[PlacedNote]] = []
        var currentGroup: [PlacedNote] = []
        var currentBeat = -1

        func close() {
            if currentGroup.count >= 2 { groups.append(currentGroup) }
            currentGroup = []
        }

        for placed in system.notes {
            let note = melody.notes[placed.index]
            let beat = Int((placed.start / group + 0.0001).rounded(.down))
            let beamable = !note.isRest && note.value.flags > 0
            let startsBar = placed.start < 0.0001
            if !beamable || beat != currentBeat || startsBar {
                close()
            }
            if beamable {
                if currentGroup.isEmpty { currentBeat = beat }
                currentGroup.append(placed)
            }
        }
        close()
        return groups
    }
}
