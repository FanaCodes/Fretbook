import SwiftUI

// MARK: - Note categories

enum NoteCategory: String, Codable, CaseIterable, Identifiable {
    case chord, scale, song, technique, rhythm, tab, theory, homework, note

    var id: String { rawValue }

    // Unknown values (from a newer app version) fall back to a plain note.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = NoteCategory(rawValue: raw) ?? .note
    }

    var label: String {
        switch self {
        case .chord: return "Chord"
        case .scale: return "Scale"
        case .song: return "Song"
        case .technique: return "Technique"
        case .rhythm: return "Rhythm"
        case .tab: return "Riff / Tab"
        case .theory: return "Theory"
        case .homework: return "Homework"
        case .note: return "Note"
        }
    }

    var symbol: String {
        switch self {
        case .chord: return "square.grid.3x3"
        case .scale: return "music.quarternote.3"
        case .song: return "music.note.list"
        case .technique: return "hand.raised.fill"
        case .rhythm: return "metronome.fill"
        case .tab: return "guitars.fill"
        case .theory: return "lightbulb.fill"
        case .homework: return "checklist"
        case .note: return "text.alignleft"
        }
    }

    var color: Color {
        switch self {
        case .chord: return .blue
        case .scale: return .teal
        case .song: return .pink
        case .technique: return .orange
        case .rhythm: return .purple
        case .tab: return .brown
        case .theory: return .indigo
        case .homework: return .red
        case .note: return .gray
        }
    }

    var titlePrompt: String {
        switch self {
        case .chord: return "Chord name, e.g. Am7"
        case .scale: return "e.g. A minor pentatonic, box 1"
        case .song: return "Song – Artist"
        case .technique: return "e.g. Alternate picking"
        case .rhythm: return "e.g. Folk strum"
        case .tab: return "Riff name"
        case .theory: return "Topic, e.g. Major scale formula"
        case .homework: return "What to practice"
        case .note: return "Title"
        }
    }

    // Which music fields the editor offers for this category.
    var showsFrets: Bool { self == .chord }
    var showsStrum: Bool { self == .song || self == .rhythm }
    var showsTab: Bool { [.scale, .song, .technique, .tab].contains(self) }
    var showsKey: Bool { [.scale, .song, .theory].contains(self) }
    var showsBPM: Bool { [.scale, .song, .technique, .rhythm, .tab, .homework].contains(self) }
}

// MARK: - Note item

struct NoteItem: Identifiable, Codable, Hashable {
    var id = UUID()
    var category: NoteCategory
    var title = ""
    var body = ""
    var frets = ""      // chord shape, low E → high e, e.g. "x32010"
    var tab = ""        // free-form ASCII tab
    var strum = ""      // e.g. "D-DU-UDU"
    var bpm: Int? = nil
    var key = ""
    var done = false    // homework only

    init(category: NoteCategory) {
        self.category = category
    }

    var isEmpty: Bool {
        [title, body, frets, tab, strum, key].allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } && bpm == nil
    }

    enum CodingKeys: String, CodingKey {
        case id, category, title, body, frets, tab, strum, bpm, key, done
    }

    // Tolerant decoding so data from older/newer versions still loads.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        category = try c.decodeIfPresent(NoteCategory.self, forKey: .category) ?? .note
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        body = try c.decodeIfPresent(String.self, forKey: .body) ?? ""
        frets = try c.decodeIfPresent(String.self, forKey: .frets) ?? ""
        tab = try c.decodeIfPresent(String.self, forKey: .tab) ?? ""
        strum = try c.decodeIfPresent(String.self, forKey: .strum) ?? ""
        bpm = try c.decodeIfPresent(Int.self, forKey: .bpm)
        key = try c.decodeIfPresent(String.self, forKey: .key) ?? ""
        done = try c.decodeIfPresent(Bool.self, forKey: .done) ?? false
    }
}

// MARK: - Lesson

struct Lesson: Identifiable, Codable, Hashable {
    var id = UUID()
    var date = Date()
    var summary = ""
    var items: [NoteItem] = []

