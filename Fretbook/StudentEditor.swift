import SwiftUI

struct StudentEditor: View {
    @Environment(\.dismiss) private var dismiss

    @State private var draft: Student
    @State private var hasSlot: Bool
    @State private var confirmDelete = false

    let isNew: Bool
    let onSave: (Student) -> Void
    let onDelete: (() -> Void)?

    private let levels = ["Beginner", "Intermediate", "Advanced"]
    private let calendar = Calendar.current

    init(student: Student, isNew: Bool, onSave: @escaping (Student) -> Void, onDelete: (() -> Void)? = nil) {
        _draft = State(initialValue: student)
        _hasSlot = State(initialValue: student.weekday != nil)
        self.isNew = isNew
        self.onSave = onSave
        self.onDelete = onDelete
    }

    private var trimmedName: String {
        draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var orderedWeekdays: [Int] {
        (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 + 1 }
    }

    private var weekdayBinding: Binding<Int> {
        Binding(
            get: { draft.weekday ?? calendar.component(.weekday, from: Date()) },
            set: { draft.weekday = $0 }
        )
    }

    private var timeBinding: Binding<Date> {
        Binding(
            get: { TimeFormat.date(minutes: draft.startMinutes) },
            set: { newValue in
                let parts = calendar.dateComponents([.hour, .minute], from: newValue)
                draft.startMinutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $draft.name)
                        .font(.title3)
                    Picker("Level", selection: $draft.level) {
                        Text("—").tag("")
                        ForEach(levels, id: \.self) { level in
                            Text(level).tag(level)
                        }
                    }
                    HStack(spacing: 12) {
                        Text("Color")
                        Spacer()
                        ForEach(Palette.student.indices, id: \.self) { index in
                            Circle()
                                .fill(Palette.student[index].gradient)
                                .frame(width: 26, height: 26)
                                .overlay {
                                    if draft.colorIndex % Palette.student.count == index {
                                        Image(systemName: "checkmark")
                                            .font(.caption.bold())
                                            .foregroundStyle(.white)
                                    }
                                }
                                .onTapGesture { draft.colorIndex = index }
                        }
                    }
                }

                Section("Weekly lesson") {
                    Toggle("Fixed weekly slot", isOn: $hasSlot.animation())
                    if hasSlot {
                        Picker("Day", selection: weekdayBinding) {
                            ForEach(orderedWeekdays, id: \.self) { day in
                                Text(calendar.weekdaySymbols[day - 1]).tag(day)
                            }
                        }
                        DatePicker("Time", selection: timeBinding, displayedComponents: .hourAndMinute)
                        Stepper("\(draft.duration) minutes", value: $draft.duration, in: 15...180, step: 15)
                    }
                }

                Section("Goals & notes") {
                    TextField("What do they want to play? Favourite bands? Gear?", text: $draft.goals, axis: .vertical)
                        .lineLimit(3...8)
                }

                Section("Contact") {
                    TextField("Phone, email, parent's name…", text: $draft.contact, axis: .vertical)
                        .lineLimit(1...4)
                }

                if onDelete != nil {
                    Section {
                        Button("Delete Student", role: .destructive) {
                            confirmDelete = true
                        }
                    }
                }
            }
            .navigationTitle(isNew ? "New Student" : "Edit Student")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isNew ? "Add" : "Save") {
                        var saved = draft
                        saved.name = trimmedName
                        saved.weekday = hasSlot ? weekdayBinding.wrappedValue : nil
                        onSave(saved)
                        dismiss()
                    }
                    .disabled(trimmedName.isEmpty)
                }
            }
            .confirmationDialog("Delete \(draft.displayName)?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete Student and All Lessons", role: .destructive) {
                    dismiss()
                    onDelete?()
                }
            } message: {
                Text("This can't be undone.")
            }
        }
    }
}
