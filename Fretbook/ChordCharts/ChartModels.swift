import SwiftUI

// MARK: - Notes

enum NoteMath {
    static let sharpNames = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]
    static let flatNames = ["C", "D♭", "D", "E♭", "E", "F", "G♭", "G", "A♭", "A", "B♭", "B"]

    /// "E", "f#", "Bb", "E♭" → pitch class 0–11.
    static func pitchClass(_ name: String) -> Int? {
        let text = name.trimmingCharacters(in: .whitespaces)
        guard let first = text.first else { return nil }
        let bases: [Character: Int] = ["C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11]
        guard let base = bases[Character(first.uppercased())] else { return nil }
        var pc = base
        for accidental in text.dropFirst() {
            switch accidental {
            case "#", "♯": pc += 1
            case "b", "♭": pc -= 1
            default: return nil
            }
        }
        return (pc % 12 + 12) % 12
    }

    static func name(_ pitchClass: Int, flats: Bool) -> String {
        (flats ? flatNames : sharpNames)[(pitchClass % 12 + 12) % 12]
    }

    /// Splits "E A D G B E" / "EADGBE" / "D,A,D,F#,A,D" into note names.
    static func parseTuning(_ text: String) -> [String]? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        var notes: [String]
        if trimmed.contains(where: { $0 == " " || $0 == "," }) {
            notes = trimmed.split(whereSeparator: { $0 == " " || $0 == "," }).map(String.init)
        } else {
            // Compact form: a letter followed by optional accidentals.
            notes = []
            for ch in trimmed {
                if ch.isLetter && ch != "b" || notes.isEmpty {
                    notes.append(String(ch))
                } else {
                    notes[notes.count - 1].append(ch)
                }
            }
        }
        guard (3...9).contains(notes.count), notes.allSatisfy({ pitchClass($0) != nil }) else { return nil }
        return notes.map { pretty($0) }
    }

    /// "f#" → "F♯", "bb" → "B♭"
    static func pretty(_ note: String) -> String {
        guard let first = note.first else { return note }
        let rest = note.dropFirst()
            .replacingOccurrences(of: "#", with: "♯")
            .replacingOccurrences(of: "b", with: "♭")
        return first.uppercased() + rest
    }
}

struct TuningPreset: Identifiable {
    let name: String
    let notes: [String]
    var id: String { name }
}

enum Tunings {
    static let standard = ["E", "A", "D", "G", "B", "E"]

    static let presets: [TuningPreset] = [
        TuningPreset(name: "Standard", notes: standard),
        TuningPreset(name: "Drop D", notes: ["D", "A", "D", "G", "B", "E"]),
        TuningPreset(name: "E♭ Standard", notes: ["E♭", "A♭", "D♭", "G♭", "B♭", "E♭"]),
        TuningPreset(name: "D Standard", notes: ["D", "G", "C", "F", "A", "D"]),
        TuningPreset(name: "Drop C", notes: ["C", "G", "C", "F", "A", "D"]),
        TuningPreset(name: "DADGAD", notes: ["D", "A", "D", "G", "A", "D"]),
        TuningPreset(name: "Open G", notes: ["D", "G", "D", "G", "B", "D"]),
        TuningPreset(name: "Open D", notes: ["D", "A", "D", "F♯", "A", "D"]),
        TuningPreset(name: "Open E", notes: ["E", "B", "E", "G♯", "B", "E"]),
        TuningPreset(name: "Open C", notes: ["C", "G", "C", "G", "C", "E"]),
        TuningPreset(name: "7-String", notes: ["B", "E", "A", "D", "G", "B", "E"]),
        TuningPreset(name: "Bass (4)", notes: ["E", "A", "D", "G"]),
        TuningPreset(name: "Bass (5)", notes: ["B", "E", "A", "D", "G"]),
        TuningPreset(name: "Ukulele", notes: ["G", "C", "E", "A"]),
        TuningPreset(name: "Baritone Ukulele", notes: ["D", "G", "B", "E"]),
        TuningPreset(name: "Mandolin", notes: ["G", "D", "A", "E"]),
    ]

    static func name(for notes: [String]) -> String {
        presets.first { $0.notes == notes }?.name ?? notes.joined(separator: " ")
    }
}

// MARK: - Diagram

enum StringMark: String, Codable {
    case none, open, muted

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = StringMark(rawValue: raw) ?? .none
    }
}

