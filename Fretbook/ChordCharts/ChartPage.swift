import SwiftUI

struct DiagramTarget: Identifiable {
    var diagram: FretDiagram
    var isNew: Bool
    var id: UUID { diagram.id }
}

/// Builds and arranges one printable chord chart.
struct ChartPage: View {
    @Binding var chart: ChordChart
    var onDelete: () -> Void

    @State private var editing: DiagramTarget?
    @State private var preview: PDFFile?
    @State private var confirmDelete = false
    @State private var showingPositions = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                settingsCard
                if chart.diagrams.isEmpty {
                    emptyState
                } else {
                    ForEach(0..<chart.pageCount, id: \.self) { page in
                        pageView(page)
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(chart.title.isEmpty ? "Chord Chart" : chart.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    preview = ChartPDF.make(chart).map(PDFFile.init)
                } label: {
                    Label("Print / PDF", systemImage: "printer")
                }
                .disabled(chart.diagrams.isEmpty)
            }
            ToolbarItem(placement: .primaryAction) {
                addMenu
            }
            ToolbarItem(placement: .secondaryAction) {
                Button(role: .destructive) {
                    confirmDelete = true
                } label: {
                    Label("Delete Chart", systemImage: "trash")
                }
            }
        }
        .fullScreenCover(item: $editing) { target in
            DiagramEditor(diagram: target.diagram, isNew: target.isNew, chart: chart) { saved in
                save(saved)
            }
        }
        .sheet(item: $preview) { file in
            PDFPreviewSheet(file: file)
        }
        .sheet(isPresented: $showingPositions) {
            ScalePositionsSheet(woodFretboard: chart.woodFretboard) { diagrams, title, subtitle in
                addPositions(diagrams, title: title, subtitle: subtitle)
            }
        }
        .confirmationDialog("Delete this chart?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete Chart", role: .destructive, action: onDelete)
        }
    }

    // MARK: Settings

    private var layoutBinding: Binding<String> {
        Binding(
            get: { chart.layout.id },
            set: { id in
                if let layout = ChartLayout.presets.first(where: { $0.id == id }) {
                    chart.layout = layout
                }
            }
        )
    }

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            TextField("Title", text: $chart.title)
                .font(.title.bold())
            TextField("Subtitle (optional), e.g. student name or song", text: $chart.subtitle)
                .foregroundStyle(.secondary)

            Divider()

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) { layoutControls }
                VStack(alignment: .leading, spacing: 12) { layoutControls }
            }

            HStack(spacing: 18) {
                Toggle("Tuning under strings", isOn: $chart.showTuning)
                Toggle("Note names in dots", isOn: $chart.showNoteNames)
                Toggle("Left-handed", isOn: $chart.leftHanded)
                Toggle("Wood fretboard", isOn: $chart.woodFretboard)
            }
            .toggleStyle(.button)
            .font(.subheadline)

            Text("\(chart.diagrams.count) diagram\(chart.diagrams.count == 1 ? "" : "s") · \(chart.pageCount) page\(chart.pageCount == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .card()
    }

    @ViewBuilder
    private var layoutControls: some View {
        Picker("Per page", selection: layoutBinding) {
            ForEach(ChartLayout.presets) { layout in
                Text(layout.label).tag(layout.id)
            }
        }
        .pickerStyle(.menu)

        Picker("Paper", selection: $chart.paper) {
            ForEach(PaperSize.allCases) { paper in
                Text(paper.label).tag(paper)
            }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 220)
    }

    // MARK: Pages

    private func pageView(_ page: Int) -> some View {
        let items = chart.diagrams(onPage: page)
        let isLast = page == chart.pageCount - 1
        let hasRoom = items.count < chart.perPage

        return VStack(alignment: .leading, spacing: 8) {
            Text("Page \(page + 1)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: chart.columns), spacing: 14) {
                ForEach(items) { diagram in
                    tile(diagram)
                }
                if isLast && hasRoom {
                    addTile
                }
            }
            .padding(18)
            .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 6))
            .shadow(color: .black.opacity(0.08), radius: 8, y: 3)

            if isLast && !hasRoom {
                Button {
                    addBlank()
                } label: {
                    Label("Add diagram (starts a new page)", systemImage: "plus")
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func tile(_ diagram: FretDiagram) -> some View {
        DiagramCard(
            diagram: diagram,
            leftHanded: chart.leftHanded,
            showTuning: chart.showTuning,
            showNoteNames: chart.showNoteNames,
            woodFretboard: chart.woodFretboard,
            nameSize: chart.columns >= 4 ? 15 : 20
        )
        .frame(maxWidth: chart.columns == 1 && diagram.kind == .box ? 320 : .infinity)
        .frame(maxWidth: .infinity)
        .padding(6)
        .contentShape(Rectangle())
        .onTapGesture { editing = DiagramTarget(diagram: diagram, isNew: false) }
        .contextMenu {
            Button {
                editing = DiagramTarget(diagram: diagram, isNew: false)
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            Button {
                duplicate(diagram)
            } label: {
                Label("Duplicate", systemImage: "plus.square.on.square")
            }
            Button {
                move(diagram, by: -1)
            } label: {
                Label("Move Earlier", systemImage: "arrow.left")
            }
            .disabled(chart.diagrams.first?.id == diagram.id)
            Button {
                move(diagram, by: 1)
            } label: {
                Label("Move Later", systemImage: "arrow.right")
            }
            .disabled(chart.diagrams.last?.id == diagram.id)
            Divider()
            Button(role: .destructive) {
                withAnimation { chart.diagrams.removeAll { $0.id == diagram.id } }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private var addTile: some View {
        Button {
            addBlank()
        } label: {
            VStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.title2.weight(.semibold))
                Text("Add diagram")
                    .font(.caption.weight(.medium))
            }
            .foregroundStyle(Color.accentColor)
            .frame(maxWidth: .infinity, minHeight: 140)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
            )
        }
        .buttonStyle(.plain)
    }

    private var addMenu: some View {
        Menu {
            Button {
                addBlank()
            } label: {
                Label("Blank Diagram", systemImage: "square.dashed")
            }
            Button {
                showingPositions = true
            } label: {
                Label("5 Scale Positions…", systemImage: "rectangle.split.1x2")
            }
            Button {
                addScale()
            } label: {
                Label("Scale on Fretboard", systemImage: "pianokeys")
            }
            Button {
                addOpenChords()
            } label: {
                Label("All Open Chords (C A G E D Am Em Dm)", systemImage: "square.grid.3x3.fill")
            }
            Menu {
                ForEach(ShapePreset.common) { preset in
                    Button(preset.name) {
                        withAnimation { chart.diagrams.append(preset.diagram) }
                    }
                }
            } label: {
                Label("Common Chord", systemImage: "music.note.list")
            }
        } label: {
            Label("Add", systemImage: "plus")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "square.grid.3x3")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("No diagrams yet")
                .font(.title3.bold())
            Text("Draw your own, generate a scale on the fretboard, or start with the common open chords.")
                .foregroundStyle(.secondary)
            HStack {
                Button("Blank Diagram") { addBlank() }
                    .buttonStyle(.bordered)
                Button("5 Scale Positions") { showingPositions = true }
                    .buttonStyle(.bordered)
                Button("Add Open Chords") { addOpenChords() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .card()
    }

    // MARK: Actions

    private func addBlank() {
        var diagram = FretDiagram()
        // New diagrams continue in the tuning of the previous one.
        if let last = chart.diagrams.last {
            diagram.setTuning(last.tuning)
            diagram.preferFlats = last.preferFlats
        }
        editing = DiagramTarget(diagram: diagram, isNew: true)
    }

    private func addScale() {
        var diagram = FretDiagram()
        if let last = chart.diagrams.last { diagram.setTuning(last.tuning) }
        diagram.kind = .neck
        diagram.fretCount = 12
        if let pentatonic = Scales.all.first(where: { $0.name == "Minor Pentatonic" }) {
            diagram.fill(scale: pentatonic, root: 9, labels: .intervals)
        }
        editing = DiagramTarget(diagram: diagram, isNew: true)
    }

    private func addPositions(_ diagrams: [FretDiagram], title: String, subtitle: String) {
        withAnimation {
            if chart.diagrams.isEmpty {
                chart.title = title
                chart.subtitle = subtitle
                chart.showTuning = false
                chart.layout = ChartLayout(columns: 1, rows: 5)
            }
            chart.diagrams.append(contentsOf: diagrams)
        }
    }

    private func addOpenChords() {
        let shapes = ShapePreset.common.filter { ShapePreset.openChords.contains($0.name) }
        withAnimation { chart.diagrams.append(contentsOf: shapes.map(\.diagram)) }
    }

    private func save(_ diagram: FretDiagram) {
        if let index = chart.diagrams.firstIndex(where: { $0.id == diagram.id }) {
            chart.diagrams[index] = diagram
        } else {
            chart.diagrams.append(diagram)
        }
    }

    private func duplicate(_ diagram: FretDiagram) {
        guard let index = chart.diagrams.firstIndex(where: { $0.id == diagram.id }) else { return }
        var copy = diagram
        copy.id = UUID()
        withAnimation { chart.diagrams.insert(copy, at: index + 1) }
    }

    private func move(_ diagram: FretDiagram, by offset: Int) {
        guard let index = chart.diagrams.firstIndex(where: { $0.id == diagram.id }) else { return }
        let target = index + offset
        guard chart.diagrams.indices.contains(target) else { return }
        withAnimation { chart.diagrams.swapAt(index, target) }
    }
}