    init(date: Date = Date()) {
        self.date = date
    }

    enum CodingKeys: String, CodingKey {
        case id, date, summary, items
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        date = try c.decodeIfPresent(Date.self, forKey: .date) ?? Date()
        summary = try c.decodeIfPresent(String.self, forKey: .summary) ?? ""
        items = try c.decodeIfPresent([NoteItem].self, forKey: .items) ?? []
    }
}

// MARK: - Student

struct Student: Identifiable, Codable, Hashable {
    var id = UUID()
    var name = ""
    var level = ""
    var goals = ""
    var contact = ""
    var weekday: Int? = nil         // Calendar weekday: 1 = Sunday … 7 = Saturday
    var startMinutes = 16 * 60      // minutes after midnight
    var duration = 30
    var colorIndex = 0
    var lessons: [Lesson] = []
    var repertoire: [RepertoireSong] = []

    init(name: String = "", colorIndex: Int = 0) {
        self.name = name
        self.colorIndex = colorIndex
    }

    enum CodingKeys: String, CodingKey {
        case id, name, level, goals, contact, weekday, startMinutes, duration, colorIndex, lessons, repertoire
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        level = try c.decodeIfPresent(String.self, forKey: .level) ?? ""
        goals = try c.decodeIfPresent(String.self, forKey: .goals) ?? ""
        contact = try c.decodeIfPresent(String.self, forKey: .contact) ?? ""
        weekday = try c.decodeIfPresent(Int.self, forKey: .weekday)
        startMinutes = try c.decodeIfPresent(Int.self, forKey: .startMinutes) ?? 16 * 60
        duration = try c.decodeIfPresent(Int.self, forKey: .duration) ?? 30
        colorIndex = try c.decodeIfPresent(Int.self, forKey: .colorIndex) ?? 0
        lessons = try c.decodeIfPresent([Lesson].self, forKey: .lessons) ?? []
        repertoire = try c.decodeIfPresent([RepertoireSong].self, forKey: .repertoire) ?? []
    }

    var displayName: String { name.isEmpty ? "Unnamed" : name }

    var initials: String {
        let letters = name.split(separator: " ").prefix(2).compactMap { $0.first }
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }

    var color: Color { Palette.student[abs(colorIndex) % Palette.student.count] }

    var allItems: [NoteItem] { lessons.flatMap { $0.items } }

    var openHomework: [NoteItem] {
        lessons.sorted { $0.date > $1.date }
            .flatMap { $0.items }
            .filter { $0.category == .homework && !$0.done }
    }

    var lastLessonDate: Date? { lessons.map(\.date).max() }

    private var validWeekday: Int? {
        guard let weekday, (1...7).contains(weekday) else { return nil }
        return weekday
    }

    var shortSlot: String? {
        guard let day = validWeekday else { return nil }
        return "\(Calendar.current.shortWeekdaySymbols[day - 1]) \(TimeFormat.string(minutes: startMinutes))"
    }

    var slotDescription: String? {
        guard let day = validWeekday else { return nil }
        return "\(Calendar.current.weekdaySymbols[day - 1])s · \(TimeFormat.string(minutes: startMinutes)) · \(duration) min"
    }

    // MARK: Item helpers (used where we only know the item's id)

    mutating func updateItem(_ item: NoteItem) {
        for l in lessons.indices {
            if let i = lessons[l].items.firstIndex(where: { $0.id == item.id }) {
                lessons[l].items[i] = item
                return
            }
        }
    }

    mutating func deleteItem(_ id: UUID) {
        for l in lessons.indices {
            lessons[l].items.removeAll { $0.id == id }
        }
    }

    mutating func toggleDone(_ id: UUID) {
        for l in lessons.indices {
            if let i = lessons[l].items.firstIndex(where: { $0.id == id }) {
                lessons[l].items[i].done.toggle()
                return
            }
        }
    }
}

// MARK: - Helpers