enum DotStyle: String, Codable, CaseIterable, Identifiable {
    case normal, root, ghost

    var id: String { rawValue }

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = DotStyle(rawValue: raw) ?? .normal
    }

    var label: String {
        switch self {
        case .normal: return "Normal"
        case .root: return "Root"
        case .ghost: return "Optional"
        }
    }
}

enum DiagramKind: String, Codable, CaseIterable, Identifiable {
    case box, neck

    var id: String { rawValue }

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = DiagramKind(rawValue: raw) ?? .box
    }

    var label: String { self == .box ? "Chord box" : "Fretboard" }
}

struct Dot: Identifiable, Codable, Hashable {
    var id = UUID()
    var string: Int         // 0 = lowest string
    var fret: Int           // absolute fret number (0 = open string, 1…24)
    var label = ""
    var style: DotStyle = .normal

    init(string: Int, fret: Int, label: String = "", style: DotStyle = .normal) {
        self.string = string
        self.fret = fret
        self.label = label
        self.style = style
    }

    enum CodingKeys: String, CodingKey { case id, string, fret, label, style }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        string = try c.decodeIfPresent(Int.self, forKey: .string) ?? 0
        fret = try c.decodeIfPresent(Int.self, forKey: .fret) ?? 1
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
        style = try c.decodeIfPresent(DotStyle.self, forKey: .style) ?? .normal
    }
}

struct Barre: Identifiable, Codable, Hashable {
    var id = UUID()
    var fret: Int
    var fromString: Int
    var toString: Int
    var label = "1"

    init(fret: Int, fromString: Int, toString: Int, label: String = "1") {
        self.fret = fret
        self.fromString = min(fromString, toString)
        self.toString = max(fromString, toString)
        self.label = label
    }

    func covers(_ string: Int) -> Bool { string >= fromString && string <= toString }

    enum CodingKeys: String, CodingKey { case id, fret, fromString, toString, label }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        fret = try c.decodeIfPresent(Int.self, forKey: .fret) ?? 1
        fromString = try c.decodeIfPresent(Int.self, forKey: .fromString) ?? 0
        toString = try c.decodeIfPresent(Int.self, forKey: .toString) ?? 0
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
    }
}

/// One chord (or scale) box: tuning, visible fret window, dots, barres and open/muted marks.
struct FretDiagram: Identifiable, Codable, Hashable {
    var id = UUID()
    var name = ""
    var caption = ""
    var tuning: [String] = Tunings.standard     // lowest string first
    var startFret = 1
    var fretCount = 5
    var marks: [StringMark] = Array(repeating: .none, count: 6)
    var dots: [Dot] = []
    var barres: [Barre] = []
    var preferFlats = false
    var kind: DiagramKind = .box

    init(name: String = "") {
        self.name = name
    }

    var stringCount: Int { tuning.count }

    func mark(_ string: Int) -> StringMark {
        string < marks.count ? marks[string] : .none
    }

    mutating func setMark(_ mark: StringMark, for string: Int) {
        while marks.count < stringCount { marks.append(.none) }
        if string < marks.count { marks[string] = mark }
    }

    mutating func setTuning(_ notes: [String]) {
        tuning = notes
        if marks.count > notes.count {
            marks = Array(marks.prefix(notes.count))
        }
        while marks.count < notes.count { marks.append(.none) }
        dots.removeAll { $0.string >= notes.count }
        barres = barres.compactMap { barre in
            guard barre.fromString < notes.count else { return nil }
            var clipped = barre
            clipped.toString = min(barre.toString, notes.count - 1)
            return clipped.fromString == clipped.toString ? nil : clipped
        }
    }

    func noteName(string: Int, fret: Int) -> String {
        guard string < tuning.count, let open = NoteMath.pitchClass(tuning[string]) else { return "" }
        return NoteMath.name(open + fret, flats: preferFlats)
    }

    /// The fret each string actually sounds at (nil = not played), considering dots, barres and marks.
    var soundingFrets: [Int?] {
        (0..<stringCount).map { string in
            if mark(string) == .muted { return nil }
            let dotFret = dots.filter { $0.string == string && $0.style != .ghost }.map(\.fret).max()
            let barreFret = barres.filter { $0.covers(string) }.map(\.fret).max()
            if let fret = [dotFret, barreFret].compactMap({ $0 }).max() { return fret }
            return mark(string) == .open ? 0 : nil
        }
    }

