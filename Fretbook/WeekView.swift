import SwiftUI

struct WeekView: View {
    @EnvironmentObject private var store: Store
    @Binding var selection: SidebarItem?
    var onAddStudent: () -> Void

    private let calendar = Calendar.current

    private var orderedWeekdays: [Int] {
        (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 + 1 }
    }

    private var today: Int { calendar.component(.weekday, from: Date()) }

    private func students(on day: Int) -> [Student] {
        store.students
            .filter { $0.weekday == day }
            .sorted { $0.startMinutes < $1.startMinutes }
    }

    private var unscheduled: [Student] {
        store.sortedStudents.filter { $0.weekday == nil }
    }

    var body: some View {
        Group {
            if store.students.isEmpty {
                ContentUnavailableView {
                    Label("No students yet", systemImage: "person.2")
                } description: {
                    Text("Add your first student to start taking lesson notes.")
                } actions: {
                    Button("Add Student", action: onAddStudent)
                        .buttonStyle(.borderedProminent)
                }
            } else {
                List {
                    ForEach(orderedWeekdays, id: \.self) { day in
                        if day == today || !students(on: day).isEmpty {
                            Section {
                                if students(on: day).isEmpty {
                                    Text("No lessons today")
                                        .foregroundStyle(.secondary)
                                } else {
                                    ForEach(students(on: day)) { student in
                                        row(for: student, showTime: true)
                                    }
                                }
                            } header: {
                                HStack {
                                    Text(calendar.weekdaySymbols[day - 1])
                                    if day == today {
                                        Text("Today")
                                            .font(.caption2.weight(.bold))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.accentColor, in: Capsule())
                                            .foregroundStyle(.white)
                                    }
                                }
                            }
                        }
                    }

                    if !unscheduled.isEmpty {
                        Section("No fixed slot") {
                            ForEach(unscheduled) { student in
                                row(for: student, showTime: false)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("This Week")
    }

    private func row(for student: Student, showTime: Bool) -> some View {
        Button {
            selection = .student(student.id)
        } label: {
            HStack(spacing: 14) {
                if showTime {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(TimeFormat.string(minutes: student.startMinutes))
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                        Text("\(student.duration) min")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 72, alignment: .trailing)
                }
                Avatar(student: student, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(student.displayName)
                        .font(.body.weight(.medium))
                    if let last = student.lastLessonDate {
                        Text("Last lesson \(last.formatted(.relative(presentation: .named)))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                let homework = student.openHomework.count
                if homework > 0 {
                    Chip(text: "\(homework) homework", systemImage: "checklist", color: NoteCategory.homework.color)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
