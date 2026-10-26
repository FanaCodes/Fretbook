import SwiftUI
import Charts

struct StatTile: View {
    let value: String
    let label: String
    let systemImage: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: systemImage)
                .font(.headline)
                .foregroundStyle(color)
            Text(value)
                .font(.system(.title2, design: .rounded).weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// Stats, charts and a timeline of what a student has achieved.
struct StudentProgressView: View {
    let student: Student

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            ProgressStats(student: student)

            if student.lessons.isEmpty {
                Text("Progress appears here as you add lessons: chords learned, tempo gains and repertoire milestones.")
                    .foregroundStyle(.secondary)
                    .card()
            }

            if !student.learnedChords.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    SectionTitle(title: "Chords learned", systemImage: NoteCategory.chord.symbol, color: NoteCategory.chord.color)
                    ChordsLearnedChart(chords: student.learnedChords)
                        .card()
                }
            }

            if !student.tempoSeries.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    SectionTitle(title: "Tempo progress", systemImage: "metronome.fill", color: .purple)
                    TempoList(series: student.tempoSeries)
                        .card()
                }
            }

            if !student.progressEvents.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    SectionTitle(title: "Timeline", systemImage: "clock.arrow.circlepath", color: .accentColor)
                    ProgressTimeline(events: Array(student.progressEvents.prefix(40)))
                        .card()
                }
            }
        }
    }
}

struct ProgressStats: View {
    let student: Student

    var body: some View {
        let homework = student.allItems.filter { $0.category == .homework }
        let done = homework.filter(\.done).count
        let songs = student.repertoire.filter { $0.status == .canPlay || $0.status == .ready }.count
        let since = student.sortedLessonsAscending.first?.date

        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 12) {
            StatTile(value: "\(student.lessons.count)", label: since.map { "lessons since \($0.formatted(.dateTime.month(.abbreviated).year()))" } ?? "lessons",
                     systemImage: "book.closed.fill", color: .accentColor)
            StatTile(value: "\(student.learnedChords.count)", label: "chords learned", systemImage: NoteCategory.chord.symbol, color: NoteCategory.chord.color)
            StatTile(value: "\(songs)", label: "songs they can play", systemImage: "music.note.list", color: NoteCategory.song.color)
            StatTile(value: homework.isEmpty ? "–" : "\(done)/\(homework.count)", label: "homework done", systemImage: "checklist", color: NoteCategory.homework.color)
        }
    }
}

struct ChordsLearnedChart: View {
    let chords: [LearnedChord]

    private struct Point: Identifiable {
        let date: Date
        let count: Int
        var id: Int { count }
    }

    var body: some View {
        let points = chords.enumerated().map { Point(date: $0.element.date, count: $0.offset + 1) }

        VStack(alignment: .leading, spacing: 14) {
            if points.count > 1 {
                Chart(points) { point in
                    AreaMark(x: .value("Date", point.date), y: .value("Chords", point.count))
                        .interpolationMethod(.stepEnd)
                        .foregroundStyle(NoteCategory.chord.color.opacity(0.15))
                    LineMark(x: .value("Date", point.date), y: .value("Chords", point.count))
                        .interpolationMethod(.stepEnd)
                        .foregroundStyle(NoteCategory.chord.color)
                    PointMark(x: .value("Date", point.date), y: .value("Chords", point.count))
                        .foregroundStyle(NoteCategory.chord.color)
                        .symbolSize(24)
                }
                .chartYAxisLabel("Total chords")
                .frame(height: 160)
            }

            FlowChips(items: chords.map { $0.name }, color: NoteCategory.chord.color)
        }
    }
}

/// Simple wrapping row of small labels.
struct FlowChips: View {
    let items: [String]
    let color: Color

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 6)], alignment: .leading, spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { entry in
                Text(entry.element)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(color)
                    .background(color.opacity(0.12), in: Capsule())
            }
        }
    }
}

struct TempoList: View {
    let series: [TempoSeries]

    var body: some View {
        VStack(spacing: 14) {
            ForEach(series) { item in
                HStack(spacing: 14) {
                    CategoryBadge(category: item.category, size: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(.body.weight(.medium))
                        if item.points.count > 1 {
                            Text("\(item.first) → \(item.latest) BPM")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("\(item.latest) BPM · \(item.points.last?.date.formatted(date: .abbreviated, time: .omitted) ?? "")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if item.points.count > 1 {
                        Chart(item.points) { point in
                            LineMark(x: .value("Date", point.date), y: .value("BPM", point.bpm))
                                .foregroundStyle(Color.purple)
                            PointMark(x: .value("Date", point.date), y: .value("BPM", point.bpm))
                                .foregroundStyle(Color.purple)
                                .symbolSize(14)
                        }
                        .chartXAxis(.hidden)
                        .chartYAxis(.hidden)
                        .chartYScale(domain: .automatic(includesZero: false))
                        .frame(width: 110, height: 36)

                        Text(item.gain >= 0 ? "+\(item.gain)" : "\(item.gain)")
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(item.gain > 0 ? Color.green : Color.secondary)
                            .frame(width: 48, alignment: .trailing)
                    }
                }
            }
        }
    }
}

struct ProgressTimeline: View {
    let events: [ProgressEvent]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(events) { event in
                HStack(alignment: .top, spacing: 12) {
                    VStack(spacing: 0) {
                        Image(systemName: event.symbol)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 26, height: 26)
                            .background(event.color.gradient, in: Circle())
                        if event.id != events.last?.id {
                            Rectangle()
                                .fill(Color.secondary.opacity(0.25))
                                .frame(width: 2)
                                .frame(minHeight: 14)
                        }
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.text)
                            .font(.subheadline.weight(.medium))
                        Text(event.date.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 3)
                    .padding(.bottom, 12)
                    Spacer(minLength: 0)
                }
            }
        }
    }
}