    var isEmpty: Bool { dots.isEmpty && barres.isEmpty && !marks.contains(where: { $0 != .none }) }

    /// Moves the visible window so every dot and barre is on screen.
    mutating func fitWindow() {
        let frets = (dots.map(\.fret) + barres.map(\.fret)).filter { $0 > 0 }
        guard let low = frets.min(), let high = frets.max() else { return }
        if high <= fretCount {
            startFret = 1
        } else if low < startFret || high >= startFret + fretCount {
            startFret = max(1, low)
        }
        fretCount = max(fretCount, high - startFret + 1)
    }

    enum CodingKeys: String, CodingKey {
        case id, name, caption, tuning, startFret, fretCount, marks, dots, barres, preferFlats, kind
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        caption = try c.decodeIfPresent(String.self, forKey: .caption) ?? ""
        tuning = try c.decodeIfPresent([String].self, forKey: .tuning) ?? Tunings.standard
        if tuning.isEmpty { tuning = Tunings.standard }
        startFret = try max(1, c.decodeIfPresent(Int.self, forKey: .startFret) ?? 1)
        fretCount = try min(24, max(2, c.decodeIfPresent(Int.self, forKey: .fretCount) ?? 5))
        marks = try c.decodeIfPresent([StringMark].self, forKey: .marks) ?? []
        dots = try c.decodeIfPresent([Dot].self, forKey: .dots) ?? []
        barres = try c.decodeIfPresent([Barre].self, forKey: .barres) ?? []
        preferFlats = try c.decodeIfPresent(Bool.self, forKey: .preferFlats) ?? false
        kind = try c.decodeIfPresent(DiagramKind.self, forKey: .kind) ?? .box
        while marks.count < tuning.count { marks.append(.none) }
    }
}

// MARK: - Chart sheet

enum PaperSize: String, Codable, CaseIterable, Identifiable {
    case a4, letter

    var id: String { rawValue }

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = PaperSize(rawValue: raw) ?? .a4
    }

    var label: String { self == .a4 ? "A4" : "US Letter" }

    /// Page size in PDF points (1/72 inch).
    var size: CGSize {
        self == .a4 ? CGSize(width: 595.28, height: 841.89) : CGSize(width: 612, height: 792)
    }

    static var regionalDefault: PaperSize {
        let region = Locale.current.region?.identifier ?? ""
        return ["US", "CA", "MX", "PH"].contains(region) ? .letter : .a4
    }
}

struct ChartLayout: Identifiable, Hashable {
    let columns: Int
    let rows: Int

    var id: String { "\(columns)x\(rows)" }
    var perPage: Int { columns * rows }

    var label: String {
        perPage == 1 ? "1 per page (full page)" : "\(perPage) per page (\(columns) × \(rows))"
    }

    static let presets: [ChartLayout] = [
        ChartLayout(columns: 1, rows: 1),
        ChartLayout(columns: 1, rows: 2),
        ChartLayout(columns: 1, rows: 3),
        ChartLayout(columns: 1, rows: 4),
        ChartLayout(columns: 1, rows: 5),
        ChartLayout(columns: 2, rows: 4),
        ChartLayout(columns: 2, rows: 2),
        ChartLayout(columns: 2, rows: 3),
        ChartLayout(columns: 3, rows: 3),
        ChartLayout(columns: 3, rows: 4),
        ChartLayout(columns: 4, rows: 4),
        ChartLayout(columns: 4, rows: 5),
        ChartLayout(columns: 4, rows: 6),
        ChartLayout(columns: 5, rows: 6),
    ]
}

struct ChordChart: Identifiable, Codable, Hashable {
    var id = UUID()
    var title = "Chord Chart"
    var subtitle = ""
    var columns = 3
    var rows = 3
    var paper: PaperSize = .regionalDefault
    var showTuning = true
    var showNoteNames = false
    var leftHanded = false
    var woodFretboard = true
    var diagrams: [FretDiagram] = []
    var created = Date()

    init(title: String = "Chord Chart") {
        self.title = title
    }

    var layout: ChartLayout {
        get { ChartLayout(columns: columns, rows: rows) }
        set {
            columns = newValue.columns
            rows = newValue.rows
        }
    }

    var perPage: Int { max(1, columns * rows) }
    var pageCount: Int { max(1, (diagrams.count + perPage - 1) / perPage) }

