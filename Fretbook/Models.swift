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

    init(name: String = "", colorIndex: Int = 0) {
        self.name = name
        self.colorIndex = colorIndex
    }

    enum CodingKeys: String, CodingKey {
        case id, name, level, goals, contact, weekday, startMinutes, duration, colorIndex, lessons
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
    var version = 1
    var students: [Student]
}
