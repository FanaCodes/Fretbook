import Foundation

// MARK: - Note values

enum NoteValue: Int, Codable, CaseIterable, Identifiable {
    case whole = 1, half = 2, quarter = 4, eighth = 8, sixteenth = 16

    var id: Int { rawValue }

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(Int.self)
        self = NoteValue(rawValue: raw) ?? .quarter
    }

    /// Length in quarter notes.
    var quarters: Double { 4.0 / Double(rawValue) }

    var label: String {
        switch self {
        case .whole: return "Whole"
        case .half: return "Half"
        case .quarter: return "Quarter"
        case .eighth: return "Eighth"
        case .sixteenth: return "16th"
        }
    }

    var hasStem: Bool { self != .whole }
    var isFilled: Bool { rawValue >= 4 }
    var flags: Int { self == .eighth ? 1 : self == .sixteenth ? 2 : 0 }
}

enum Accidental: String, Codable, CaseIterable {
    case none, sharp, flat, natural

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Accidental(rawValue: raw) ?? .none
    }

    var symbol: String {
        switch self {
        case .none: return ""
        case .sharp: return "♯"
        case .flat: return "♭"
        case .natural: return "♮"
        }
    }
}

// MARK: - Note

struct MelodyNote: Identifiable, Codable, Hashable {
    var id = UUID()
    /// Staff position: 0 = middle C (C4), 1 = D4, 2 = E4 (bottom line) … 10 = F5 (top line).
    var step = 4
    var accidental: Accidental = .none
    var value: NoteValue = .quarter
    var dotted = false
    var isRest = false
    var lyric = ""
    var chord = ""
    /// Tab string chosen by hand (0 = lowest string); nil = automatic.
    var string: Int? = nil

    init(step: Int = 4, value: NoteValue = .quarter, isRest: Bool = false) {
        self.step = step
        self.value = value
        self.isRest = isRest
    }

    var quarters: Double { value.quarters * (dotted ? 1.5 : 1) }

    func midi(keySignature: Int) -> Int {
        MusicTheory.midi(step: step, accidental: accidental, keySignature: keySignature)
    }

    enum CodingKeys: String, CodingKey { case id, step, accidental, value, dotted, isRest, lyric, chord, string }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        step = try c.decodeIfPresent(Int.self, forKey: .step) ?? 4
        accidental = try c.decodeIfPresent(Accidental.self, forKey: .accidental) ?? .none
        value = try c.decodeIfPresent(NoteValue.self, forKey: .value) ?? .quarter
        dotted = try c.decodeIfPresent(Bool.self, forKey: .dotted) ?? false
        isRest = try c.decodeIfPresent(Bool.self, forKey: .isRest) ?? false
        lyric = try c.decodeIfPresent(String.self, forKey: .lyric) ?? ""
        chord = try c.decodeIfPresent(String.self, forKey: .chord) ?? ""
        string = try c.decodeIfPresent(Int.self, forKey: .string)
    }
}

// MARK: - Melody

enum ScoreDisplay: String, Codable, CaseIterable, Identifiable {
    case staff, staffAndTab, tab

    var id: String { rawValue }

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ScoreDisplay(rawValue: raw) ?? .staff
    }

    var label: String {
        switch self {
        case .staff: return "Notes"
        case .staffAndTab: return "Notes + Tab"
        case .tab: return "Tab"
        }
    }

    var showsStaff: Bool { self != .tab }
    var showsTab: Bool { self != .staff }
}

struct Melody: Identifiable, Codable, Hashable {
    var id = UUID()
    var title = "New Melody"
    var subtitle = ""
    var keySignature = 0        // +sharps / −flats
    var beatsPerBar = 4
    var beatUnit = 4
    var tempo = 90
    var display: ScoreDisplay = .staff
    var tuning: [String] = Tunings.standard
    var notes: [MelodyNote] = []
    var created = Date()

    init(title: String = "New Melody") {
        self.title = title
    }

    var barQuarters: Double { Double(beatsPerBar) * 4 / Double(beatUnit) }

    /// Notes are beamed within these groups: a quarter, or a dotted quarter in 6/8, 9/8, 12/8.
    var beamGroupQuarters: Double { beatUnit == 8 && beatsPerBar % 3 == 0 ? 1.5 : 1 }

    var keyName: String {
        MusicTheory.keys.first { $0.signature == keySignature }?.name ?? "C"
    }

    var hasLyrics: Bool { notes.contains { !$0.lyric.isEmpty } }
    var hasChords: Bool { notes.contains { !$0.chord.isEmpty } }

    enum CodingKeys: String, CodingKey {
        case id, title, subtitle, keySignature, beatsPerBar, beatUnit, tempo, display, tuning, notes, created
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? "Melody"
        subtitle = try c.decodeIfPresent(String.self, forKey: .subtitle) ?? ""
        keySignature = try min(7, max(-7, c.decodeIfPresent(Int.self, forKey: .keySignature) ?? 0))
        beatsPerBar = try min(16, max(1, c.decodeIfPresent(Int.self, forKey: .beatsPerBar) ?? 4))
        beatUnit = try c.decodeIfPresent(Int.self, forKey: .beatUnit) ?? 4
        if ![2, 4, 8].contains(beatUnit) { beatUnit = 4 }
        tempo = try min(300, max(20, c.decodeIfPresent(Int.self, forKey: .tempo) ?? 90))
        display = try c.decodeIfPresent(ScoreDisplay.self, forKey: .display) ?? .staff
        tuning = try c.decodeIfPresent([String].self, forKey: .tuning) ?? Tunings.standard
        if tuning.isEmpty { tuning = Tunings.standard }
        notes = try c.decodeIfPresent([MelodyNote].self, forKey: .notes) ?? []
        created = try c.decodeIfPresent(Date.self, forKey: .created) ?? Date()
    }
}

