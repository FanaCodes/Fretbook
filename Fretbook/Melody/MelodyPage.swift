import SwiftUI

/// Small drawn note symbol for the duration buttons.
struct NoteValueIcon: View {
    let value: NoteValue
    var isRest = false

    var body: some View {
        Canvas { context, size in
            let s = size.height / 5.2
            let x = size.width / 2 - s * 0.3
            let y = size.height - s * 1.1
            let ink = GraphicsContext.Shading.foreground
            if isRest {
                let label = Text(restSymbol).font(.system(size: size.height * 0.36, weight: .bold))
                context.draw(label, at: CGPoint(x: size.width / 2, y: size.height / 2))
                return
            }
            let oval = Path(ellipseIn: CGRect(x: -s * 0.62, y: -s * 0.42, width: s * 1.24, height: s * 0.84))
                .applying(CGAffineTransform(rotationAngle: -0.35).concatenating(CGAffineTransform(translationX: x, y: y)))
            if value.isFilled {
                context.fill(oval, with: ink)
            } else {
                context.stroke(oval, with: ink, lineWidth: s * 0.2)
            }
            guard value.hasStem else { return }
            let stemX = x + s * 0.56
            var stem = Path()
            stem.move(to: CGPoint(x: stemX, y: y))
            stem.addLine(to: CGPoint(x: stemX, y: y - s * 3.4))
            context.stroke(stem, with: ink, lineWidth: s * 0.16)
            for flag in 0..<value.flags {
                let top = y - s * 3.4 + CGFloat(flag) * s * 0.8
                var path = Path()
                path.move(to: CGPoint(x: stemX, y: top))
                path.addQuadCurve(to: CGPoint(x: stemX + s * 0.8, y: top + s * 1.8), control: CGPoint(x: stemX + s * 0.9, y: top + s * 0.6))
                context.stroke(path, with: ink, lineWidth: s * 0.22)
            }
        }
    }

    private var restSymbol: String {
        switch value {
        case .whole: return "R1"
        case .half: return "R½"
        case .quarter: return "R¼"
        case .eighth: return "R⅛"
        case .sixteenth: return "R16"
        }
    }
}

struct MelodyHeader: View {
    let melody: Melody
    var scale: CGFloat = 1

