import Foundation

// MARK: - Song sheet

/// A lyrics sheet with chords. The text uses ChordPro-style markers:
/// "[Am]Hello [G]world", lines starting with "#" are section titles.
struct SongSheet: Identifiable, Codable, Hashable {
    var id = UUID()
    var title = "New Song"
    var artist = ""
    var key = ""
    var capo = 0
    var tempo: Int? = nil
    var text = ""
    var showDiagrams = true
    var diagramsAtTop = true
    var fontSize: Double = 13           // printed size in points
    var customDiagrams: [FretDiagram] = []
    var created = Date()

    init(title: String = "New Song") {
        self.title = title
    }

    var rawLines: [String] { text.components(separatedBy: "\n") }
    var lineKinds: [SongLineKind] { rawLines.map(SongLineKind.init) }

    /// Every chord in order of first appearance.
    var uniqueChords: [String] {
        var seen = Set<String>()
        var result: [String] = []
        for kind in lineKinds {
            guard case .lyric(let line) = kind else { continue }
            for chord in line.chords.sorted(by: { $0.position < $1.position }) {
                if seen.insert(ChordNames.normalize(chord.name)).inserted {
                    result.append(chord.name)
                }
            }
        }
        return result
    }

    /// The diagram to show for a chord: a voicing picked by hand, otherwise the library's best guess.
    func diagram(for name: String) -> FretDiagram? {
        let key = ChordNames.normalize(name)
        if let custom = customDiagrams.first(where: { ChordNames.normalize($0.name) == key }) {
            return custom
        }
        return ChordLibrary.diagram(for: name)
    }

    var metaLine: String {
        var parts: [String] = []
        if !key.isEmpty { parts.append("Key: \(key)") }
        if capo > 0 { parts.append("Capo \(capo)") }
        if let tempo { parts.append("♩ = \(tempo)") }
        return parts.joined(separator: "   ·   ")
    }

    /// Moves every chord (and the key) up or down by semitones.
    mutating func transpose(by steps: Int) {
        let newKey = key.isEmpty ? "" : ChordNames.transpose(key, by: steps, flats: false)
        let flats = ChordNames.prefersFlats(key: newKey)
        let lines = rawLines.map { raw -> String in
            guard case .lyric = SongLineKind(raw) else { return raw }
            var line = ChordLine(parsing: raw)
            guard !line.chords.isEmpty else { return raw }
            for index in line.chords.indices {
                line.chords[index].name = ChordNames.transpose(line.chords[index].name, by: steps, flats: flats)
            }
            return line.serialized()
        }
        text = lines.joined(separator: "\n")
        if !key.isEmpty { key = ChordNames.transpose(key, by: steps, flats: flats) }
        customDiagrams = []
    }

    enum CodingKeys: String, CodingKey {
        case id, title, artist, key, capo, tempo, text, showDiagrams, diagramsAtTop, fontSize, customDiagrams, created
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? "Song"
        artist = try c.decodeIfPresent(String.self, forKey: .artist) ?? ""
        key = try c.decodeIfPresent(String.self, forKey: .key) ?? ""
        capo = try c.decodeIfPresent(Int.self, forKey: .capo) ?? 0
        tempo = try c.decodeIfPresent(Int.self, forKey: .tempo)
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        showDiagrams = try c.decodeIfPresent(Bool.self, forKey: .showDiagrams) ?? true
        diagramsAtTop = try c.decodeIfPresent(Bool.self, forKey: .diagramsAtTop) ?? true
        fontSize = try c.decodeIfPresent(Double.self, forKey: .fontSize) ?? 13
        customDiagrams = try c.decodeIfPresent([FretDiagram].self, forKey: .customDiagrams) ?? []
        created = try c.decodeIfPresent(Date.self, forKey: .created) ?? Date()
    }
}

// MARK: - Lines

struct PlacedChord: Hashable {
    var position: Int       // character offset in the lyric text
    var name: String
}

enum SongLineKind {
    case blank
    case section(String)
    case lyric(ChordLine)