// MARK: - Theory helpers

enum MusicTheory {
    static let degreeSemitones = [0, 2, 4, 5, 7, 9, 11]
    static let sharpOrder = [3, 0, 4, 1, 5, 2, 6]      // F C G D A E B
    static let flatOrder = [6, 2, 5, 1, 4, 0, 3]       // B E A D G C F

    static let keys: [(name: String, signature: Int)] = [
        ("C / Am", 0), ("G / Em", 1), ("D / Bm", 2), ("A / F♯m", 3), ("E / C♯m", 4), ("B / G♯m", 5), ("F♯ / D♯m", 6),
        ("F / Dm", -1), ("B♭ / Gm", -2), ("E♭ / Cm", -3), ("A♭ / Fm", -4), ("D♭ / B♭m", -5), ("G♭ / E♭m", -6),
    ]

    static let times: [(beats: Int, unit: Int)] = [(4, 4), (3, 4), (2, 4), (6, 8), (12, 8), (2, 2)]

    static func degree(_ step: Int) -> Int { ((step % 7) + 7) % 7 }
    static func octave(_ step: Int) -> Int { Int((Double(step) / 7).rounded(.down)) }

    static func keyAlteration(degree: Int, keySignature: Int) -> Int {
        if keySignature > 0 { return sharpOrder.prefix(keySignature).contains(degree) ? 1 : 0 }
        if keySignature < 0 { return flatOrder.prefix(-keySignature).contains(degree) ? -1 : 0 }
        return 0
    }

    static func midi(step: Int, accidental: Accidental, keySignature: Int) -> Int {
        let d = Self.degree(step)
        let natural = 60 + 12 * Self.octave(step) + degreeSemitones[d]
        switch accidental {
        case .sharp: return natural + 1
        case .flat: return natural - 1
        case .natural: return natural
        case .none: return natural + keyAlteration(degree: d, keySignature: keySignature)
        }
    }

    /// Writes a MIDI pitch as a staff step plus the accidental needed in this key.
    static func spell(midi: Int, keySignature: Int) -> (step: Int, accidental: Accidental) {
        let pc = ((midi % 12) + 12) % 12
        let octave = Int((Double(midi) / 12).rounded(.down)) - 1
        let flats = keySignature < 0
        let degrees = flats ? [0, 1, 1, 2, 2, 3, 4, 4, 5, 5, 6, 6] : [0, 0, 1, 1, 2, 3, 3, 4, 4, 5, 5, 6]
        let alters = flats ? [0, -1, 0, -1, 0, 0, -1, 0, -1, 0, -1, 0] : [0, 1, 0, 1, 0, 0, 1, 0, 1, 0, 1, 0]
        let degree = degrees[pc]
        let alter = alters[pc]
        let step = degree + 7 * (octave - 4)
        let inKey = keyAlteration(degree: degree, keySignature: keySignature)
        let accidental: Accidental
        if alter == inKey {
            accidental = .none
        } else if alter == 1 {
            accidental = .sharp
        } else if alter == -1 {
            accidental = .flat
        } else {
            accidental = .natural
        }
        return (step, accidental)
    }

    /// Open-string MIDI pitches for a tuning (lowest string near E2).
    static func openStrings(_ tuning: [String]) -> [Int] {
        var result: [Int] = []
        for name in tuning {
            guard let pc = NoteMath.pitchClass(name) else {
                result.append((result.last ?? 40) + 5)
                continue
            }
            if let previous = result.last {
                var midi = previous + ((pc - previous) % 12 + 12) % 12
                if midi == previous { midi += 12 }
                result.append(midi)
            } else {
                let offset = ((pc - 4) % 12 + 12) % 12
                result.append(40 + (offset > 6 ? offset - 12 : offset))
            }
        }
        return result
    }

    /// Picks a string and fret for every note (guitar sounds an octave below written pitch).
    static func tabPositions(for melody: Melody) -> [UUID: (string: Int, fret: Int)] {
        let open = openStrings(melody.tuning)
        var result: [UUID: (string: Int, fret: Int)] = [:]
        var anchor = 2
        for note in melody.notes where !note.isRest {
            let sounding = note.midi(keySignature: melody.keySignature) - 12
            if let chosen = note.string, open.indices.contains(chosen) {
                let fret = sounding - open[chosen]
                if (0...24).contains(fret) {
                    result[note.id] = (chosen, fret)
                    if fret > 0 { anchor = fret }
                    continue
                }
            }
            var best: (string: Int, fret: Int, cost: Double)?
            for (string, openMidi) in open.enumerated() {
                let fret = sounding - openMidi
                guard (0...20).contains(fret) else { continue }
                let cost = Double(abs(fret - anchor)) - (fret == 0 ? 0.6 : 0)
                if best == nil || cost < best!.cost {
                    best = (string, fret, cost)
                }
            }
            if let best {
                result[note.id] = (best.string, best.fret)
                if best.fret > 0 { anchor = best.fret }
            }
        }
        return result
    }
}