    var body: some View {
        VStack(spacing: 3 * scale) {
            Text(melody.title.isEmpty ? "Untitled" : melody.title)
                .font(.system(size: 22 * scale, weight: .bold))
            if !melody.subtitle.isEmpty {
                Text(melody.subtitle)
                    .font(.system(size: 12 * scale))
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text("♩ = \(melody.tempo)")
                    .font(.system(size: 11 * scale, weight: .semibold))
                Spacer()
                if melody.display.showsTab && melody.tuning != Tunings.standard {
                    Text("Tuning: \(Tunings.name(for: melody.tuning))")
                        .font(.system(size: 10 * scale))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// A simple melody writer: tap the staff to add notes, add lyrics and chords, see tab, play it back.
struct MelodyPage: View {
    @Binding var melody: Melody
    var onDelete: () -> Void

    @StateObject private var player = MelodyPlayer()
    @State private var selectedID: UUID?
    @State private var inputValue: NoteValue = .quarter
    @State private var inputDotted = false
    @State private var restMode = false
    @State private var preview: PDFFile?
    @State private var confirmDelete = false
    @FocusState private var lyricFocused: Bool

    private let s: CGFloat = 9

    private var selectedIndex: Int? {
        guard let selectedID else { return nil }
        return melody.notes.firstIndex { $0.id == selectedID }
    }

    var body: some View {
        GeometryReader { geo in
            let paperWidth = max(300, min(geo.size.width - 48, 900) - 48)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    settingsCard
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
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
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
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    selectedID = nil
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
        .onDisappear { player.stop() }
        .sheet(item: $preview) { file in
            PDFPreviewSheet(file: file)
        }
        .confirmationDialog("Delete this melody?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete Melody", role: .destructive, action: onDelete)
        }
    }

    // MARK: Settings

    private var timeBinding: Binding<String> {
        Binding(
            get: { "\(melody.beatsPerBar)/\(melody.beatUnit)" },
            set: { value in
                let parts = value.split(separator: "/").compactMap { Int($0) }
                if parts.count == 2 {
                    melody.beatsPerBar = parts[0]
                    melody.beatUnit = parts[1]
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
            if melody.display.showsTab {
                Menu {
                    ForEach(Tunings.presets.filter { $0.notes.count == 6 }) { preset in
                        Button("\(preset.name) – \(preset.notes.joined(separator: " "))") {
                            melody.tuning = preset.notes
                        }
                    }
                } label: {
                    Label("Tab tuning: \(Tunings.name(for: melody.tuning))", systemImage: "tuningfork")
                        .font(.subheadline)
                }
            }
        }
        .card()
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
                onTap: { system, point in handleTap(system: system, point: point) }
            )
            if melody.notes.isEmpty {
                Text("Pick a note length below, then tap the staff where the note should go. Tap a note to select it; use the arrows to change its pitch and the fields below to add lyrics or chords.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(24)
        .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
    }

    private func handleTap(system: ScoreSystem, point: CGPoint) {
        let metrics = ScoreMetrics(melody: melody, s: s)

        // Tap on (or right next to) a note selects it.
        if let nearest = system.notes.min(by: { abs($0.x - point.x) < abs($1.x - point.x) }),
           abs(nearest.x - point.x) < s * 1.1 {
            selectedID = melody.notes[nearest.index].id
            if metrics.hasLyrics && abs(point.y - metrics.lyricY) < s * 1.3 {
                lyricFocused = true
            }
            return
        }

        // Otherwise add a new note where the user tapped.
        let insertAt: Int
        if let before = system.notes.last(where: { $0.x < point.x }) {
            insertAt = before.index + 1
        } else {
            insertAt = min(system.firstNoteIndex, melody.notes.count)
        }

        var note = MelodyNote(step: 4, value: inputValue, isRest: restMode)
        note.dotted = inputDotted

        let stringCount = melody.tuning.count
        let tabTop = metrics.tabY(string: stringCount - 1, strings: stringCount)
        let onTab = metrics.showTab && point.y > tabTop - metrics.tabSpacing && (!metrics.showStaff || point.y > metrics.staffBottom + s * 2.5)
        if onTab {
            // Tab: nearest string, open string pitch (set the fret afterwards)
            let row = Int(((point.y - tabTop) / metrics.tabSpacing).rounded())
            let string = min(stringCount - 1, max(0, stringCount - 1 - row))
            setPitch(of: &note, string: string, fret: 0)
        } else if metrics.showStaff {
            note.step = min(18, max(-6, metrics.step(atY: point.y)))
        } else if let previous = melody.notes.last {
            note.step = previous.step
        }

        melody.notes.insert(note, at: insertAt)
        selectedID = note.id
        player.preview(note, keySignature: melody.keySignature)
    }

    private func setPitch(of note: inout MelodyNote, string: Int, fret: Int) {
        let open = MusicTheory.openStrings(melody.tuning)
        guard open.indices.contains(string) else { return }
        let spelled = MusicTheory.spell(midi: open[string] + fret + 12, keySignature: melody.keySignature)
        note.step = spelled.step
        note.accidental = spelled.accidental
        note.string = string
    }

    // MARK: Palette

    private func noteBinding<T>(_ keyPath: WritableKeyPath<MelodyNote, T>, default value: T) -> Binding<T> {
        Binding(
            get: { selectedIndex.map { melody.notes[$0][keyPath: keyPath] } ?? value },
            set: { newValue in
                if let index = selectedIndex { melody.notes[index][keyPath: keyPath] = newValue }
            }
        )
    }

    private var palette: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                ForEach(NoteValue.allCases) { value in
                    Button {
                        inputValue = value
                        if let index = selectedIndex { melody.notes[index].value = value }
                    } label: {
                        NoteValueIcon(value: value, isRest: restMode)
                            .frame(width: 26, height: 30)
                    }
                    .buttonStyle(.bordered)
                    .tint(inputValue == value ? .accentColor : .secondary)
                    .accessibilityLabel(value.label)
                }

                toggleButton("Dot", systemImage: "circle.fill", isOn: inputDotted) {
                    inputDotted.toggle()
                    if let index = selectedIndex { melody.notes[index].dotted = inputDotted }
                }
                toggleButton("Rest", systemImage: "pause", isOn: restMode) {
                    restMode.toggle()
                    if let index = selectedIndex { melody.notes[index].isRest = restMode }
                }

                Divider().frame(height: 30)

                ForEach([Accidental.sharp, .flat, .natural], id: \.self) { accidental in
                    Button(accidental.symbol) {
                        guard let index = selectedIndex else { return }
                        melody.notes[index].accidental = melody.notes[index].accidental == accidental ? .none : accidental
                        melody.notes[index].string = nil
                        player.preview(melody.notes[index], keySignature: melody.keySignature)
                    }
                    .font(.title3)
                    .buttonStyle(.bordered)
                    .tint(selectedIndex.map { melody.notes[$0].accidental == accidental } == true ? .accentColor : .secondary)
                    .disabled(selectedIndex == nil)
                }

                Divider().frame(height: 30)

                iconButton("arrow.up") { movePitch(1) }
                iconButton("arrow.down") { movePitch(-1) }
                iconButton("chevron.left") { moveSelection(-1) }
                iconButton("chevron.right") { moveSelection(1) }
                iconButton("delete.left") { deleteSelected() }
                    .tint(.red)
            }
            .disabled(player.isPlaying)

            if let index = selectedIndex {
                selectedNoteRow(index)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    private func selectedNoteRow(_ index: Int) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "text.quote")
                .foregroundStyle(.secondary)
            TextField("Lyric (syllable)", text: noteBinding(\.lyric, default: ""))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($lyricFocused)
                .submitLabel(.next)
                .onSubmit {
                    moveSelection(1, skipRests: true)
                    lyricFocused = true
                }
                .frame(maxWidth: 220)
            Image(systemName: "music.note.list")
                .foregroundStyle(.secondary)
            TextField("Chord", text: noteBinding(\.chord, default: ""))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .frame(maxWidth: 100)

            if melody.display.showsTab && !melody.notes[index].isRest {
                tabControls(index)
            }
            Spacer()
        }
        .textFieldStyle(.roundedBorder)
    }

    private func tabControls(_ index: Int) -> some View {
        let note = melody.notes[index]
        let position = MusicTheory.tabPositions(for: melody)[note.id]
        let strings = melody.tuning.count

        return HStack(spacing: 8) {
            Menu {
                Button("Automatic") { melody.notes[index].string = nil }
                ForEach((0..<strings).reversed(), id: \.self) { string in
                    Button("String \(strings - string) (\(melody.tuning[string]))") {
                        if let fret = position.map({ MusicTheory.openStrings(melody.tuning)[$0.string] + $0.fret - MusicTheory.openStrings(melody.tuning)[string] }), fret >= 0 {
                            melody.notes[index].string = string
                        } else {
                            setPitch(of: &melody.notes[index], string: string, fret: 0)
                        }
                    }
                }
            } label: {
                Label(position.map { "String \(strings - $0.string)" } ?? "String", systemImage: "line.3.horizontal")
            }
            Stepper(position.map { "Fret \($0.fret)" } ?? "Fret –", onIncrement: {
                guard let position else { return }
                setPitch(of: &melody.notes[index], string: position.string, fret: min(24, position.fret + 1))
                player.preview(melody.notes[index], keySignature: melody.keySignature)
            }, onDecrement: {
                guard let position else { return }
                setPitch(of: &melody.notes[index], string: position.string, fret: max(0, position.fret - 1))
                player.preview(melody.notes[index], keySignature: melody.keySignature)
            })
            .fixedSize()
        }
    }

    private func toggleButton(_ title: String, systemImage: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.titleOnly)
                .font(.subheadline.weight(.semibold))
                .frame(minWidth: 34, minHeight: 30)
        }
        .buttonStyle(.bordered)
        .tint(isOn ? .accentColor : .secondary)
    }

    private func iconButton(_ systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(width: 26, height: 30)
        }
        .buttonStyle(.bordered)
        .disabled(selectedIndex == nil)
    }

    // MARK: Editing

    private func movePitch(_ delta: Int) {
        guard let index = selectedIndex, !melody.notes[index].isRest else { return }
        melody.notes[index].step = min(18, max(-6, melody.notes[index].step + delta))
        melody.notes[index].accidental = .none
        melody.notes[index].string = nil
        player.preview(melody.notes[index], keySignature: melody.keySignature)
    }

    private func moveSelection(_ delta: Int, skipRests: Bool = false) {
        guard !melody.notes.isEmpty else { return }
        var index = (selectedIndex ?? (delta > 0 ? -1 : melody.notes.count)) + delta
        while skipRests && melody.notes.indices.contains(index) && melody.notes[index].isRest {
            index += delta
        }
        guard melody.notes.indices.contains(index) else { return }
        selectedID = melody.notes[index].id
        let note = melody.notes[index]
        inputValue = note.value
        inputDotted = note.dotted
        restMode = note.isRest
    }

    private func deleteSelected() {
        guard let index = selectedIndex else { return }
        melody.notes.remove(at: index)
        if melody.notes.isEmpty {
            selectedID = nil
        } else {
            selectedID = melody.notes[max(0, index - 1)].id
        }
    }
}

// MARK: - PDF

enum MelodyPDF {
    @MainActor
    static func make(_ melody: Melody) -> URL? {
        let paper = PaperSize.regionalDefault
        let width = paper.size.width - PDFPaginator.margin * 2
        let s: CGFloat = 6.4
        let metrics = ScoreMetrics(melody: melody, s: s)
        let tab = MusicTheory.tabPositions(for: melody)
        let systems = ScoreLayout.layout(melody: melody, width: width, s: s)

        var blocks: [AnyView] = [AnyView(MelodyHeader(melody: melody))]
        for system in systems {
            blocks.append(AnyView(ScoreSystemView(melody: melody, system: system, metrics: metrics, tab: tab)))
        }
        return PDFPaginator.make(
            fileName: melody.title.isEmpty ? "Melody" : melody.title,
            paper: paper,
            footer: melody.title,
            blocks: blocks
        )
    }
}
