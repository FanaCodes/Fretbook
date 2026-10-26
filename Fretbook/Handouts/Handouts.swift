import SwiftUI
import Charts

// MARK: - Paginated PDF

/// Lays out a list of blocks onto as many pages as needed and writes a vector PDF.
enum PDFPaginator {
    static let margin: CGFloat = 44
    static let spacing: CGFloat = 16
    static let footerHeight: CGFloat = 16

    @MainActor
    static func make(fileName: String, paper: PaperSize, footer: String, blocks: [AnyView]) -> URL? {
        let size = paper.size
        let width = size.width - margin * 2
        let usable = size.height - margin * 2 - footerHeight - spacing

        // Measure every block at the printable width, then fill pages greedily.
        let heights = blocks.map { measure($0, width: width) }
        var pages: [[Int]] = [[]]
        var used: CGFloat = 0
        for (index, height) in heights.enumerated() {
            let needed = (pages[pages.count - 1].isEmpty ? 0 : spacing) + height
            if used + needed > usable && !pages[pages.count - 1].isEmpty {
                pages.append([index])
                used = height
            } else {
                pages[pages.count - 1].append(index)
                used += needed
            }
        }

        let safeName = fileName
            .components(separatedBy: CharacterSet(charactersIn: "/\\:?*\"<>|"))
            .joined(separator: "-")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(safeName.isEmpty ? "Handout" : safeName)
            .appendingPathExtension("pdf")

        var box = CGRect(origin: .zero, size: size)
        guard let pdf = CGContext(url as CFURL, mediaBox: &box, nil) else { return nil }
        for (pageIndex, indices) in pages.enumerated() {
            let page = HandoutPage(
                blocks: indices.map { blocks[$0] },
                size: size,
                footer: footer,
                pageText: pages.count > 1 ? "\(pageIndex + 1) / \(pages.count)" : ""
            )
            let renderer = ImageRenderer(content: page)
            renderer.proposedSize = ProposedViewSize(size)
            pdf.beginPDFPage(nil)
            renderer.render { _, draw in draw(pdf) }
            pdf.endPDFPage()
        }
        pdf.closePDF()
        return url
    }

    @MainActor
    private static func measure(_ block: AnyView, width: CGFloat) -> CGFloat {
        let controller = UIHostingController(rootView: block
            .frame(width: width, alignment: .leading)
            .environment(\.colorScheme, .light))
        return controller.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude)).height
    }
}

struct HandoutPage: View {
    let blocks: [AnyView]
    let size: CGSize
    let footer: String
    let pageText: String

    var body: some View {
        VStack(alignment: .leading, spacing: PDFPaginator.spacing) {
            ForEach(blocks.indices, id: \.self) { index in
                blocks[index]
            }
            Spacer(minLength: 0)
            HStack {
                Text(footer)
                Spacer()
                Text(pageText)
            }
            .font(.system(size: 8))
            .foregroundStyle(.secondary)
            .frame(height: PDFPaginator.footerHeight)
        }
        .padding(PDFPaginator.margin)
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .background(Color.white)
        .environment(\.colorScheme, .light)
    }
}

// MARK: - Shared print pieces

struct PrintHeader: View {
    let title: String
    let subtitle: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 24, weight: .bold))
            Text(subtitle)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            if !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 11))
                    .padding(.top, 6)
            }
            Rectangle()
                .fill(Color.primary.opacity(0.15))
                .frame(height: 1)
                .padding(.top, 8)
        }
    }
}

struct PrintSectionTitle: View {
    let title: String
    let color: Color

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .bold))
            .tracking(1)
            .foregroundStyle(color)
    }
}

