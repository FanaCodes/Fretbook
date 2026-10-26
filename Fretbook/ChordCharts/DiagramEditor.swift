import SwiftUI

/// Full-screen editor for one diagram: tap to place dots, drag across strings for a barre.
struct DiagramEditor: View {
    @Environment(\.dismiss) private var dismiss

    @State private var draft: FretDiagram
    @State private var selection: UUID?
    @State private var tuningText: String
    @State private var confirmClear = false
    @State private var scaleRoot = 9
    @State private var scaleName = "Minor Pentatonic"
    @State private var scaleLabels: ScaleLabels = .intervals

    let isNew: Bool
    let leftHanded: Bool
    let showTuning: Bool
    let showNoteNames: Bool
    let onSave: (FretDiagram) -> Void

    init(diagram: FretDiagram, isNew: Bool, chart: ChordChart, onSave: @escaping (FretDiagram) -> Void) {
        _draft = State(initialValue: diagram)
        _tuningText = State(initialValue: diagram.tuning.joined(separator: " "))
        self.isNew = isNew
        self.leftHanded = chart.leftHanded
        self.showTuning = chart.showTuning
        self.showNoteNames = chart.showNoteNames
        self.onSave = onSave
    }

    private var selectedDotIndex: Int? {
        guard let selection else { return nil }
        return draft.dots.firstIndex { $0.id == selection }
    }