    func diagrams(onPage page: Int) -> ArraySlice<FretDiagram> {
        let start = min(page * perPage, diagrams.count)
        let end = min(start + perPage, diagrams.count)
        return diagrams[start..<end]
    }

    enum CodingKeys: String, CodingKey {
        case id, title, subtitle, columns, rows, paper, showTuning, showNoteNames, leftHanded, woodFretboard, diagrams, created
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? "Chord Chart"
        subtitle = try c.decodeIfPresent(String.self, forKey: .subtitle) ?? ""
        columns = try min(6, max(1, c.decodeIfPresent(Int.self, forKey: .columns) ?? 3))
        rows = try min(8, max(1, c.decodeIfPresent(Int.self, forKey: .rows) ?? 3))
        paper = try c.decodeIfPresent(PaperSize.self, forKey: .paper) ?? .regionalDefault
        showTuning = try c.decodeIfPresent(Bool.self, forKey: .showTuning) ?? true
        showNoteNames = try c.decodeIfPresent(Bool.self, forKey: .showNoteNames) ?? false
        leftHanded = try c.decodeIfPresent(Bool.self, forKey: .leftHanded) ?? false
        woodFretboard = try c.decodeIfPresent(Bool.self, forKey: .woodFretboard) ?? true
        diagrams = try c.decodeIfPresent([FretDiagram].self, forKey: .diagrams) ?? []
        created = try c.decodeIfPresent(Date.self, forKey: .created) ?? Date()
    }
}

// MARK: - Chord naming

enum ChordNamer {
    private static let qualities: [(suffix: String, intervals: Set<Int>)] = [
        ("", [0, 4, 7]), ("m", [0, 3, 7]), ("5", [0, 7]),
        ("dim", [0, 3, 6]), ("aug", [0, 4, 8]),
        ("sus2", [0, 2, 7]), ("sus4", [0, 5, 7]),
        ("6", [0, 4, 7, 9]), ("m6", [0, 3, 7, 9]),
        ("7", [0, 4, 7, 10]), ("maj7", [0, 4, 7, 11]), ("m7", [0, 3, 7, 10]),
        ("m(maj7)", [0, 3, 7, 11]), ("m7♭5", [0, 3, 6, 10]), ("dim7", [0, 3, 6, 9]),
        ("7sus4", [0, 5, 7, 10]), ("add9", [0, 2, 4, 7]), ("m(add9)", [0, 2, 3, 7]),
        ("9", [0, 2, 4, 7, 10]), ("maj9", [0, 2, 4, 7, 11]), ("m9", [0, 2, 3, 7, 10]),
        ("6/9", [0, 2, 4, 7, 9]), ("7♯9", [0, 3, 4, 7, 10]), ("7♭9", [0, 1, 4, 7, 10]),
        ("11", [0, 2, 4, 5, 7, 10]), ("m11", [0, 2, 3, 5, 7, 10]), ("13", [0, 2, 4, 7, 9, 10]),
    ]

    /// Best guesses for the chord name, most likely first.
    static func suggestions(for diagram: FretDiagram) -> [String] {
        var pitchClasses: [Int] = []
        for (string, fret) in diagram.soundingFrets.enumerated() {
            guard let fret, string < diagram.tuning.count, let open = NoteMath.pitchClass(diagram.tuning[string]) else { continue }
            pitchClasses.append((open + fret) % 12)
        }
        guard let bass = pitchClasses.first else { return [] }
        let unique = Set(pitchClasses)
        guard unique.count >= 2 else { return [] }

        var candidates: [(score: Int, name: String)] = []
        let roots = [bass] + unique.filter { $0 != bass }.sorted()
        for root in roots {
            let intervals = Set(unique.map { ($0 - root + 12) % 12 })
            for quality in qualities {
                var score = 0
                if intervals == quality.intervals {
                    score = 10
                } else if !intervals.contains(7), quality.intervals.count >= 4, intervals.union([7]) == quality.intervals {
                    score = 6   // fifth left out, very common on guitar
                }
                guard score > 0 else { continue }
                if root == bass { score += 3 }
                score -= quality.suffix.count / 3
                let rootName = NoteMath.name(root, flats: diagram.preferFlats)
                let bassName = NoteMath.name(bass, flats: diagram.preferFlats)
                let name = rootName + quality.suffix + (root == bass ? "" : "/" + bassName)
                candidates.append((score, name))
            }
        }

        var seen = Set<String>()
        return candidates
            .sorted { $0.score > $1.score }
            .map(\.name)
            .filter { seen.insert($0).inserted }
            .prefix(4)
            .map { $0 }
    }
}

