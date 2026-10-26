import SwiftUI

struct SongTarget: Identifiable {
    var song: RepertoireSong
    var isNew: Bool
    var id: UUID { song.id }
}

/// A student's song list, grouped by how far along they are.
struct RepertoireView: View {
    @Binding var student: Student
    @State private var editing: SongTarget?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                SectionTitle(title: "Repertoire", systemImage: "music.note.list", color: NoteCategory.song.color)
                Spacer()
                Button {
                    editing = SongTarget(song: RepertoireSong(), isNew: true)
                } label: {
                    Label("Add Song", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }

            if !student.songSuggestions.isEmpty {
                suggestions
            }

            if student.repertoire.isEmpty {
                Text("No songs yet. Add the songs \(student.displayName) is working on, wants to learn, or can already play – and move them along as they progress.")
                    .foregroundStyle(.secondary)
                    .card()
            }

            ForEach(SongStatus.displayOrder) { status in
                let songs = student.repertoire
                    .filter { $0.status == status }
                    .sorted { $0.statusDate > $1.statusDate }
                if !songs.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("\(status.label) · \(songs.count)", systemImage: status.symbol)
                            .font(.headline)
                            .foregroundStyle(status.color)
                        VStack(spacing: 0) {
                            ForEach(songs) { song in
                                SongRow(song: song) { newStatus in
                                    setStatus(song.id, newStatus)
                                }
                                .contentShape(Rectangle())
                                .onTapGesture { editing = SongTarget(song: song, isNew: false) }
                                if song.id != songs.last?.id {
                                    Divider()
                                }
                            }
                        }
                        .card()
                    }
                }
            }
        }
        .sheet(item: $editing) { target in
            SongEditor(
                song: target.song,
                isNew: target.isNew,
                onSave: save,
                onDelete: target.isNew ? nil : { delete(target.song.id) }
            )
        }
    }

    private var suggestions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("From your lesson notes")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(student.songSuggestions, id: \.self) { title in
                        Button {
                            withAnimation { student.repertoire.append(RepertoireSong(title: title)) }
                        } label: {
                            Label(title, systemImage: "plus")
                                .font(.subheadline)
                        }
                        .buttonStyle(.bordered)
                        .tint(NoteCategory.song.color)
                    }
                }
            }
        }
    }

    private func setStatus(_ id: UUID, _ status: SongStatus) {
        guard let index = student.repertoire.firstIndex(where: { $0.id == id }) else { return }
        withAnimation { student.repertoire[index].setStatus(status) }
    }

    private func save(_ song: RepertoireSong) {
        if let index = student.repertoire.firstIndex(where: { $0.id == song.id }) {
            student.repertoire[index] = song
        } else {
            student.repertoire.append(song)
        }
    }

    private func delete(_ id: UUID) {
        student.repertoire.removeAll { $0.id == id }
    }
}

struct SongRow: View {
    let song: RepertoireSong
    let onStatus: (SongStatus) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: song.status.symbol)
                .font(.title3)
                .foregroundStyle(song.status.color)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(song.title.isEmpty ? "Untitled" : song.title)
                    .font(.body.weight(.medium))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                ForEach(SongStatus.allCases) { status in
                    Button {
                        onStatus(status)
                    } label: {
                        Label(status.label, systemImage: status.symbol)
                    }
                    .disabled(status == song.status)
                }
            } label: {
                Chip(text: song.status.label, color: song.status.color)
            }
        }
        .padding(.vertical, 10)
    }

    private var subtitle: String {
        var parts: [String] = []
        if !song.artist.isEmpty { parts.append(song.artist) }
        parts.append("since \(song.statusDate.formatted(date: .abbreviated, time: .omitted))")
        return parts.joined(separator: " · ")
    }
}

struct SongEditor: View {
    @Environment(\.dismiss) private var dismiss

    @State private var draft: RepertoireSong
    @State private var status: SongStatus
    @State private var confirmDelete = false

    let isNew: Bool
    let onSave: (RepertoireSong) -> Void
    let onDelete: (() -> Void)?

    init(song: RepertoireSong, isNew: Bool, onSave: @escaping (RepertoireSong) -> Void, onDelete: (() -> Void)? = nil) {
        _draft = State(initialValue: song)
        _status = State(initialValue: song.status)
        self.isNew = isNew
        self.onSave = onSave
        self.onDelete = onDelete
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Song title", text: $draft.title)
                        .font(.title3)
                    TextField("Artist", text: $draft.artist)
                    Picker("Status", selection: $status) {
                        ForEach(SongStatus.allCases) { status in
                            Label(status.label, systemImage: status.symbol).tag(status)
                        }
                    }
                }

                Section("Notes") {
                    TextField("Capo, tuning, tricky parts, goal tempo…", text: $draft.notes, axis: .vertical)
                        .lineLimit(3...8)
                }

                if !isNew && !draft.history.isEmpty {
                    Section("History") {
                        ForEach(Array(draft.history.reversed().enumerated()), id: \.offset) { entry in
                            HStack {
                                Label(entry.element.status.label, systemImage: entry.element.status.symbol)
                                    .foregroundStyle(entry.element.status.color)
                                Spacer()
                                Text(entry.element.date.formatted(date: .abbreviated, time: .omitted))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                if onDelete != nil {
                    Section {
                        Button("Remove from Repertoire", role: .destructive) {
                            confirmDelete = true
                        }
                    }
                }
            }
            .navigationTitle(isNew ? "Add Song" : "Edit Song")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isNew ? "Add" : "Save") {
                        var saved = draft
                        saved.title = saved.title.trimmingCharacters(in: .whitespacesAndNewlines)
                        if isNew {
                            saved.status = status
                            saved.history = [SongStatusChange(status: status, date: Date())]
                        } else {
                            saved.setStatus(status)
                        }
                        onSave(saved)
                        dismiss()
                    }
                    .disabled(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .confirmationDialog("Remove this song?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Remove", role: .destructive) {
                    onDelete?()
                    dismiss()
                }
            }
        }
    }
}
