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
    /// Tied to the following note (same pitch, lengths add up).
    var tie = false
    /// Part of a triplet (plays 2/3 of its written length).
    var triplet = false
    /// Keeps singing the previous syllable instead of taking a new one.
    var holdsSyllable = false

    init(step: Int = 4, value: NoteValue = .quarter, isRest: Bool = false) {
        self.step = step
        self.value = value
        self.isRest = isRest
    }

    var quarters: Double { value.quarters * (dotted ? 1.5 : 1) * (triplet ? 2.0 / 3.0 : 1) }

    func midi(keySignature: Int) -> Int {
        MusicTheory.midi(step: step, accidental: accidental, keySignature: keySignature)
    }

    enum CodingKeys: String, CodingKey {
        case id, step, accidental, value, dotted, isRest, lyric, chord, string, tie, triplet, holdsSyllable
    }

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
        tie = try c.decodeIfPresent(Bool.self, forKey: .tie) ?? false
        triplet = try c.decodeIfPresent(Bool.self, forKey: .triplet) ?? false
        holdsSyllable = try c.decodeIfPresent(Bool.self, forKey: .holdsSyllable) ?? false
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
    /// Lyrics with syllables split by hyphens ("hap-py birth-day"); sung one syllable per note.
    var lyrics = ""
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

    var hasLyrics: Bool {
        !lyrics.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || notes.contains { !$0.lyric.isEmpty }
    }
    var hasChords: Bool { notes.contains { !$0.chord.isEmpty } }

    enum CodingKeys: String, CodingKey {
        case id, title, subtitle, keySignature, beatsPerBar, beatUnit, tempo, display, tuning, notes, lyrics, created
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
        lyrics = try c.decodeIfPresent(String.self, forKey: .lyrics) ?? ""
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
        let pitches = melody.pitches
        for note in melody.notes where !note.isRest {
            guard let written = pitches[note.id] else { continue }
            let sounding = written - 12
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

// MARK: - Lyrics & pitch context

struct Syllable: Hashable {
    let text: String
    /// A hyphen follows (the word continues on the next syllable).
    let continues: Bool
}

extension Melody {
    var syllables: [Syllable] {
        var result: [Syllable] = []
        for word in lyrics.split(whereSeparator: { $0.isWhitespace }) {
            let parts = word.split(separator: "-", omittingEmptySubsequences: true).map(String.init)
            for (index, part) in parts.enumerated() {
                result.append(Syllable(text: part, continues: index < parts.count - 1))
            }
        }
        return result
    }

    /// The syllable each note sings, and how many syllables are used so far.
    /// Rests, notes tied from the previous note and "hold" notes don't take a new syllable.
    var lyricAssignment: (map: [UUID: Syllable], used: Int, total: Int) {
        guard !lyrics.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            var manual: [UUID: Syllable] = [:]
            for note in notes where !note.lyric.isEmpty {
                manual[note.id] = Syllable(text: note.lyric, continues: false)
            }
            return (manual, 0, 0)
        }
        let all = syllables
        var map: [UUID: Syllable] = [:]
        var next = 0
        var previousTied = false
        for note in notes {
            defer { previousTied = note.tie && !note.isRest }
            if note.isRest || previousTied || note.holdsSyllable { continue }
            guard next < all.count else { continue }
            map[note.id] = all[next]
            next += 1
        }
        return (map, next, all.count)
    }

    /// Sounding (written) MIDI pitch of every note. Accidentals last until the end of the bar,
    /// and a tied note keeps the pitch of the note it's tied from.
    var pitches: [UUID: Int] {
        var result: [UUID: Int] = [:]
        var position = 0.0
        var carried: [Int: Accidental] = [:]
        var previous: MelodyNote?
        var previousPitch: Int?
        for note in notes {
            if note.isRest {
                previousPitch = nil
            } else {
                var accidental = note.accidental
                if accidental == .none, let barAccidental = carried[note.step] {
                    accidental = barAccidental
                }
                if note.accidental != .none {
                    carried[note.step] = note.accidental
                }
                var pitch = MusicTheory.midi(step: note.step, accidental: accidental, keySignature: keySignature)
                if let previous, previous.tie, previous.step == note.step, note.accidental == .none, let previousPitch {
                    pitch = previousPitch
                }
                result[note.id] = pitch
                previousPitch = pitch
            }
            previous = note
            position += note.quarters
            if position >= barQuarters - 0.0001 {
                position = 0
                carried = [:]
            }
        }
        return result
    }

    /// Accidentals already written earlier in the bar where a note at `index` would go.
    func barAccidentals(before index: Int) -> [Int: Accidental] {
        var position = 0.0
        var carried: [Int: Accidental] = [:]
        for note in notes.prefix(max(0, index)) {
            if !note.isRest && note.accidental != .none {
                carried[note.step] = note.accidental
            }
            position += note.quarters
            if position >= barQuarters - 0.0001 {
                position = 0
                carried = [:]
            }
        }
        return carried
    }

    /// Spells a MIDI pitch for insertion at `index`, adding a ♮/♯/♭ when an earlier
    /// accidental in the bar would otherwise change it.
    func spell(midi: Int, at index: Int) -> (step: Int, accidental: Accidental) {
        let spelled = MusicTheory.spell(midi: midi, keySignature: keySignature)
        let carried = barAccidentals(before: index)[spelled.step]
        let effective = spelled.accidental == .none ? (carried ?? .none) : spelled.accidental
        if MusicTheory.midi(step: spelled.step, accidental: effective, keySignature: keySignature) == midi {
            return spelled
        }
        let natural = MusicTheory.midi(step: spelled.step, accidental: .natural, keySignature: keySignature)
        switch midi - natural {
        case 1: return (spelled.step, .sharp)
        case -1: return (spelled.step, .flat)
        default: return (spelled.step, .natural)
        }
    }

    /// Bar number (0-based) of every note.
    var barNumbers: [Int] {
        var result: [Int] = []
        var bar = 0
        var position = 0.0
        for note in notes {
            result.append(bar)
            position += note.quarters
            if position >= barQuarters - 0.0001 {
                position = 0
                bar += 1
            }
        }
        return result
    }
}

extension MusicTheory {
    /// "G♯4"
    static func noteName(midi: Int, keySignature: Int) -> String {
        NoteMath.name(midi, flats: keySignature < 0) + "\(Int((Double(midi) / 12).rounded(.down)) - 1)"
    }

    /// Rough syllable split for sung lyrics: "happy birthday" → "hap-py birth-day".
    static func hyphenate(_ text: String) -> String {
        text.components(separatedBy: "\n").map { line in
            line.components(separatedBy: " ").map(hyphenateWord).joined(separator: " ")
        }
        .joined(separator: "\n")
    }

    private static func hyphenateWord(_ word: String) -> String {
        guard word.count > 3, !word.contains("-") else { return word }
        let letters = Array(word)
        let vowels = Set("aeiouyäöüAEIOUYÄÖÜ")
        func isVowel(_ i: Int) -> Bool {
            guard vowels.contains(letters[i]) else { return false }
            // A final silent "e" (love, time) doesn't make a syllable.
            if i == letters.count - 1, letters[i] == "e", i > 0, !vowels.contains(letters[i - 1]) { return false }
            return true
        }

        // Vowel groups
        var groups: [(start: Int, end: Int)] = []
        var i = 0
        while i < letters.count {
            if letters[i].isLetter && isVowel(i) {
                let start = i
                while i < letters.count && letters[i].isLetter && isVowel(i) { i += 1 }
                groups.append((start, i))
            } else {
                i += 1
            }
        }
        guard groups.count > 1 else { return word }

        var cuts: [Int] = []
        for k in 0..<(groups.count - 1) {
            let consonantStart = groups[k].end
            let consonantEnd = groups[k + 1].start
            guard consonantEnd > consonantStart,
                  letters[consonantStart..<consonantEnd].allSatisfy({ $0.isLetter }) else { continue }
            // Consonant sounds, keeping th/ch/sh/ph/wh/gh/sch together.
            var units: [Int] = []
            var j = consonantStart
            while j < consonantEnd {
                units.append(j)
                let rest = String(letters[j..<consonantEnd]).lowercased()
                if let pair = ["sch", "ch", "sh", "th", "ph", "wh", "gh"].first(where: { rest.hasPrefix($0) }) {
                    j += pair.count
                } else {
                    j += 1
                }
            }
            // One sound goes to the next syllable; with more, only the last one does.
            cuts.append(units.count == 1 ? units[0] : units[units.count - 1])
        }
        var result = ""
        for (index, letter) in letters.enumerated() {
            if cuts.contains(index) && index > 0 && index < letters.count - 1 { result.append("-") }
            result.append(letter)
        }
        return result
    }
}