    init(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            self = .blank
        } else if trimmed.hasPrefix("#") {
            self = .section(trimmed.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces))
        } else if trimmed.hasPrefix("{") && trimmed.hasSuffix("}") {
            // ChordPro directives such as {c: Chorus} or {comment: Verse 2}
            let inner = trimmed.dropFirst().dropLast()
            if let colon = inner.firstIndex(of: ":") {
                self = .section(inner[inner.index(after: colon)...].trimmingCharacters(in: .whitespaces))
            } else {
                self = .section(inner.trimmingCharacters(in: .whitespaces))
            }
        } else if trimmed.hasPrefix("["), trimmed.hasSuffix("]"), trimmed.filter({ $0 == "[" }).count == 1,
                  !ChordNames.isChord(String(trimmed.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)) {
            // "[Verse 1]" as used by most chord websites
            self = .section(String(trimmed.dropFirst().dropLast()))
        } else {
            self = .lyric(ChordLine(parsing: raw))
        }
    }
}

struct ChordLine {
    var plain: String
    var chords: [PlacedChord]

    init(plain: String, chords: [PlacedChord]) {
        self.plain = plain
        self.chords = chords
    }

    init(parsing line: String) {
        var plain = ""
        var count = 0
        var chords: [PlacedChord] = []
        var index = line.startIndex
        while index < line.endIndex {
            let character = line[index]
            if character == "[", let close = line[index...].firstIndex(of: "]") {
                let inner = line[line.index(after: index)..<close].trimmingCharacters(in: .whitespaces)
                if ChordNames.isChord(inner) {
                    chords.append(PlacedChord(position: count, name: inner))
                    index = line.index(after: close)
                    continue
                }
            }
            plain.append(character)
            count += 1
            index = line.index(after: index)
        }
        self.plain = plain
        self.chords = chords
    }

    func serialized() -> String {
        let characters = Array(plain)
        let ordered = chords.enumerated()
            .sorted { ($0.element.position, $0.offset) < ($1.element.position, $1.offset) }
            .map(\.element)
        var output = ""
        var next = 0
        for (offset, character) in characters.enumerated() {
            while next < ordered.count && ordered[next].position <= offset {
                output += "[\(ordered[next].name)]"
                next += 1
            }
            output.append(character)
        }
        // Chords after the last letter keep their spacing.
        var length = characters.count
        while next < ordered.count {
            let position = ordered[next].position
            if position > length {
                output += String(repeating: " ", count: position - length)
                length = position
            }
            output += "[\(ordered[next].name)]"
            next += 1
        }
        return output
    }

    /// Splits the line into words; chords inside a word split it into pieces.
    func words() -> [SongWord] {
        let characters = Array(plain)
        let count = characters.count

        // A chord sitting on a space belongs to the next word.
        var byPosition: [Int: [(index: Int, name: String)]] = [:]
        for (index, chord) in chords.enumerated() {
            var position = min(max(chord.position, 0), count)
            while position < count && characters[position].isWhitespace { position += 1 }
            byPosition[position, default: []].append((index, chord.name))
        }

        var words: [SongWord] = []
        var cursor = 0
        while cursor < count {
            while cursor < count && characters[cursor].isWhitespace { cursor += 1 }
            guard cursor < count else { break }
            let start = cursor
            while cursor < count && !characters[cursor].isWhitespace { cursor += 1 }
            let end = cursor

            let boundaries = [start] + byPosition.keys.filter { $0 > start && $0 < end }.sorted() + [end]
            var pieces: [SongPiece] = []
            for (k, boundary) in boundaries.dropLast().enumerated() {
                let text = String(characters[boundary..<boundaries[k + 1]])
                let here = byPosition[boundary] ?? []
                for extra in here.dropLast() {
                    pieces.append(SongPiece(id: pieces.count, position: boundary, chord: extra.name, chordIndex: extra.index, text: ""))
                }
                pieces.append(SongPiece(id: pieces.count, position: boundary, chord: here.last?.name, chordIndex: here.last?.index, text: text))
            }
            words.append(SongWord(id: start, pieces: pieces))
        }

        // Chords after the last word (e.g. instrumental lines "[C] [G] [Am]")
        for (k, chord) in (byPosition[count] ?? []).enumerated() {
            words.append(SongWord(id: count + 1 + k, pieces: [
                SongPiece(id: 0, position: count, chord: chord.name, chordIndex: chord.index, text: ""),
            ]))
        }
        return words
    }
}

struct SongWord: Identifiable {
    let id: Int             // start offset
    let pieces: [SongPiece]
}

struct SongPiece: Identifiable {
    let id: Int
    let position: Int
    let chord: String?
    let chordIndex: Int?
    let text: String
}

