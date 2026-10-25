import SwiftUI

/// One student's page: info, open homework, and every lesson with its notes.
struct StudentPage: View {
    @Binding var student: Student
    var onDelete: () -> Void

    @State private var editingInfo = false
    @State private var filter: NoteCategory?
    @State private var editing: EditTarget?

    private var sortedLessons: [Lesson] {
        student.lessons.sorted { $0.date > $1.date }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header

                if !student.openHomework.isEmpty {
                    homework
                }

                if !student.allItems.isEmpty {
                    filterBar
                }

                if let filter {
                    filtered(by: filter)
                } else {
                    lessons
                }
            }
            .padding(24)
            .frame(maxWidth: 860, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(student.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    addLesson()
                } label: {
                    Label("New Lesson", systemImage: "plus")
                }
            }
            ToolbarItem(placement: .secondaryAction) {
                Button {
                    editingInfo = true
                } label: {
                    Label("Edit Student", systemImage: "pencil")
                }
            }
        }
        .sheet(isPresented: $editingInfo) {
            StudentEditor(student: student, isNew: false, onSave: { student = $0 }, onDelete: onDelete)
        }
        .sheet(item: $editing) { target in
            NoteEditor(
                item: target.item,
                isNew: false,
                onSave: { student.updateItem($0) },
                onDelete: { student.deleteItem(target.item.id) }
            )
        }
    }

    // MARK: Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) {
                Avatar(student: student, size: 64)
                VStack(alignment: .leading, spacing: 6) {
                    Text(student.displayName)
                        .font(.largeTitle.bold())
                    HStack(spacing: 10) {
                        if !student.level.isEmpty {
                            Chip(text: student.level, color: student.color)
                        }
                        if let slot = student.slotDescription {
                            Label(slot, systemImage: "clock")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Spacer()
                Button {
                    editingInfo = true
                } label: {
                    Image(systemName: "pencil.circle")
                        .font(.title)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            if !student.goals.isEmpty || !student.contact.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    if !student.goals.isEmpty {
                        Label {
                            Text(student.goals)
                        } icon: {
                            Image(systemName: "target")
                                .foregroundStyle(student.color)
                        }
                    }
                    if !student.contact.isEmpty {
                        Label {
                            Text(student.contact)
                                .foregroundStyle(.secondary)
                        } icon: {
                            Image(systemName: "person.crop.circle")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .font(.callout)
                .card()
            }
        }
    }

    private var homework: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "Open homework", systemImage: "checklist", color: NoteCategory.homework.color)
            VStack(alignment: .leading, spacing: 12) {
                ForEach(student.openHomework) { item in
                    HStack(alignment: .top, spacing: 12) {
                        Button {
                            withAnimation { student.toggleDone(item.id) }
                        } label: {
                            Image(systemName: "circle")
                                .font(.title3)
                                .foregroundStyle(NoteCategory.homework.color)
                        }
                        .buttonStyle(.plain)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title.isEmpty ? "Homework" : item.title)
                                .font(.body.weight(.medium))
                            if !item.body.isEmpty {
                                Text(item.body)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 0)
                        if let bpm = item.bpm {
                            Chip(text: "♩ = \(bpm)", color: NoteCategory.homework.color)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { editing = EditTarget(item: item, isNew: false) }
                }
            }
            .card()
        }
    }

    private var usedCategories: [CategoryCount] {
        let items = student.allItems
        return NoteCategory.allCases.compactMap { category in
            let count = items.filter { $0.category == category }.count
            return count > 0 ? CategoryCount(category: category, count: count) : nil
        }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(title: "All lessons", systemImage: "calendar", color: .accentColor, selected: filter == nil) {
                    filter = nil
                }
                ForEach(usedCategories, id: \.category) { entry in
                    FilterChip(
                        title: "\(entry.category.label) \(entry.count)",
                        systemImage: entry.category.symbol,
                        color: entry.category.color,
                        selected: filter == entry.category
                    ) {
                        filter = filter == entry.category ? nil : entry.category
                    }
                }
            }
        }
    }

    private var lessons: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                SectionTitle(title: "Lessons", systemImage: "book.closed", color: .accentColor)
                Spacer()
                Button {
                    addLesson()
                } label: {
                    Label("New Lesson", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }

            if student.lessons.isEmpty {
                Text("No lessons yet. Tap New Lesson after (or during) your next lesson.")
                    .foregroundStyle(.secondary)
                    .card()
            }

            ForEach(sortedLessons) { lesson in
                LessonCard(lesson: lessonBinding(lesson.id)) {
                    withAnimation {
                        student.lessons.removeAll { $0.id == lesson.id }
                    }
                }
            }
        }
    }

    /// Everything of one category across all lessons, newest first.
    private func filtered(by category: NoteCategory) -> some View {
        let entries = sortedLessons.flatMap { lesson in
            lesson.items
                .filter { $0.category == category }
                .map { DatedItem(date: lesson.date, item: $0) }
        }

        return VStack(alignment: .leading, spacing: 14) {
            SectionTitle(title: "All \(category.label.lowercased()) notes", systemImage: category.symbol, color: category.color)

            if category == .chord {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 10)], spacing: 10) {
                    ForEach(entries) { entry in
                        ChordTile(item: entry.item, date: entry.date)
                            .onTapGesture { editing = EditTarget(item: entry.item, isNew: false) }
                    }
                }
                .card()
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(entries) { entry in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(entry.date.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            NoteItemView(item: entry.item, onToggleDone: { student.toggleDone(entry.item.id) })
                                .contentShape(Rectangle())
                                .onTapGesture { editing = EditTarget(item: entry.item, isNew: false) }
                        }
                    }
                }
                .card()
            }
        }
    }

    // MARK: Actions

    private func addLesson() {
        withAnimation {
            filter = nil
            student.lessons.append(Lesson(date: Date()))
        }
    }

    private func lessonBinding(_ id: UUID) -> Binding<Lesson> {
        Binding(
            get: { student.lessons.first(where: { $0.id == id }) ?? Lesson() },
            set: { newValue in
                if let i = student.lessons.firstIndex(where: { $0.id == id }) {
                    student.lessons[i] = newValue
                }
            }
        )
    }
}

// MARK: - Helpers

struct EditTarget: Identifiable {
    var item: NoteItem
    var isNew: Bool
    var id: UUID { item.id }
}

struct CategoryCount: Hashable {
    let category: NoteCategory
    let count: Int
}

struct DatedItem: Identifiable {
    let date: Date
    let item: NoteItem
    var id: UUID { item.id }
}

struct SectionTitle: View {
    let title: String
    let systemImage: String
    var color: Color = .accentColor

    var body: some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(color)
        }
        .font(.title3.bold())
    }
}

struct FilterChip: View {
    let title: String
    let systemImage: String
    let color: Color
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .foregroundStyle(selected ? Color.white : color)
                .background(selected ? color : color.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