enum Palette {
    static let student: [Color] = [.blue, .orange, .green, .pink, .purple, .teal, .red, .indigo]
}

enum TimeFormat {
    static func date(minutes: Int, on day: Date = Date()) -> Date {
        Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: day) ?? day
    }

    static func string(minutes: Int) -> String {
        date(minutes: minutes).formatted(date: .omitted, time: .shortened)
    }
}

struct Library: Codable {
    var version = 3
    var students: [Student]
    var charts: [ChordChart]
    var songs: [SongSheet] = []

    init(students: [Student], charts: [ChordChart], songs: [SongSheet] = []) {
        self.students = students
        self.charts = charts
        self.songs = songs
    }

    enum CodingKeys: String, CodingKey { case version, students, charts, songs }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        students = try c.decode([Student].self, forKey: .students)
        charts = try c.decodeIfPresent([ChordChart].self, forKey: .charts) ?? []
        songs = try c.decodeIfPresent([SongSheet].self, forKey: .songs) ?? []
    }
}

// MARK: - Repertoire

enum SongStatus: String, Codable, CaseIterable, Identifiable {
    case wishlist, learning, canPlay, ready

    var id: String { rawValue }

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = SongStatus(rawValue: raw) ?? .learning
    }

    var label: String {
        switch self {
        case .wishlist: return "Wishlist"
        case .learning: return "Learning"
        case .canPlay: return "Can play"
        case .ready: return "Performance-ready"
        }
    }

    var symbol: String {
        switch self {
        case .wishlist: return "star"
        case .learning: return "hammer.fill"
        case .canPlay: return "checkmark.circle.fill"
        case .ready: return "star.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .wishlist: return .gray
        case .learning: return .orange
        case .canPlay: return .blue
        case .ready: return .green
        }
    }

    /// Order used on screen: what they're working on first.
    static let displayOrder: [SongStatus] = [.learning, .canPlay, .ready, .wishlist]
}

struct SongStatusChange: Codable, Hashable {
    var status: SongStatus
    var date: Date
}

struct RepertoireSong: Identifiable, Codable, Hashable {
    var id = UUID()
    var title = ""
    var artist = ""
    var status: SongStatus = .learning
    var notes = ""
    var added = Date()
    var history: [SongStatusChange] = []

    init(title: String = "", artist: String = "", status: SongStatus = .learning) {
        self.title = title
        self.artist = artist
        self.status = status
        self.history = [SongStatusChange(status: status, date: Date())]
    }

    mutating func setStatus(_ newStatus: SongStatus, on date: Date = Date()) {
        guard newStatus != status else { return }
        status = newStatus
        history.append(SongStatusChange(status: newStatus, date: date))
    }

    /// When the song reached its current status.
    var statusDate: Date { history.last(where: { $0.status == status })?.date ?? added }

    enum CodingKeys: String, CodingKey { case id, title, artist, status, notes, added, history }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        artist = try c.decodeIfPresent(String.self, forKey: .artist) ?? ""
        status = try c.decodeIfPresent(SongStatus.self, forKey: .status) ?? .learning
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        added = try c.decodeIfPresent(Date.self, forKey: .added) ?? Date()
        history = try c.decodeIfPresent([SongStatusChange].self, forKey: .history) ?? []
    }
}

// MARK: - Progress

struct LearnedChord: Identifiable {
    let name: String
    let frets: String
    let date: Date
    var id: String { name + frets }
}

struct TempoPoint: Identifiable {
    let date: Date
    let bpm: Int
    var id: Date { date }
}

struct TempoSeries: Identifiable {
    let title: String
    let category: NoteCategory
    let points: [TempoPoint]
    var id: String { title.lowercased() }
    var first: Int { points.first?.bpm ?? 0 }
    var latest: Int { points.last?.bpm ?? 0 }
    var gain: Int { latest - first }
}

struct ProgressEvent: Identifiable {
    let id = UUID()
    let date: Date
    let symbol: String
    let color: Color
    let text: String
}

extension Student {
    var sortedLessonsAscending: [Lesson] { lessons.sorted { $0.date < $1.date } }