    private var selectedBarreIndex: Int? {
        guard let selection else { return nil }
        return draft.barres.firstIndex { $0.id == selection }
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                if geo.size.width > 760 {
                    HStack(spacing: 0) {
                        canvasArea
                            .frame(maxWidth: .infinity)
                        Divider()
                        inspector
                            .frame(width: 400)
                    }
                } else {
                    VStack(spacing: 0) {
                        canvasArea
                            .frame(height: geo.size.height * 0.52)
                        Divider()
                        inspector
                    }
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle(isNew ? "New Diagram" : "Edit Diagram")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isNew ? "Add" : "Done") {
                        onSave(draft)
                        dismiss()
                    }
                }
            }
            .confirmationDialog("Clear this diagram?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Clear Dots and Markers", role: .destructive) {
                    draft.dots = []
                    draft.barres = []
                    draft.marks = Array(repeating: .none, count: draft.stringCount)
                    selection = nil
                }
            }
        }
    }

    // MARK: Canvas

    private var canvasArea: some View {
        VStack(spacing: 14) {
            TextField("Chord name", text: $draft.name)
                .font(.system(size: 34, weight: .bold))
                .multilineTextAlignment(.center)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            GeometryReader { box in
                FretDiagramView(
                    diagram: draft,
                    leftHanded: leftHanded,
                    showTuning: true,
                    showNoteNames: showNoteNames,
                    selection: selection
                )
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onEnded { value in
                            handle(start: value.startLocation, end: value.location, size: box.size)
                        }
                )
            }
            .aspectRatio(FretDiagramView.aspectRatio(for: draft), contentMode: .fit)
            .padding(.horizontal, 24)
            .frame(maxWidth: draft.kind == .neck ? 1000 : 520, maxHeight: .infinity)

            Text(draft.kind == .neck
                 ? "Tap a fret to add a dot · tap a dot to select it, tap again to remove · tap left of the nut for open strings · drag across strings for a barre"
                 : "Tap a fret to add a dot · tap a dot to select it, tap again to remove · tap above the nut for open ○ / muted ✕ · drag across strings for a barre")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .padding(.vertical, 20)
    }

    private func handle(start: CGPoint, end: CGPoint, size: CGSize) {
        if draft.kind == .neck {
            handleNeck(start: start, end: end, size: size)
            return
        }
        let geometry = DiagramGeometry(
            size: size,
            strings: draft.stringCount,
            frets: draft.fretCount,
            leftHanded: leftHanded,
            hasBottomLabels: true
        )
        let first = geometry.hit(start)
        let last = geometry.hit(end)

        withAnimation(.snappy(duration: 0.15)) {
            switch (first, last) {
            case let (.cell(s1, r1), .cell(s2, r2)) where r1 == r2 && s1 != s2:
                addBarre(fret: draft.startFret + r1, from: s1, to: s2)
            case let (.cell(string, row), _):
                tap(string: string, fret: draft.startFret + row)
            case let (.marker(string), _):
                if draft.dots.contains(where: { $0.string == string && $0.fret == 0 }) {
                    tap(string: string, fret: 0)
                } else {
                    cycleMark(string)
                }
            default:
                selection = nil
            }
        }
    }

    private func handleNeck(start: CGPoint, end: CGPoint, size: CGSize) {
        let geometry = NeckGeometry(
            size: size,
            strings: draft.stringCount,
            startFret: draft.startFret,
            frets: draft.fretCount,
            leftHanded: leftHanded,
            showTuning: true
        )
        withAnimation(.snappy(duration: 0.15)) {
            if let first = geometry.hit(start), let last = geometry.hit(end),
               first.fret == last.fret, first.string != last.string, first.fret > 0 {
                addBarre(fret: first.fret, from: first.string, to: last.string)
            } else if let first = geometry.hit(start) {
                tap(string: first.string, fret: first.fret)
            } else {
                selection = nil
            }
        }
    }

    private func tap(string: Int, fret: Int) {
        if let index = draft.dots.firstIndex(where: { $0.string == string && $0.fret == fret }) {
            let dot = draft.dots[index]
            if selection == dot.id {
                draft.dots.remove(at: index)
                selection = nil
            } else {
                selection = dot.id
            }
            return
        }
        if let barre = draft.barres.first(where: { $0.fret == fret && $0.covers(string) }) {
            if selection == barre.id {
                draft.barres.removeAll { $0.id == barre.id }
                selection = nil
            } else {
                selection = barre.id
            }
            return
        }
        let dot = Dot(string: string, fret: fret)
        draft.dots.append(dot)
        if draft.mark(string) == .muted {
            draft.setMark(.none, for: string)
        }
        selection = dot.id
    }

    private func addBarre(fret: Int, from: Int, to: Int) {
        let barre = Barre(fret: fret, fromString: from, toString: to)
        draft.barres.removeAll { $0.fret == fret && ($0.covers(barre.fromString) || $0.covers(barre.toString) || barre.covers($0.fromString)) }
        draft.dots.removeAll { $0.fret == fret && barre.covers($0.string) && $0.label == "1" }
        draft.barres.append(barre)
        for string in barre.fromString...barre.toString where draft.mark(string) == .muted {
            draft.setMark(.none, for: string)
        }
        selection = barre.id
    }

    private func cycleMark(_ string: Int) {
        switch draft.mark(string) {
        case .none:
            draft.setMark(.open, for: string)
        case .open:
            draft.setMark(.muted, for: string)
            draft.dots.removeAll { $0.string == string }
        case .muted:
            draft.setMark(.none, for: string)
        }
        selection = nil
    }

    // MARK: Inspector

    private var inspector: some View {
        Form {
            if let index = selectedDotIndex {
                dotSection(index)
            } else if let index = selectedBarreIndex {
                barreSection(index)
            }

            chordSection
            fretboardSection
            scaleSection
            librarySection
        }
    }

    private var chordSection: some View {
        Section {
            let suggestions = ChordNamer.suggestions(for: draft)
            if !suggestions.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Looks like")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(suggestions, id: \.self) { name in
                                Button(name) { draft.name = name }
                                    .buttonStyle(.bordered)
                                    .tint(draft.name == name ? .accentColor : .secondary)
                            }
                        }
                    }
                }
            }
            TextField("Caption (optional), e.g. Verse · use pick", text: $draft.caption)
        } header: {
            Text("Chord")
        }
    }

    private func dotSection(_ index: Int) -> some View {
        let dot = draft.dots[index]
        let note = draft.noteName(string: dot.string, fret: dot.fret)

        return Section {
            VStack(alignment: .leading, spacing: 10) {
                labelRow(["", "1", "2", "3", "4", "T"], current: dot.label) { draft.dots[index].label = $0 }
                labelRow(["R", "♭3", "3", "5", "♭7", "7"], current: dot.label) { draft.dots[index].label = $0 }
                labelRow([note, "9", "11", "13"], current: dot.label) { draft.dots[index].label = $0 }
            }
            .padding(.vertical, 4)

            TextField("Custom label", text: Binding(
                get: { index < draft.dots.count ? draft.dots[index].label : "" },
                set: { if index < draft.dots.count { draft.dots[index].label = String($0.prefix(3)) } }
            ))

            Picker("Style", selection: Binding(
                get: { index < draft.dots.count ? draft.dots[index].style : .normal },
                set: { if index < draft.dots.count { draft.dots[index].style = $0 } }
            )) {
                ForEach(DotStyle.allCases) { style in
                    Text(style.label).tag(style)
                }
            }
            .pickerStyle(.segmented)

            Button("Remove Dot", role: .destructive) {
                draft.dots.remove(at: index)
                selection = nil
            }
        } header: {
            Text("Selected dot · fret \(dot.fret) · \(note)")
        }
    }

    private func barreSection(_ index: Int) -> some View {
        let barre = draft.barres[index]

        return Section {
            labelRow(["", "1", "2", "3", "4", "T"], current: barre.label) { draft.barres[index].label = $0 }
                .padding(.vertical, 4)
            Button("Remove Barre", role: .destructive) {
                draft.barres.remove(at: index)
                selection = nil
            }
        } header: {
            Text("Selected barre · fret \(barre.fret)")
        }
    }

    private func labelRow(_ labels: [String], current: String, set: @escaping (String) -> Void) -> some View {
        HStack(spacing: 6) {
            ForEach(labels, id: \.self) { label in
                Button {
                    set(label)
                } label: {
                    Text(label.isEmpty ? "–" : label)
                        .font(.subheadline.weight(.semibold))
                        .frame(minWidth: 28)
                }
                .buttonStyle(.bordered)
                .tint(current == label ? .accentColor : .secondary)
            }
        }
    }

    private var fretboardSection: some View {
        Section {
            Picker("View", selection: Binding(
                get: { draft.kind },
                set: { setKind($0) }
            )) {
                ForEach(DiagramKind.allCases) { kind in
                    Text(kind.label).tag(kind)
                }
            }
            .pickerStyle(.segmented)

            Menu {
                ForEach(Tunings.presets) { preset in
                    Button("\(preset.name) – \(preset.notes.joined(separator: " "))") {
                        applyTuning(preset.notes)
                    }
                }
            } label: {
                LabeledContent("Tuning", value: Tunings.name(for: draft.tuning))
            }

            TextField("Custom tuning, low → high, e.g. D A D G B E", text: $tuningText)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .onSubmit {
                    if let notes = NoteMath.parseTuning(tuningText) {
                        applyTuning(notes)
                    } else {
                        tuningText = draft.tuning.joined(separator: " ")
                    }
                }

            Stepper("Start at fret \(draft.startFret)", value: $draft.startFret, in: 1...24)
            Stepper("\(draft.fretCount) frets shown", value: $draft.fretCount, in: 3...(draft.kind == .neck ? 24 : 12))
            Toggle("Use flats (♭) for note names", isOn: $draft.preferFlats)
            Button("Fit to dots") {
                withAnimation { draft.fitWindow() }
            }
            .disabled(draft.dots.isEmpty && draft.barres.isEmpty)
        } header: {
            Text("Fretboard")
        } footer: {
            Text("\(draft.stringCount) strings. Press return after typing a custom tuning.")
        }
    }

    private var librarySection: some View {
        Section {
            Menu {
                ForEach(ShapePreset.common) { preset in
                    Button(preset.name) {
                        let id = draft.id
                        let caption = draft.caption
                        draft = preset.diagram
                        draft.id = id
                        draft.caption = caption
                        tuningText = draft.tuning.joined(separator: " ")
                        selection = nil
                    }
                }
            } label: {
                Label("Load a common chord shape", systemImage: "square.grid.3x3")
            }
            Button(role: .destructive) {
                confirmClear = true
            } label: {
                Label("Clear diagram", systemImage: "eraser")
            }
            .disabled(draft.isEmpty)
        } footer: {
            Text("Common shapes use standard tuning and include finger numbers.")
        }
    }

    private func setKind(_ kind: DiagramKind) {
        withAnimation {
            draft.kind = kind
            if kind == .neck && draft.fretCount < 12 {
                draft.fretCount = 12
            } else if kind == .box && draft.fretCount > 7 {
                draft.fretCount = 5
                draft.fitWindow()
            }
        }
    }

    private var scaleSection: some View {
        Section {
            Picker("Key", selection: $scaleRoot) {
                ForEach(0..<12, id: \.self) { pc in
                    Text(NoteMath.name(pc, flats: [1, 3, 8, 10].contains(pc))).tag(pc)
                }
            }
            Picker("Scale", selection: $scaleName) {
                ForEach(Scales.groups, id: \.self) { group in
                    Section(group) {
                        ForEach(Scales.all.filter { $0.group == group }) { scale in
                            Text(scale.name).tag(scale.name)
                        }
                    }
                }
            }
            Picker("Labels", selection: $scaleLabels) {
                ForEach(ScaleLabels.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            .pickerStyle(.segmented)

            Button {
                guard let scale = Scales.all.first(where: { $0.name == scaleName }) else { return }
                withAnimation {
                    draft.fill(scale: scale, root: scaleRoot, labels: scaleLabels)
                    selection = nil
                }
            } label: {
                Label("Fill frets \(draft.visibleFrets.lowerBound)–\(draft.visibleFrets.upperBound) with this scale", systemImage: "wand.and.stars")
            }

            Button {
                withAnimation {
                    draft.kind = .neck
                    draft.startFret = 1
                    draft.fretCount = 12
                }
            } label: {
                Label("Show whole neck (frets 0–12)", systemImage: "arrow.left.and.right")
            }
            .disabled(draft.kind == .neck && draft.startFret == 1 && draft.fretCount == 12)
        } header: {
            Text("Scale / arpeggio")
        } footer: {
            Text("Fills the visible frets – set the start fret and number of frets first (e.g. start at 5 with 4 frets for a box shape). Roots are drawn as squares.")
        }
    }

    private func applyTuning(_ notes: [String]) {
        draft.setTuning(notes)
        tuningText = notes.joined(separator: " ")
        selection = nil
    }
}
