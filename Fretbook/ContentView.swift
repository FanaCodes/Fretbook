import SwiftUI
import UniformTypeIdentifiers

enum SidebarItem: Hashable {
    case week
    case student(UUID)
    case chart(UUID)
    case song(UUID)
    case melody(UUID)
}

struct ContentView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.scenePhase) private var scenePhase

    @State private var selection: SidebarItem? = .week
    @State private var search = ""
    @State private var newStudent: Student?
    @State private var pendingDelete: Student?
    @State private var pendingChartDelete: ChordChart?
    @State private var confirmImport = false
    @State private var importing = false
    @State private var alertMessage: String?

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { store.save() }
        }
        .onAppear {
            if let error = store.loadError { alertMessage = error }
        }
        .sheet(item: $newStudent) { student in
            StudentEditor(student: student, isNew: true) { saved in
                store.add(saved)
                selection = .student(saved.id)
            }
        }
        .confirmationDialog(
            "Delete \(pendingDelete?.displayName ?? "student")?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { student in
            Button("Delete Student and All Lessons", role: .destructive) {
                deleteStudent(student.id)
            }
        } message: { _ in
            Text("This can't be undone.")
        }
        .confirmationDialog(
            "Delete \(pendingChartDelete?.title ?? "chart")?",
            isPresented: Binding(get: { pendingChartDelete != nil }, set: { if !$0 { pendingChartDelete = nil } }),
            titleVisibility: .visible,
            presenting: pendingChartDelete
        ) { chart in
            Button("Delete Chart", role: .destructive) {
                deleteChart(chart.id)
            }
        } message: { _ in
            Text("This can't be undone.")
        }
        .confirmationDialog("Import a backup?", isPresented: $confirmImport, titleVisibility: .visible) {
            Button("Choose Backup File…") { importing = true }
        } message: {
            Text("This replaces all students and lessons with the backup. A safety copy of your current data is kept in the Files app.")
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url):
                do {
                    try store.importBackup(from: url)
                    selection = .week
                } catch {
                    alertMessage = "That file couldn't be imported. \(error.localizedDescription)"
                }
            case .failure(let error):
                alertMessage = error.localizedDescription
            }
        }
        .alert(
            "Fretbook",
            isPresented: Binding(get: { alertMessage != nil }, set: { if !$0 { alertMessage = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage ?? "")
        }
    }

    // MARK: Sidebar

    private var filteredStudents: [Student] {
        let query = search.trimmingCharacters(in: .whitespaces)
        let all = store.sortedStudents
        return query.isEmpty ? all : all.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    private var sidebar: some View {
        List(selection: $selection) {
            NavigationLink(value: SidebarItem.week) {
                Label("This Week", systemImage: "calendar")
            }

            Section("Song Sheets") {
                ForEach(store.songs) { song in
                    NavigationLink(value: SidebarItem.song(song.id)) {
                        Label {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(song.title.isEmpty ? "Untitled" : song.title)
                                if !song.artist.isEmpty {
                                    Text(song.artist)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        } icon: {
                            Image(systemName: "music.note.list")
                        }
                    }
                    .contextMenu {
                        Button(role: .destructive) {
                            deleteSong(song.id)
                        } label: {
                            Label("Delete Song Sheet", systemImage: "trash")
                        }
                    }
                }
                Button {
                    selection = .song(store.addSong())
                } label: {
                    Label("New Song Sheet", systemImage: "plus")
                }
            }

            Section("Melodies") {
                ForEach(store.melodies) { melody in
                    NavigationLink(value: SidebarItem.melody(melody.id)) {
                        Label(melody.title.isEmpty ? "Untitled" : melody.title, systemImage: "music.quarternote.3")
                    }
                    .contextMenu {
                        Button(role: .destructive) {
                            deleteMelody(melody.id)
                        } label: {
                            Label("Delete Melody", systemImage: "trash")
                        }
                    }
                }
                Button {
                    selection = .melody(store.addMelody())
                } label: {
                    Label("New Melody", systemImage: "plus")
                }
            }

            Section("Chord Charts") {
                ForEach(store.charts) { chart in
                    NavigationLink(value: SidebarItem.chart(chart.id)) {
                        Label(chart.title.isEmpty ? "Chord Chart" : chart.title, systemImage: "square.grid.3x3")
                    }
                    .contextMenu {
                        Button(role: .destructive) {
                            pendingChartDelete = chart
                        } label: {
                            Label("Delete Chart", systemImage: "trash")
                        }
                    }
                }
                Button {
                    selection = .chart(store.addChart())
                } label: {
                    Label("New Chord Chart", systemImage: "plus")
                }
            }

            Section("Students") {
                ForEach(filteredStudents) { student in
                    NavigationLink(value: SidebarItem.student(student.id)) {
                        StudentRow(student: student)
                    }
                    .contextMenu {
                        Button(role: .destructive) {
                            pendingDelete = student
                        } label: {
                            Label("Delete Student", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .navigationTitle("Fretbook")
        .searchable(text: $search, prompt: "Search students")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    ShareLink(item: store.fileURL) {
                        Label("Export Backup", systemImage: "square.and.arrow.up")
                    }
                    Button {
                        confirmImport = true
                    } label: {
                        Label("Import Backup…", systemImage: "square.and.arrow.down")
                    }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    newStudent = Student(colorIndex: store.students.count)
                } label: {
                    Label("Add Student", systemImage: "person.badge.plus")
                }
            }
        }
    }

    // MARK: Detail

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .melody(let id)?:
            if let binding = store.melodyBinding(for: id) {
                MelodyPage(melody: binding, onDelete: { deleteMelody(id) })
                    .id(id)
            } else {
                ContentUnavailableView("Pick a melody", systemImage: "music.quarternote.3")
            }
        case .song(let id)?:
            if let binding = store.songBinding(for: id) {
                SongSheetPage(song: binding, onDelete: { deleteSong(id) })
                    .id(id)
            } else {
                ContentUnavailableView("Pick a song", systemImage: "music.note.list")
            }
        case .chart(let id)?:
            if let binding = store.chartBinding(for: id) {
                ChartPage(chart: binding, onDelete: { deleteChart(id) })
                    .id(id)
            } else {
                ContentUnavailableView("Pick a chart", systemImage: "square.grid.3x3")
            }
        case .student(let id)?:
            if let binding = store.binding(for: id) {
                StudentPage(student: binding, onDelete: { deleteStudent(id) }, onOpenChart: { selection = .chart($0) })
                    .id(id)
            } else {
                ContentUnavailableView("Pick a student", systemImage: "person.crop.circle")
            }
        default:
            WeekView(selection: $selection, onAddStudent: {
                newStudent = Student(colorIndex: store.students.count)
            })
        }
    }

    private func deleteMelody(_ id: UUID) {
        if selection == .melody(id) { selection = .week }
        store.deleteMelody(id)
    }

    private func deleteSong(_ id: UUID) {
        if selection == .song(id) { selection = .week }
        store.deleteSong(id)
    }

    private func deleteChart(_ id: UUID) {
        if selection == .chart(id) { selection = .week }
        store.deleteChart(id)
    }

    private func deleteStudent(_ id: UUID) {
        if selection == .student(id) { selection = .week }
        store.delete(id)
    }
}

// MARK: - Shared small views

struct StudentRow: View {
    let student: Student

    var body: some View {
        HStack(spacing: 12) {
            Avatar(student: student, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(student.displayName)
                    .font(.body.weight(.medium))
                if let slot = student.shortSlot {
                    Text(slot)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

struct Avatar: View {
    let student: Student
    var size: CGFloat = 40

    var body: some View {
        Circle()
            .fill(student.color.gradient)
            .frame(width: size, height: size)
            .overlay(
                Text(student.initials)
                    .font(.system(size: size * 0.4, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            )
    }
}

struct Chip: View {
    let text: String
    var systemImage: String? = nil
    var color: Color = .secondary

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
            }
            Text(text)
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .foregroundStyle(color)
        .background(color.opacity(0.12), in: Capsule())
    }
}

extension View {
    func card() -> some View {
        padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color(uiColor: .secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
    }
}