    /// Every chord from lesson notes, first time it appeared, oldest first.
    var learnedChords: [LearnedChord] {
        var seen = Set<String>()
        var result: [LearnedChord] = []
        for lesson in sortedLessonsAscending {
            for item in lesson.items where item.category == .chord {
                let name = item.title.trimmingCharacters(in: .whitespaces)
                let key = name.isEmpty ? item.frets : name.lowercased()
                guard !key.isEmpty, seen.insert(key).inserted else { continue }
                result.append(LearnedChord(name: name.isEmpty ? item.frets : name, frets: item.frets, date: lesson.date))
            }
        }
        return result
    }

    /// Exercises/songs whose tempo was noted, grouped by title, oldest point first.
    var tempoSeries: [TempoSeries] {
        var groups: [String: (title: String, category: NoteCategory, points: [TempoPoint])] = [:]
        for lesson in sortedLessonsAscending {
            for item in lesson.items {
                guard let bpm = item.bpm else { continue }
                let title = item.title.trimmingCharacters(in: .whitespaces)
                guard !title.isEmpty else { continue }
                let key = title.lowercased()
                var entry = groups[key] ?? (title, item.category, [])
                entry.points.append(TempoPoint(date: lesson.date, bpm: bpm))
                groups[key] = entry
            }
        }
        return groups.values
            .map { TempoSeries(title: $0.title, category: $0.category, points: $0.points) }
            .sorted { a, b in
                // Exercises with an actual trend first, then most recently practised.
                let aTrend = a.points.count > 1
                let bTrend = b.points.count > 1
                if aTrend != bTrend { return aTrend }
                return (a.points.last?.date ?? .distantPast) > (b.points.last?.date ?? .distantPast)
            }
    }

    /// Song titles from lesson notes that aren't in the repertoire yet.
    var songSuggestions: [String] {
        let known = Set(repertoire.map { $0.title.lowercased() })
        var seen = Set<String>()
        var result: [String] = []
        for lesson in lessons.sorted(by: { $0.date > $1.date }) {
            for item in lesson.items where item.category == .song {
                let title = item.title.trimmingCharacters(in: .whitespaces)
                let key = title.lowercased()
                guard !title.isEmpty, !known.contains(key), seen.insert(key).inserted else { continue }
                result.append(title)
            }
        }
        return result
    }

    /// Milestones for the timeline, newest first.
    var progressEvents: [ProgressEvent] {
        var events: [ProgressEvent] = []
        let lessonsAscending = sortedLessonsAscending
        if let first = lessonsAscending.first {
            events.append(ProgressEvent(date: first.date, symbol: "flag.fill", color: .accentColor, text: "First lesson"))
        }
        for (index, lesson) in lessonsAscending.enumerated() where (index + 1) % 10 == 0 {
            events.append(ProgressEvent(date: lesson.date, symbol: "\(min(index + 1, 50)).circle.fill", color: .accentColor, text: "\(index + 1) lessons"))
        }
        for chord in learnedChords {
            events.append(ProgressEvent(date: chord.date, symbol: NoteCategory.chord.symbol, color: NoteCategory.chord.color, text: "Learned \(chord.name)"))
        }
        for song in repertoire {
            for change in song.history where change.status != .wishlist {
                let verb: String
                switch change.status {
                case .learning: verb = "Started learning"
                case .canPlay: verb = "Can play"
                case .ready: verb = "Performance-ready:"
                case .wishlist: verb = ""
                }
                events.append(ProgressEvent(date: change.date, symbol: change.status.symbol, color: change.status.color, text: "\(verb) \(song.title)"))
            }
        }
        for series in tempoSeries where series.points.count > 1 && series.gain > 0 {
            if let last = series.points.last {
                events.append(ProgressEvent(date: last.date, symbol: "metronome.fill", color: .purple, text: "\(series.title): \(series.first) → \(series.latest) BPM"))
            }
        }
        return events.sorted { $0.date > $1.date }
    }
}