// MARK: - Shape library

struct ShapePreset: Identifiable {
    let name: String
    let frets: String       // low E → high e, x = muted
    let fingers: String     // same length, "-" = none
    var id: String { name }

    /// Builds a standard-tuning diagram. Finger 1 used on several strings at one fret becomes a barre.
    var diagram: FretDiagram {
        var diagram = FretDiagram(name: name)
        guard let shape = ChordShape(frets) else { return diagram }
        let fingerChars = Array(fingers)

        var dots: [Dot] = []
        for (string, fret) in shape.frets.enumerated() {
            guard let fret else {
                diagram.setMark(.muted, for: string)
                continue
            }
            if fret == 0 {
                diagram.setMark(.open, for: string)
                continue
            }
            let finger = string < fingerChars.count && fingerChars[string] != "-" ? String(fingerChars[string]) : ""
            dots.append(Dot(string: string, fret: fret, label: finger))
        }

        let ones = dots.filter { $0.label == "1" }
        if ones.count >= 2, let fret = ones.first?.fret, ones.allSatisfy({ $0.fret == fret }),
           let low = ones.map(\.string).min(), let high = ones.map(\.string).max() {
            diagram.barres = [Barre(fret: fret, fromString: low, toString: high, label: "1")]
            dots.removeAll { $0.label == "1" }
        }

        diagram.dots = dots
        diagram.fitWindow()
        return diagram
    }

    static let common: [ShapePreset] = [
        ShapePreset(name: "C", frets: "x32010", fingers: "-32-1-"),
        ShapePreset(name: "A", frets: "x02220", fingers: "--123-"),
        ShapePreset(name: "G", frets: "320003", fingers: "21---3"),
        ShapePreset(name: "E", frets: "022100", fingers: "-231--"),
        ShapePreset(name: "D", frets: "xx0232", fingers: "---132"),
        ShapePreset(name: "Am", frets: "x02210", fingers: "--231-"),
        ShapePreset(name: "Em", frets: "022000", fingers: "-23---"),
        ShapePreset(name: "Dm", frets: "xx0231", fingers: "---231"),
        ShapePreset(name: "F", frets: "133211", fingers: "134211"),
        ShapePreset(name: "Bm", frets: "x24432", fingers: "-13421"),
        ShapePreset(name: "F♯m", frets: "244222", fingers: "134111"),
        ShapePreset(name: "B♭", frets: "x13331", fingers: "-12341"),
        ShapePreset(name: "C7", frets: "x32310", fingers: "-3241-"),
        ShapePreset(name: "A7", frets: "x02020", fingers: "--2-3-"),
        ShapePreset(name: "G7", frets: "320001", fingers: "32---1"),
        ShapePreset(name: "E7", frets: "020100", fingers: "-2-1--"),
        ShapePreset(name: "D7", frets: "xx0212", fingers: "---213"),
        ShapePreset(name: "B7", frets: "x21202", fingers: "-213-4"),
        ShapePreset(name: "Am7", frets: "x02010", fingers: "--2-1-"),
        ShapePreset(name: "Em7", frets: "022030", fingers: "-12-3-"),
        ShapePreset(name: "Dm7", frets: "xx0211", fingers: "---211"),
        ShapePreset(name: "Cmaj7", frets: "x32000", fingers: "-32---"),
        ShapePreset(name: "Fmaj7", frets: "xx3210", fingers: "--321-"),
        ShapePreset(name: "Amaj7", frets: "x02120", fingers: "--213-"),
        ShapePreset(name: "Dmaj7", frets: "xx0222", fingers: "---111"),
        ShapePreset(name: "Asus2", frets: "x02200", fingers: "--12--"),
        ShapePreset(name: "Asus4", frets: "x02230", fingers: "--124-"),
        ShapePreset(name: "Dsus2", frets: "xx0230", fingers: "---13-"),
        ShapePreset(name: "Dsus4", frets: "xx0233", fingers: "---134"),
        ShapePreset(name: "Cadd9", frets: "x32030", fingers: "-21-3-"),
        ShapePreset(name: "E5", frets: "022xxx", fingers: "-11---"),
        ShapePreset(name: "A5", frets: "x022xx", fingers: "--11--"),
    ]