/// One lesson note, laid out for paper (no scroll views or buttons).
struct PrintNoteItem: View {
    let item: NoteItem

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(item.category.label.uppercased())
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(item.category.color)
                Text(item.title.isEmpty ? item.category.label : item.title)
                    .font(.system(size: 12, weight: .semibold))
                if !item.key.isEmpty {
                    Text("Key: \(item.key)")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                if let bpm = item.bpm {
                    Text("♩ = \(bpm)")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            if !item.strum.isEmpty {
                StrumView(pattern: item.strum)
                    .scaleEffect(0.85, anchor: .leading)
            }
            if !item.tab.isEmpty {
                Text(item.tab)
                    .font(.system(size: 9, design: .monospaced))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !item.body.isEmpty {
                Text(item.body)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.leading, 10)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(item.category.color)
                .frame(width: 2.5)
        }
    }
}

/// A row of chord diagrams for paper.
struct PrintDiagramRow: View {
    let diagrams: [FretDiagram]
    var perRow = 5

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ForEach(diagrams) { diagram in
                DiagramCard(diagram: diagram, showTuning: false, nameSize: 13)
                    .frame(width: 82, height: 120)
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Lesson handout

enum LessonHandout {
    @MainActor
    static func make(student: Student, lesson: Lesson) -> URL? {
        let date = lesson.date.formatted(date: .complete, time: .omitted)
        var blocks: [AnyView] = [
            AnyView(PrintHeader(title: student.displayName, subtitle: "Lesson · \(date)", detail: lesson.summary))
        ]

        let chords = lesson.items
            .filter { $0.category == .chord }
            .compactMap { FretDiagram.fromChordNote(name: $0.title, frets: $0.frets) }
        if !chords.isEmpty {
            blocks.append(AnyView(PrintSectionTitle(title: "Chords", color: NoteCategory.chord.color)))
            for start in stride(from: 0, to: chords.count, by: 5) {
                blocks.append(AnyView(PrintDiagramRow(diagrams: Array(chords[start..<min(start + 5, chords.count)]))))
            }
        }
        // Chord notes without a valid shape still get printed as text.
        let otherItems = lesson.items.filter {
            $0.category != .homework && ($0.category != .chord || ChordShape($0.frets) == nil)
        }
        if !otherItems.isEmpty {
            blocks.append(AnyView(PrintSectionTitle(title: "What we worked on", color: .primary)))
            blocks.append(contentsOf: otherItems.map { AnyView(PrintNoteItem(item: $0)) })
        }

        let homework = lesson.items.filter { $0.category == .homework }
        if !homework.isEmpty {
            blocks.append(AnyView(PrintSectionTitle(title: "Homework", color: NoteCategory.homework.color)))
            blocks.append(contentsOf: homework.map { AnyView(HomeworkLine(item: $0)) })
        }

        return PDFPaginator.make(
            fileName: "\(student.displayName) – Lesson \(lesson.date.formatted(.iso8601.year().month().day()))",
            paper: .regionalDefault,
            footer: "\(student.displayName) · \(date)",
            blocks: blocks
        )
    }
}

struct HomeworkLine: View {
    let item: NoteItem

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 3)
                .stroke(Color.primary, lineWidth: 1)
                .frame(width: 12, height: 12)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.title.isEmpty ? "Practice" : item.title)
                        .font(.system(size: 12, weight: .semibold))
                    if let bpm = item.bpm {
                        Text("♩ = \(bpm)")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
                if !item.body.isEmpty {
                    Text(item.body)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

// MARK: - Progress report

enum ProgressReport {
    @MainActor
    static func make(student: Student) -> URL? {
        let today = Date().formatted(date: .long, time: .omitted)
        var detail: [String] = []
        if let first = student.sortedLessonsAscending.first {
            detail.append("Lessons since \(first.date.formatted(date: .long, time: .omitted)) · \(student.lessons.count) lessons")
        }
        if !student.level.isEmpty { detail.append("Level: \(student.level)") }
        if !student.goals.isEmpty { detail.append("Goals: \(student.goals)") }

        var blocks: [AnyView] = [
            AnyView(PrintHeader(title: student.displayName, subtitle: "Progress report · \(today)", detail: detail.joined(separator: "\n"))),
            AnyView(PrintStats(student: student)),
        ]

        let chords = student.learnedChords
        if !chords.isEmpty {
            blocks.append(AnyView(PrintSectionTitle(title: "Chords learned (\(chords.count))", color: NoteCategory.chord.color)))
            if chords.count > 1 {
                blocks.append(AnyView(ChordsLearnedChart(chords: chords)))
            } else {
                blocks.append(AnyView(FlowChips(items: chords.map(\.name), color: NoteCategory.chord.color)))
            }
        }

        let tempo = student.tempoSeries.filter { $0.points.count > 1 }
        if !tempo.isEmpty {
            blocks.append(AnyView(PrintSectionTitle(title: "Tempo progress", color: .purple)))
            blocks.append(AnyView(TempoList(series: Array(tempo.prefix(10)))))
        }

        let songs = student.repertoire
        if !songs.isEmpty {
            blocks.append(AnyView(PrintSectionTitle(title: "Repertoire", color: NoteCategory.song.color)))
            for status in SongStatus.displayOrder {
                let group = songs.filter { $0.status == status }
                if !group.isEmpty {
                    blocks.append(AnyView(PrintSongGroup(status: status, songs: group)))
                }
            }
        }

        let events = student.progressEvents
        if !events.isEmpty {
            blocks.append(AnyView(PrintSectionTitle(title: "Recent milestones", color: .primary)))
            blocks.append(AnyView(ProgressTimeline(events: Array(events.prefix(12)))))
        }

        return PDFPaginator.make(
            fileName: "\(student.displayName) – Progress Report",
            paper: .regionalDefault,
            footer: "\(student.displayName) · Progress report · \(today)",
            blocks: blocks
        )
    }
}

struct PrintStats: View {
    let student: Student

    var body: some View {
        let homework = student.allItems.filter { $0.category == .homework }
        let songs = student.repertoire.filter { $0.status == .canPlay || $0.status == .ready }.count

        HStack(spacing: 10) {
            stat("\(student.lessons.count)", "lessons")
            stat("\(student.learnedChords.count)", "chords learned")
            stat("\(songs)", "songs they can play")
            stat(homework.isEmpty ? "–" : "\(homework.filter(\.done).count)/\(homework.count)", "homework done")
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct PrintSongGroup: View {
    let status: SongStatus
    let songs: [RepertoireSong]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(status.label, systemImage: status.symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(status.color)
            ForEach(songs) { song in
                HStack {
                    Text(song.title)
                        .font(.system(size: 11, weight: .medium))
                    if !song.artist.isEmpty {
                        Text("– \(song.artist)")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(song.statusDate.formatted(date: .abbreviated, time: .omitted))
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Chord charts from lessons

enum LessonCharts {
    /// Builds a chord chart from chord notes, de-duplicated, in the order they were learned.
    static func chart(title: String, subtitle: String, chordItems: [(item: NoteItem, date: Date)]) -> ChordChart? {
        var seen = Set<String>()
        var diagrams: [FretDiagram] = []
        for entry in chordItems.sorted(by: { $0.date < $1.date }) {
            let key = entry.item.title.lowercased() + "|" + entry.item.frets
            guard seen.insert(key).inserted,
                  let diagram = FretDiagram.fromChordNote(name: entry.item.title, frets: entry.item.frets) else { continue }
            diagrams.append(diagram)
        }
        guard !diagrams.isEmpty else { return nil }
        var chart = ChordChart(title: title)
        chart.subtitle = subtitle
        chart.diagrams = diagrams
        let layout = ChartLayout.presets.first { $0.perPage >= diagrams.count && $0.columns >= 2 } ?? ChartLayout(columns: 4, rows: 5)
        chart.layout = layout
        return chart
    }

    static func forStudent(_ student: Student) -> ChordChart? {
        let items = student.lessons.flatMap { lesson in
            lesson.items.filter { $0.category == .chord }.map { (item: $0, date: lesson.date) }
        }
        return chart(
            title: "\(student.displayName) – Chords",
            subtitle: "Everything learned so far · \(Date().formatted(date: .abbreviated, time: .omitted))",
            chordItems: items
        )
    }

    static func forLesson(_ lesson: Lesson, student: Student) -> ChordChart? {
        let items = lesson.items.filter { $0.category == .chord }.map { (item: $0, date: lesson.date) }
        return chart(
            title: "\(student.displayName) – Chords",
            subtitle: "Lesson · \(lesson.date.formatted(date: .abbreviated, time: .omitted))",
            chordItems: items
        )
    }
}