// MARK: - Chord names

enum ChordNames {
    private static let pattern = try? NSRegularExpression(
        pattern: "^[A-G](#|b|♯|♭)?(maj|min|dim|aug|sus|add|m|M|°|ø|Δ|\\+|-|#|b|♯|♭|\\(|\\)|[0-9])*(/[A-G](#|b|♯|♭)?)?$"
    )

    static func isChord(_ text: String) -> Bool {
        guard !text.isEmpty, let pattern else { return false }
        let range = NSRange(text.startIndex..., in: text)
        return pattern.firstMatch(in: text, range: range) != nil
    }

    /// "F♯m" → "F#m", "B♭" → "Bb"
    static func normalize(_ name: String) -> String {
        name.replacingOccurrences(of: "♯", with: "#").replacingOccurrences(of: "♭", with: "b")
    }

    static func split(_ name: String) -> (root: String, quality: String, bass: String?)? {
        let text = normalize(name)
        guard let first = text.first, "ABCDEFG".contains(first) else { return nil }
        var root = String(first)
        var index = text.index(after: text.startIndex)
        if index < text.endIndex, text[index] == "#" || text[index] == "b" {
            root.append(text[index])
            index = text.index(after: index)
        }
        var rest = String(text[index...])
        var bass: String?
        if let slash = rest.firstIndex(of: "/") {
            bass = String(rest[rest.index(after: slash)...])
            rest = String(rest[..<slash])
        }
        return (root, rest, bass)
    }

    static func spelled(_ pitchClass: Int, flats: Bool) -> String {
        normalize(NoteMath.name(pitchClass, flats: flats))
    }

    static func transpose(_ name: String, by steps: Int, flats: Bool) -> String {
        guard let parts = split(name), let root = NoteMath.pitchClass(parts.root) else { return name }
        var result = spelled(root + steps, flats: flats) + parts.quality
        if let bass = parts.bass {
            if let bassPC = NoteMath.pitchClass(bass) {
                result += "/" + spelled(bassPC + steps, flats: flats)
            } else {
                result += "/" + bass
            }
        }
        return result
    }

    /// Flat keys: F, B♭, E♭, A♭, D♭ and their relative minors.
    static func prefersFlats(key: String) -> Bool {
        guard let parts = split(key), let root = NoteMath.pitchClass(parts.root) else { return false }
        let isMinor = parts.quality.hasPrefix("m") && !parts.quality.hasPrefix("maj")
        let major = isMinor ? (root + 3) % 12 : root
        return [1, 3, 5, 8, 10].contains(major)
    }
}

// MARK: - Chords-over-lyrics import

enum ChordSheetImport {
    /// A line made only of chord names (and bar lines), as copied from chord websites.
    static func isChordRow(_ line: String) -> Bool {
        let tokens = line.split(whereSeparator: \.isWhitespace).map(String.init).filter { $0 != "|" }
        return !tokens.isEmpty && tokens.allSatisfy(ChordNames.isChord)
    }

    static func hasChordRows(_ text: String) -> Bool {
        text.components(separatedBy: "\n").contains(where: isChordRow)
    }

    /// Converts "chords on the line above" into inline [Chord] markers at the same columns.
    static func convert(_ text: String) -> String {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var output: [String] = []
        var index = 0
        while index < lines.count {
            let line = lines[index]
            guard isChordRow(line) else {
                output.append(line)
                index += 1
                continue
            }

            var placed: [PlacedChord] = []
            var column = 0
            var tokenStart: Int?
            var token = ""
            for character in line + " " {
                if character.isWhitespace {
                    if let start = tokenStart, token != "|" {
                        placed.append(PlacedChord(position: start, name: token))
                    }
                    tokenStart = nil
                    token = ""
                } else {
                    if tokenStart == nil { tokenStart = column }
                    token.append(character)
                }
                column += 1
            }

            let next = index + 1 < lines.count ? lines[index + 1] : nil
            if let next, !next.trimmingCharacters(in: .whitespaces).isEmpty, !isChordRow(next),
               case .lyric = SongLineKind(next) {
                output.append(ChordLine(plain: next, chords: placed).serialized())
                index += 2
            } else {
                output.append(ChordLine(plain: "", chords: placed).serialized())
                index += 1
            }
        }
        return output.joined(separator: "\n")
    }
}
