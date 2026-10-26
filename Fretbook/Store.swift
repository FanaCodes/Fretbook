import SwiftUI

/// Keeps every student in memory and mirrors them to a JSON file in the app's
/// Documents folder (visible in the Files app under On My iPad → Fretbook).
final class Store: ObservableObject {
    @Published var students: [Student] = [] {
        didSet { scheduleSave() }
    }

    @Published var charts: [ChordChart] = [] {
        didSet { scheduleSave() }
    }

    /// Set when the data file exists but couldn't be read.
    @Published var loadError: String?

    let fileURL: URL
    private var pendingSave: DispatchWorkItem?

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = docs.appendingPathComponent("Fretbook.json")

        if FileManager.default.fileExists(atPath: fileURL.path) {
            load()
        } else {
            students = [Sample.student]
            save()
        }
    }

    // MARK: Loading & saving

    private func load() {
        do {
            let library = try Self.decode(Data(contentsOf: fileURL))
            students = library.students
            charts = library.charts
        } catch {
            // Never overwrite a file we couldn't read: keep a copy aside first.
            let copy = fileURL.deletingLastPathComponent()
                .appendingPathComponent("Fretbook-unreadable-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.copyItem(at: fileURL, to: copy)
            loadError = "Your data file couldn't be read. A copy was kept as \(copy.lastPathComponent) in the Files app."
        }
    }

    private func scheduleSave() {
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.save() }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    func save() {
        pendingSave?.cancel()
        pendingSave = nil
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(Library(students: students, charts: charts))
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("Save failed: \(error)")
        }
    }

    private static func decode(_ data: Data) throws -> Library {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let library = try? decoder.decode(Library.self, from: data) {
            return library
        }
        return Library(students: try decoder.decode([Student].self, from: data), charts: [])
    }

    /// Replaces all data with a backup file. The current data is copied aside first.
    func importBackup(from url: URL) throws {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }

        let imported = try Self.decode(Data(contentsOf: url))
        let safety = fileURL.deletingLastPathComponent()
            .appendingPathComponent("Fretbook-before-import-\(Int(Date().timeIntervalSince1970)).json")
        try? FileManager.default.copyItem(at: fileURL, to: safety)
        students = imported.students
        charts = imported.charts
        save()
    }

    // MARK: Students

    var sortedStudents: [Student] {
        students.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func add(_ student: Student) {
        students.append(student)
    }

    func delete(_ id: UUID) {
        students.removeAll { $0.id == id }
    }

    // MARK: Chord charts

    func addChart() -> UUID {
        let chart = ChordChart(title: "Chord Chart \(charts.count + 1)")
        charts.append(chart)
        return chart.id
    }

    func deleteChart(_ id: UUID) {
        charts.removeAll { $0.id == id }
    }

    func chartBinding(for id: UUID) -> Binding<ChordChart>? {
        guard charts.contains(where: { $0.id == id }) else { return nil }
        return Binding(
            get: { self.charts.first(where: { $0.id == id }) ?? ChordChart() },
            set: { newValue in
                if let i = self.charts.firstIndex(where: { $0.id == id }) {
                    self.charts[i] = newValue
                }
            }
        )
    }

    func binding(for id: UUID) -> Binding<Student>? {
        guard students.contains(where: { $0.id == id }) else { return nil }
        return Binding(
            get: { self.students.first(where: { $0.id == id }) ?? Student() },
            set: { newValue in
                if let i = self.students.firstIndex(where: { $0.id == id }) {
                    self.students[i] = newValue
                }
            }
        )
    }
}

// MARK: - First-launch example

enum Sample {
    static var student: Student {
        var s = Student(name: "Sample Student", colorIndex: 2)
        s.level = "Beginner"
        s.goals = "Wants to play campfire songs with friends. (This is an example – delete it whenever you like.)"
        s.weekday = 3
        s.startMinutes = 16 * 60 + 30

        var lesson = Lesson(date: Date())
        lesson.summary = "First open chords and a simple strumming pattern."

        var am = NoteItem(category: .chord)
        am.title = "Am"
        am.frets = "x02210"

        var c = NoteItem(category: .chord)
        c.title = "C"
        c.frets = "x32010"

        var g = NoteItem(category: .chord)
        g.title = "G"
        g.frets = "320003"

        var strum = NoteItem(category: .rhythm)
        strum.title = "Folk strum"
        strum.strum = "D-DU-UDU"
        strum.bpm = 70

        var riff = NoteItem(category: .tab)
        riff.title = "Am arpeggio"
        riff.tab = """
        e|-------0-------|
        B|-----1---1-----|
        G|---2-------2---|
        D|-2-----------2-|
        A|0--------------|
        E|---------------|
        """

        var homework = NoteItem(category: .homework)
        homework.title = "Am ↔ C one-minute changes"
        homework.body = "Count the changes in one minute. Goal: 30."

        lesson.items = [am, c, g, strum, riff, homework]
        s.lessons = [lesson]
        return s
    }
}