    static let openChords = ["C", "A", "G", "E", "D", "Am", "Em", "Dm"]
}

// MARK: - Scales & arpeggios

struct ScaleType: Identifiable {
    let name: String
    let group: String
    let steps: [(semitones: Int, label: String)]
    var id: String { name }

    var isMinor: Bool { steps.contains { $0.semitones == 3 } && !steps.contains { $0.semitones == 4 } }
}

enum Scales {
    static let all: [ScaleType] = [
        ScaleType(name: "Major", group: "Scales", steps: [(0, "R"), (2, "2"), (4, "3"), (5, "4"), (7, "5"), (9, "6"), (11, "7")]),
        ScaleType(name: "Natural Minor", group: "Scales", steps: [(0, "R"), (2, "2"), (3, "♭3"), (5, "4"), (7, "5"), (8, "♭6"), (10, "♭7")]),
        ScaleType(name: "Major Pentatonic", group: "Scales", steps: [(0, "R"), (2, "2"), (4, "3"), (7, "5"), (9, "6")]),
        ScaleType(name: "Minor Pentatonic", group: "Scales", steps: [(0, "R"), (3, "♭3"), (5, "4"), (7, "5"), (10, "♭7")]),
        ScaleType(name: "Blues", group: "Scales", steps: [(0, "R"), (3, "♭3"), (5, "4"), (6, "♭5"), (7, "5"), (10, "♭7")]),
        ScaleType(name: "Major Blues", group: "Scales", steps: [(0, "R"), (2, "2"), (3, "♭3"), (4, "3"), (7, "5"), (9, "6")]),
        ScaleType(name: "Harmonic Minor", group: "Scales", steps: [(0, "R"), (2, "2"), (3, "♭3"), (5, "4"), (7, "5"), (8, "♭6"), (11, "7")]),
        ScaleType(name: "Melodic Minor", group: "Scales", steps: [(0, "R"), (2, "2"), (3, "♭3"), (5, "4"), (7, "5"), (9, "6"), (11, "7")]),
        ScaleType(name: "Dorian", group: "Modes", steps: [(0, "R"), (2, "2"), (3, "♭3"), (5, "4"), (7, "5"), (9, "6"), (10, "♭7")]),
        ScaleType(name: "Phrygian", group: "Modes", steps: [(0, "R"), (1, "♭2"), (3, "♭3"), (5, "4"), (7, "5"), (8, "♭6"), (10, "♭7")]),
        ScaleType(name: "Lydian", group: "Modes", steps: [(0, "R"), (2, "2"), (4, "3"), (6, "♯4"), (7, "5"), (9, "6"), (11, "7")]),
        ScaleType(name: "Mixolydian", group: "Modes", steps: [(0, "R"), (2, "2"), (4, "3"), (5, "4"), (7, "5"), (9, "6"), (10, "♭7")]),
        ScaleType(name: "Locrian", group: "Modes", steps: [(0, "R"), (1, "♭2"), (3, "♭3"), (5, "4"), (6, "♭5"), (8, "♭6"), (10, "♭7")]),
        ScaleType(name: "Major Arpeggio", group: "Arpeggios", steps: [(0, "R"), (4, "3"), (7, "5")]),
        ScaleType(name: "Minor Arpeggio", group: "Arpeggios", steps: [(0, "R"), (3, "♭3"), (7, "5")]),
        ScaleType(name: "Dominant 7 Arpeggio", group: "Arpeggios", steps: [(0, "R"), (4, "3"), (7, "5"), (10, "♭7")]),
        ScaleType(name: "Major 7 Arpeggio", group: "Arpeggios", steps: [(0, "R"), (4, "3"), (7, "5"), (11, "7")]),
        ScaleType(name: "Minor 7 Arpeggio", group: "Arpeggios", steps: [(0, "R"), (3, "♭3"), (7, "5"), (10, "♭7")]),
        ScaleType(name: "m7♭5 Arpeggio", group: "Arpeggios", steps: [(0, "R"), (3, "♭3"), (6, "♭5"), (10, "♭7")]),
        ScaleType(name: "Diminished 7 Arpeggio", group: "Arpeggios", steps: [(0, "R"), (3, "♭3"), (6, "♭5"), (9, "♭♭7")]),
    ]

    static let groups = ["Scales", "Modes", "Arpeggios"]
}

enum ScaleLabels: String, CaseIterable, Identifiable {
    case fingers, intervals, notes, none

    var id: String { rawValue }

