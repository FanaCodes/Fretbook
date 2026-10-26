import SwiftUI

struct LessonCard: View {
    @Binding var lesson: Lesson
    var onDelete: () -> Void
    var onHandout: () -> Void = {}
    var onMakeChart: () -> Void = {}

    @State private var editing: EditTarget?
    @State private var confirmDelete = false

    private var chords: [NoteItem] { lesson.items.filter { $0.category == .chord } }
    private var others: [NoteItem] { lesson.items.filter { $0.category != .chord } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                DatePicker("Lesson date", selection: $lesson.date, displayedComponents: .date)
                    .labelsHidden()
                Spacer()
                Menu {
                    Button(action: onHandout) {
                        Label("Lesson Handout (PDF)", systemImage: "doc.richtext")
                    }
                    Button(action: onMakeChart) {
                        Label("Chord Chart from This Lesson", systemImage: "square.grid.3x3")
                    }
                    .disabled(chords.isEmpty)
                    Divider()
                    Button(role: .destructive) {
                        confirmDelete = true
                    } label: {
                        Label("Delete Lesson", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }

            TextField("What did you work on today?", text: $lesson.summary, axis: .vertical)
                .font(.body)

            if !chords.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 10)], spacing: 10) {
                    ForEach(chords) { item in
                        ChordTile(item: item)
                            .onTapGesture { editing = EditTarget(item: item, isNew: false) }
                    }
                }
            }

            ForEach(others) { item in
                NoteItemView(item: item, onToggleDone: { toggleDone(item.id) })
                    .contentShape(Rectangle())
                    .onTapGesture { editing = EditTarget(item: item, isNew: false) }
            }

            Menu {
                ForEach(NoteCategory.allCases) { category in
                    Button {
                        editing = EditTarget(item: NoteItem(category: category), isNew: true)
                    } label: {
                        Label(category.label, systemImage: category.symbol)
                    }
                }
            } label: {
                Label("Add to lesson", systemImage: "plus.circle.fill")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.bordered)
        }
        .card()
        .sheet(item: $editing) { target in
            NoteEditor(
                item: target.item,
                isNew: target.isNew,
                onSave: { save($0) },
                onDelete: target.isNew ? nil : { delete(target.item.id) }
            )
        }
        .confirmationDialog("Delete this lesson?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete Lesson", role: .destructive, action: onDelete)
        } message: {
            Text("All notes in this lesson will be removed.")
        }
    }

    private func save(_ item: NoteItem) {
        if let i = lesson.items.firstIndex(where: { $0.id == item.id }) {
            lesson.items[i] = item
        } else {
            withAnimation { lesson.items.append(item) }
        }
    }

    private func delete(_ id: UUID) {
        withAnimation { lesson.items.removeAll { $0.id == id } }
    }

    private func toggleDone(_ id: UUID) {
        if let i = lesson.items.firstIndex(where: { $0.id == id }) {
            withAnimation { lesson.items[i].done.toggle() }
        }
    }
}
