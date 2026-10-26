import SwiftUI

private struct NoteDrag {
    let id: UUID
    let startStep: Int
}

/// Melody writer: type the lyrics, then give each syllable its note with the piano,
/// the fretboard or by tapping the staff.
struct MelodyPage: View {
    @Binding var melody: Melody
    var onDelete: () -> Void

    @StateObject private var player = MelodyPlayer()
    @AppStorage("melodyZoom") private var zoom = 10.0
    @AppStorage("melodyInputPanel") private var panel: InputPanel = .piano

    @State private var selectedID: UUID?
    @State private var inputValue: NoteValue = .quarter
    @State private var inputDotted = false
    @State private var inputTriplet = false
    @State private var keyboardOctave = 4
    @State private var undoStack: [Melody] = []
    @State private var redoStack: [Melody] = []
    @State private var clipboard: [MelodyNote] = []
    @State private var drag: NoteDrag?
    @State private var preview: PDFFile?
    @State private var confirmDelete = false

    private var s: CGFloat { CGFloat(zoom) }

    private var selectedIndex: Int? {
        guard let selectedID else { return nil }
        return melody.notes.firstIndex { $0.id == selectedID }
    }

    var body: some View {
        GeometryReader { geo in
            let paperWidth = max(300, min(geo.size.width - 48, 1000) - 48)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    settingsCard
                    lyricsCard
                    scoreCard(width: paperWidth)
                }
                .padding(24)
                .frame(maxWidth: .infinity)
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .safeAreaInset(edge: .bottom) { palette }
        .navigationTitle(melody.title.isEmpty ? "Melody" : melody.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .onAppear(perform: migrateNoteLyrics)
        .onDisappear { player.stop() }
        .sheet(item: $preview) { file in
            PDFPreviewSheet(file: file)
        }
        .confirmationDialog("Delete this melody?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete Melody", role: .destructive, action: onDelete)
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                undo()
            } label: {
                Label("Undo", systemImage: "arrow.uturn.backward")
            }
            .disabled(undoStack.isEmpty)
            Button {
                redo()
            } label: {
                Label("Redo", systemImage: "arrow.uturn.forward")
            }
            .disabled(redoStack.isEmpty)
            Button {
                if player.isPlaying {
                    player.stop()
                } else {
                    player.play(melody, from: selectedIndex ?? 0)
                }
            } label: {
                Label(player.isPlaying ? "Stop" : "Play", systemImage: player.isPlaying ? "stop.fill" : "play.fill")
            }
            .disabled(melody.notes.isEmpty)
            Button {
                preview = MelodyPDF.make(melody).map(PDFFile.init)
            } label: {
                Label("Print / PDF", systemImage: "printer")
            }
            .disabled(melody.notes.isEmpty)
        }
        ToolbarItem(placement: .secondaryAction) {
            Button(role: .destructive) {
                confirmDelete = true
            } label: {
                Label("Delete Melody", systemImage: "trash")
            }
        }
    }

    // MARK: Settings

    private var timeBinding: Binding<String> {
        Binding(
            get: { "\(melody.beatsPerBar)/\(melody.beatUnit)" },
            set: { value in
                let parts = value.split(separator: "/").compactMap { Int($0) }
                if parts.count == 2 {
                    commit {
                        $0.beatsPerBar = parts[0]
                        $0.beatUnit = parts[1]
                    }
                }
            }
        )
    }

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Title", text: $melody.title)
                .font(.title.bold())
            TextField("Subtitle (optional)", text: $melody.subtitle)
                .foregroundStyle(.secondary)
            Divider()
            HStack(spacing: 16) {
                Picker("Key", selection: $melody.keySignature) {
                    ForEach(MusicTheory.keys, id: \.signature) { key in
                        Text(key.name).tag(key.signature)
                    }
                }
                .pickerStyle(.menu)

                Picker("Time", selection: timeBinding) {
                    ForEach(MusicTheory.times.indices, id: \.self) { index in
                        let time = MusicTheory.times[index]
                        Text("\(time.beats)/\(time.unit)").tag("\(time.beats)/\(time.unit)")
                    }
                }
                .pickerStyle(.menu)

                Stepper("♩ = \(melody.tempo)", value: $melody.tempo, in: 30...240, step: 5)
                    .fixedSize()

                Spacer()

                Picker("Show", selection: $melody.display) {
                    ForEach(ScoreDisplay.allCases) { display in
                        Text(display.label).tag(display)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 280)
            }
            HStack(spacing: 12) {
                Image(systemName: "minus.magnifyingglass")
                    .foregroundStyle(.secondary)
                Slider(value: $zoom, in: 7...16, step: 0.5)
                    .frame(maxWidth: 220)
                Image(systemName: "plus.magnifyingglass")
                    .foregroundStyle(.secondary)
                Spacer()
                if melody.display.showsTab {
                    Menu {
                        ForEach(Tunings.presets.filter { $0.notes.count == 6 }) { preset in
                            Button("\(preset.name) – \(preset.notes.joined(separator: " "))") {
                                commit { $0.tuning = preset.notes }
                            }
                        }
                    } label: {
                        Label("Tab tuning: \(Tunings.name(for: melody.tuning))", systemImage: "tuningfork")
                            .font(.subheadline)
                    }
                }
            }
        }
        .card()
    }

    // MARK: Lyrics

    private var lyricsCard: some View {
        let assignment = melody.lyricAssignment
        let syllables = melody.syllables

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Lyrics", systemImage: "text.quote")
                    .font(.headline)
                Spacer()
                Button {
                    commit { $0.lyrics = MusicTheory.hyphenate($0.lyrics) }
                } label: {
                    Label("Split into syllables", systemImage: "scissors")
                }
                .buttonStyle(.bordered)
                .disabled(melody.lyrics.isEmpty)
            }

            TextEditor(text: $melody.lyrics)
                .font(.body)
                .autocorrectionDisabled()
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(minHeight: 70, maxHeight: 130)
                .background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))

            if syllables.isEmpty {
                Text("Type or paste the lyrics, split syllables with hyphens (hap-py birth-day). Every note you enter then sings the next syllable. Use **Hold** for one syllable over several notes.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                WrapLayout(spacing: 4, lineSpacing: 4) {
                    ForEach(Array(syllables.enumerated()), id: \.offset) { entry in
                        let used = entry.offset < assignment.used
                        let isNext = entry.offset == assignment.used
                        Text(entry.element.text + (entry.element.continues ? " -" : ""))
                            .font(.subheadline.weight(isNext ? .bold : .regular))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .foregroundStyle(isNext ? Color.white : (used ? Color.accentColor : Color.secondary))
                            .background(
                                isNext ? Color.accentColor : (used ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.1)),
                                in: Capsule()
                            )
                            .onTapGesture { selectSyllable(entry.offset) }
                    }
                }
                Text(assignment.used < assignment.total
                     ? "Next note sings “\(syllables[assignment.used].text)” · \(assignment.total - assignment.used) syllables left"
                     : "All syllables have notes.")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .card()
    }

    private func selectSyllable(_ index: Int) {
        let assignment = melody.lyricAssignment.map
        var count = 0
        for note in melody.notes where assignment[note.id] != nil {
            if count == index {
                selectedID = note.id
                return
            }
            count += 1
        }
        // Not sung yet: select the last note so the next entry gets this syllable.
        selectedID = melody.notes.last?.id
    }

    /// Older melodies stored a lyric per note; move them into the lyrics text once.
    private func migrateNoteLyrics() {
        guard melody.lyrics.isEmpty, melody.notes.contains(where: { !$0.lyric.isEmpty }) else { return }
        let words = melody.notes.compactMap { $0.lyric.isEmpty ? nil : $0.lyric }
        melody.lyrics = words.joined(separator: " ")
        for index in melody.notes.indices { melody.notes[index].lyric = "" }
    }

    // MARK: Score

    private func scoreCard(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            MelodyHeader(melody: melody, scale: 1.1)
            ScoreView(
                melody: melody,
                width: width,
                s: s,
                selected: selectedID,
                playing: player.playing,
                onTap: { system, point in handleTap(system: system, point: point) },
                onDrag: { system, start, location, ended in handleDrag(system: system, start: start, location: location, ended: ended) }
            )
            if melody.notes.isEmpty {
                Text("Choose a note length below and play the notes on the piano or fretboard. They're added one after another, each with the next syllable. Long-press a note and drag up or down to change its pitch.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(24)
        .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
    }

    private func handleTap(system: ScoreSystem, point: CGPoint) {
        guard drag == nil else { return }
        let metrics = ScoreMetrics(melody: melody, s: s)

        if let nearest = system.notes.min(by: { abs($0.x - point.x) < abs($1.x - point.x) }),
           abs(nearest.x - point.x) < s * 1.1 {
            selectNote(melody.notes[nearest.index].id)
            return
        }
        guard panel == .staff else {
            selectedID = nil
            return
        }

        let insertAt: Int
        if let before = system.notes.last(where: { $0.x < point.x }) {
            insertAt = before.index + 1
        } else {
            insertAt = min(system.firstNoteIndex, melody.notes.count)
        }

        let stringCount = melody.tuning.count
        let tabTop = metrics.tabY(string: stringCount - 1, strings: stringCount)
        let onTab = metrics.showTab && point.y > tabTop - metrics.tabSpacing
            && (!metrics.showStaff || point.y > metrics.staffBottom + s * 2.5)
        if onTab {
            let row = Int(((point.y - tabTop) / metrics.tabSpacing).rounded())
            let string = min(stringCount - 1, max(0, stringCount - 1 - row))
            let open = MusicTheory.openStrings(melody.tuning)
            insertPitch(open[string] + 12, string: string, at: insertAt)
        } else {
            var note = newNote()
            note.step = min(18, max(-6, metrics.showStaff ? metrics.step(atY: point.y) : (melody.notes.last?.step ?? 6)))
            insert(note, at: insertAt)
        }
    }

    private func handleDrag(system: ScoreSystem, start: CGPoint, location: CGPoint, ended: Bool) {
        if drag == nil {
            guard let nearest = system.notes.min(by: { abs($0.x - start.x) < abs($1.x - start.x) }),
                  abs(nearest.x - start.x) < s * 1.4 else { return }
            let note = melody.notes[nearest.index]
            guard !note.isRest else { return }
            pushUndo()
            drag = NoteDrag(id: note.id, startStep: note.step)
            selectedID = note.id
            UISelectionFeedbackGenerator().selectionChanged()
        }
        guard let current = drag, let index = melody.notes.firstIndex(where: { $0.id == current.id }) else {
            if ended { drag = nil }
            return
        }
        let delta = Int(((start.y - location.y) / (s / 2)).rounded())
        let step = min(18, max(-6, current.startStep + delta))
        if melody.notes[index].step != step {
            melody.notes[index].step = step
            melody.notes[index].accidental = .none
            melody.notes[index].string = nil
            UISelectionFeedbackGenerator().selectionChanged()
            if let midi = melody.pitches[current.id] { player.preview(midi: midi) }
        }
        if ended {
            DispatchQueue.main.async { drag = nil }
        }
    }

    // MARK: Palette

    private var selectedSummary: String {
        guard let index = selectedIndex else { return "Nothing selected – new notes go at the end" }
        let note = melody.notes[index]
        var parts: [String] = []
        if note.isRest {
            parts.append("\(note.value.label) rest")
        } else {
            if let midi = melody.pitches[note.id] {
                parts.append(MusicTheory.noteName(midi: midi, keySignature: melody.keySignature))
            }
            parts.append(note.value.label.lowercased() + (note.dotted ? " dotted" : "") + (note.triplet ? " triplet" : ""))
            if let syllable = melody.lyricAssignment.map[note.id] {
                parts.append("“\(syllable.text)”")
            } else if note.holdsSyllable {
                parts.append("holds syllable")
            }
        }
        parts.append("bar \(melody.barNumbers[index] + 1)")
        return parts.joined(separator: " · ")
    }

    private var palette: some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(NoteValue.allCases) { value in
                        Button {
                            setValue(value)
                        } label: {
                            NoteValueIcon(value: value)
                                .frame(width: 26, height: 30)
                        }
                        .buttonStyle(.bordered)
                        .tint(inputValue == value ? .accentColor : .secondary)
                        .accessibilityLabel(value.label)
                    }
                    textButton("•", help: "Dotted", isOn: inputDotted) { toggleDot() }
                    textButton("3", help: "Triplet", isOn: inputTriplet) { toggleTriplet() }
                    textButton("Rest", help: "Add a rest") { addRest() }

                    Divider().frame(height: 30)

                    ForEach([Accidental.sharp, .flat, .natural], id: \.self) { accidental in
                        textButton(accidental.symbol, help: "Accidental",
                                   isOn: selectedIndex.map { melody.notes[$0].accidental == accidental } ?? false) {
                            toggleAccidental(accidental)
                        }
                        .disabled(selectedIndex == nil)
                    }
                    textButton("⁀", help: "Tie to next note", isOn: selectedIndex.map { melody.notes[$0].tie } ?? false) {
                        toggleFlag(\.tie)
                    }
                    .disabled(selectedIndex == nil)
                    textButton("Hold", help: "Keep singing the previous syllable",
                               isOn: selectedIndex.map { melody.notes[$0].holdsSyllable } ?? false) {
                        toggleFlag(\.holdsSyllable)
                    }
                    .disabled(selectedIndex == nil)

                    Divider().frame(height: 30)

                    iconButton("arrow.up") { movePitch(1) }
                    iconButton("arrow.down") { movePitch(-1) }
                    iconButton("chevron.left") { moveSelection(-1) }
                    iconButton("chevron.right") { moveSelection(1) }
                    iconButton("delete.left") { deleteSelected() }
                        .tint(.red)

                    Menu {
                        Button("Copy Note") { copyNote() }
                            .disabled(selectedIndex == nil)
                        Button("Copy Bar") { copyBar() }
                            .disabled(selectedIndex == nil)
                        Button("Paste \(clipboard.count) Note\(clipboard.count == 1 ? "" : "s")") { paste() }
                            .disabled(clipboard.isEmpty)
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .frame(width: 26, height: 30)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal, 16)
            }
            .disabled(player.isPlaying)

            HStack(spacing: 12) {
                Text(selectedSummary)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                if let index = selectedIndex, !melody.notes[index].isRest {
                    TextField("Chord", text: noteBinding(\.chord, default: ""))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 90)
                    if melody.display.showsTab {
                        tabControls(index)
                    }
                }
                Spacer()
                Picker("Input", selection: $panel) {
                    ForEach(InputPanel.allCases) { option in
                        Label(option.label, systemImage: option.symbol).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 300)
            }
            .padding(.horizontal, 16)

            inputPanel
                .padding(.horizontal, 16)
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    @ViewBuilder
    private var inputPanel: some View {
        switch panel {
        case .piano:
            HStack(spacing: 8) {
                VStack(spacing: 6) {
                    iconButton("chevron.up", enabled: keyboardOctave < 6) { keyboardOctave += 1 }
                    Text("Oct")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    iconButton("chevron.down", enabled: keyboardOctave > 3) { keyboardOctave -= 1 }
                }
                PianoKeyboard(
                    lowestOctave: keyboardOctave,
                    highlighted: selectedIndex.flatMap { melody.pitches[melody.notes[$0].id] }
                ) { midi in
                    insertPitch(midi)
                }
                .frame(height: 110)
            }
        case .fretboard:
            FretboardPad(
                tuning: melody.tuning,
                highlighted: selectedIndex.flatMap { MusicTheory.tabPositions(for: melody)[melody.notes[$0].id] }
            ) { string, fret in
                let open = MusicTheory.openStrings(melody.tuning)
                guard open.indices.contains(string) else { return }
                insertPitch(open[string] + fret + 12, string: string)
            }
        case .staff:
            Text("Tap the staff where a note should go (between notes inserts there). Tap a tab line to add a note on that string.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func tabControls(_ index: Int) -> some View {
        let note = melody.notes[index]
        let positions = MusicTheory.tabPositions(for: melody)
        let position = positions[note.id]
        let strings = melody.tuning.count

        return HStack(spacing: 8) {
            Menu {
                Button("Automatic") { commit { $0.notes[index].string = nil } }
                ForEach((0..<strings).reversed(), id: \.self) { string in
                    Button("String \(strings - string) (\(melody.tuning[string]))") {
                        commit { $0.notes[index].string = string }
                    }
                }
            } label: {
                Text(position.map { "String \(strings - $0.string)" } ?? "String")
            }
            Stepper(position.map { "Fret \($0.fret)" } ?? "Fret –", onIncrement: {
                guard let position else { return }
                setTab(index, string: position.string, fret: min(24, position.fret + 1))
            }, onDecrement: {
                guard let position else { return }
                setTab(index, string: position.string, fret: max(0, position.fret - 1))
            })
            .fixedSize()
        }
        .font(.subheadline)
    }

    private func textButton(_ title: String, help: String, isOn: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .frame(minWidth: 26, minHeight: 30)
        }
        .buttonStyle(.bordered)
        .tint(isOn ? .accentColor : .secondary)
        .accessibilityLabel(help)
    }

    private func iconButton(_ systemImage: String, enabled: Bool? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(width: 26, height: 30)
        }
        .buttonStyle(.bordered)
        .disabled(!(enabled ?? (selectedIndex != nil)))
    }

    private func noteBinding<T>(_ keyPath: WritableKeyPath<MelodyNote, T>, default value: T) -> Binding<T> {
        Binding(
            get: { selectedIndex.map { melody.notes[$0][keyPath: keyPath] } ?? value },
            set: { newValue in
                if let index = selectedIndex { melody.notes[index][keyPath: keyPath] = newValue }
            }
        )
    }

    // MARK: Editing (all changes go through `commit` so they can be undone)

    private func pushUndo() {
        undoStack.append(melody)
        if undoStack.count > 200 { undoStack.removeFirst() }
        redoStack.removeAll()
    }

    private func commit(_ change: (inout Melody) -> Void) {
        pushUndo()
        var copy = melody
        change(&copy)
        melody = copy
    }

    private func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(melody)
        melody = previous
        if selectedIndex == nil { selectedID = melody.notes.last?.id }
    }

    private func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(melody)
        melody = next
        if selectedIndex == nil { selectedID = melody.notes.last?.id }
    }

    private func newNote() -> MelodyNote {
        var note = MelodyNote(step: 4, value: inputValue)
        note.dotted = inputDotted
        note.triplet = inputTriplet
        return note
    }

    private func insert(_ note: MelodyNote, at index: Int? = nil) {
        let position = min(index ?? selectedIndex.map { $0 + 1 } ?? melody.notes.count, melody.notes.count)
        commit { $0.notes.insert(note, at: position) }
        selectedID = note.id
        if !note.isRest, let midi = melody.pitches[note.id] { player.preview(midi: midi) }
    }

    private func insertPitch(_ midi: Int, string: Int? = nil, at index: Int? = nil) {
        let position = min(index ?? selectedIndex.map { $0 + 1 } ?? melody.notes.count, melody.notes.count)
        let spelled = melody.spell(midi: midi, at: position)
        var note = newNote()
        note.step = min(18, max(-6, spelled.step))
        note.accidental = spelled.accidental
        note.string = string
        insert(note, at: position)
    }

    private func addRest() {
        var rest = newNote()
        rest.isRest = true
        insert(rest)
    }

    private func setValue(_ value: NoteValue) {
        inputValue = value
        if let index = selectedIndex { commit { $0.notes[index].value = value } }
    }

    private func toggleDot() {
        inputDotted.toggle()
        if let index = selectedIndex { commit { $0.notes[index].dotted = inputDotted } }
    }

    private func toggleTriplet() {
        inputTriplet.toggle()
        if let index = selectedIndex { commit { $0.notes[index].triplet = inputTriplet } }
    }

    private func toggleAccidental(_ accidental: Accidental) {
        guard let index = selectedIndex else { return }
        commit {
            $0.notes[index].accidental = $0.notes[index].accidental == accidental ? .none : accidental
            $0.notes[index].string = nil
        }
        if let midi = melody.pitches[melody.notes[index].id] { player.preview(midi: midi) }
    }

    private func toggleFlag(_ flag: WritableKeyPath<MelodyNote, Bool>) {
        guard let index = selectedIndex else { return }
        commit { $0.notes[index][keyPath: flag].toggle() }
    }

    private func setTab(_ index: Int, string: Int, fret: Int) {
        let open = MusicTheory.openStrings(melody.tuning)
        guard open.indices.contains(string) else { return }
        let spelled = melody.spell(midi: open[string] + fret + 12, at: index)
        commit {
            $0.notes[index].step = spelled.step
            $0.notes[index].accidental = spelled.accidental
            $0.notes[index].string = string
        }
        if let midi = melody.pitches[melody.notes[index].id] { player.preview(midi: midi) }
    }

    private func movePitch(_ delta: Int) {
        guard let index = selectedIndex, !melody.notes[index].isRest else { return }
        commit {
            $0.notes[index].step = min(18, max(-6, $0.notes[index].step + delta))
            $0.notes[index].accidental = .none
            $0.notes[index].string = nil
        }
        if let midi = melody.pitches[melody.notes[index].id] { player.preview(midi: midi) }
    }

    private func selectNote(_ id: UUID) {
        selectedID = id
        guard let note = melody.notes.first(where: { $0.id == id }) else { return }
        inputValue = note.value
        inputDotted = note.dotted
        inputTriplet = note.triplet
    }

    private func moveSelection(_ delta: Int) {
        guard !melody.notes.isEmpty else { return }
        let index = (selectedIndex ?? (delta > 0 ? -1 : melody.notes.count)) + delta
        guard melody.notes.indices.contains(index) else { return }
        selectNote(melody.notes[index].id)
    }

    private func deleteSelected() {
        guard let index = selectedIndex else { return }
        commit { $0.notes.remove(at: index) }
        selectedID = melody.notes.isEmpty ? nil : melody.notes[max(0, index - 1)].id
    }

    private func copyNote() {
        guard let index = selectedIndex else { return }
        clipboard = [melody.notes[index]]
    }

    private func copyBar() {
        guard let index = selectedIndex else { return }
        let bars = melody.barNumbers
        clipboard = melody.notes.enumerated().filter { bars[$0.offset] == bars[index] }.map(\.element)
    }

    private func paste() {
        guard !clipboard.isEmpty else { return }
        let position = min(selectedIndex.map { $0 + 1 } ?? melody.notes.count, melody.notes.count)
        let copies = clipboard.map { note -> MelodyNote in
            var copy = note
            copy.id = UUID()
            return copy
        }
        commit { $0.notes.insert(contentsOf: copies, at: position) }
        selectedID = copies.last?.id
    }
}