    var label: String {
        switch self {
        case .intervals: return "Intervals"
        case .notes: return "Notes"
        case .none: return "Dots only"
        case .fingers: return "Fingers"
        }
    }
}

extension FretDiagram {
    /// Lowest and highest fret currently visible (fret 0 included when the nut is shown).
    var visibleFrets: ClosedRange<Int> {
        (startFret == 1 ? 0 : startFret)...(startFret + fretCount - 1)
    }

    /// Replaces the diagram's dots with every note of a scale/arpeggio in `range`
    /// (default: the visible window).
    mutating func fill(scale: ScaleType, root: Int, labels: ScaleLabels, range: ClosedRange<Int>? = nil) {
        let relativeMajor = scale.isMinor ? (root + 3) % 12 : root
        preferFlats = [1, 3, 5, 8, 10].contains(relativeMajor)
        let frets = range ?? visibleFrets

        var steps: [Int: String] = [:]
        for step in scale.steps { steps[step.semitones] = step.label }

        dots = []
        barres = []
        marks = Array(repeating: .none, count: stringCount)
        for string in 0..<stringCount {
            guard let open = NoteMath.pitchClass(tuning[string]) else { continue }
            let matches = frets.filter { steps[((open + $0 - root) % 12 + 12) % 12] != nil }
            // One finger per fret. In a 5-fret window the index finger stretches back only
            // on strings that have a note on the first fret.
            let stretch = frets.count > 4 && !matches.contains(frets.lowerBound)
            let fingerBase = stretch ? frets.lowerBound + 1 : frets.lowerBound
            for fret in matches {
                let interval = ((open + fret - root) % 12 + 12) % 12
                guard let label = steps[interval] else { continue }
                let text: String
                switch labels {
                case .fingers: text = fret == 0 ? "0" : "\(min(4, max(1, fret - fingerBase + 1)))"
                case .intervals: text = label
                case .notes: text = NoteMath.name(open + fret, flats: preferFlats)
                case .none: text = ""
                }
                dots.append(Dot(string: string, fret: fret, label: text, style: interval == 0 ? .root : .normal))
            }
        }
        name = "\(NoteMath.name(root, flats: preferFlats)) \(scale.name)"
    }

    /// The five classic scale positions, each drawn on a full fretboard.
    /// Windows are measured from the (relative) major root on the lowest string,
    /// e.g. G major → frets 2–5, 4–8, 7–10, 9–13, 12–15.
    static func scalePositions(scale: ScaleType, root: Int, labels: ScaleLabels,
                               tuning: [String] = Tunings.standard, neckLength: Int = 15) -> [FretDiagram] {
        guard let lowest = NoteMath.pitchClass(tuning.first ?? "E") else { return [] }
        let reference = scale.isMinor ? (root + 3) % 12 : root
        let rootFret = ((reference - lowest) % 12 + 12) % 12
        let windows = [(-1, 2), (1, 5), (4, 7), (6, 10), (9, 12)]

        let ranges = windows.map { window -> ClosedRange<Int> in
            var low = rootFret + window.0
            var high = rootFret + window.1
            if low < 1 {
                low += 12
                high += 12
            }
            if high > neckLength && low - 12 >= 1 {
                low -= 12
                high -= 12
            }
            return low...high
        }
        .sorted { $0.lowerBound < $1.lowerBound }

        let length = max(neckLength, ranges.map(\.upperBound).max() ?? neckLength)
        return ranges.enumerated().map { index, range in
            var diagram = FretDiagram()
            diagram.setTuning(tuning)
            diagram.kind = .neck
            diagram.startFret = 1
            diagram.fretCount = length
            diagram.fill(scale: scale, root: root, labels: labels, range: range)
            diagram.name = "Position \(index + 1)"
            return diagram
        }
    }

    /// Converts a lesson chord note ("Am", "x02210") into a chart diagram,
    /// using the library shape (with fingerings) when it's the same shape.
    static func fromChordNote(name: String, frets: String) -> FretDiagram? {
        guard let shape = ChordShape(frets) else { return nil }
        var diagram: FretDiagram
        if let preset = ShapePreset.common.first(where: { ChordShape($0.frets) == shape }) {
            diagram = preset.diagram
        } else {
            diagram = ShapePreset(name: name, frets: frets, fingers: "").diagram
        }
        if !name.isEmpty { diagram.name = name }
        return diagram
    }
}
