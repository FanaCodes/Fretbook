import SwiftUI
import UIKit

enum SongMode: String, CaseIterable, Identifiable {
    case text, chords, preview

    var id: String { rawValue }

    var label: String {
        switch self {
        case .text: return "Lyrics"
        case .chords: return "Place Chords"
        case .preview: return "Preview"
        }
    }
}

struct ChordEditTarget: Identifiable {
    let id = UUID()
    let line: Int
    let position: Int
    let chordIndex: Int?
    let context: String
    let current: String?
}

/// Write a lyrics sheet, place chords on syllables, preview and print it.
struct SongSheetPage: View {
    @Binding var song: SongSheet
    var onDelete: () -> Void

    @State private var mode: SongMode = .preview
    @State private var chordTarget: ChordEditTarget?
    @State private var voicing: DiagramTarget?
    @State private var preview: PDFFile?
    @State private var confirmDelete = false

    private var screenFont: CGFloat { CGFloat(song.fontSize) * 1.3 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                detailsCard

                Picker("Mode", selection: $mode) {
                    ForEach(SongMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                switch mode {
                case .text: textEditor
                case .chords: chordPlacer
                case .preview: sheetPreview
                }
            }
            .padding(24)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(song.title.isEmpty ? "Song" : song.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if song.text.isEmpty { mode = .text }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    preview = SongPDF.make(song).map(PDFFile.init)
                } label: {
                    Label("Print / PDF", systemImage: "printer")
                }
                .disabled(song.text.isEmpty)
            }
            ToolbarItem(placement: .secondaryAction) {
                Button(role: .destructive) {
                    confirmDelete = true
                } label: {
                    Label("Delete Song", systemImage: "trash")
                }
            }
        }
        .sheet(item: $chordTarget) { target in
            ChordPlacementSheet(
                target: target,
                songChords: song.uniqueChords,
                onApply: { apply($0, to: target) },
                onRemove: target.chordIndex == nil ? nil : { removeChord(target) },
                onMove: target.chordIndex == nil ? nil : { moveChord(target, by: $0) }
            )
            .presentationDetents([.medium, .large])
        }
        .fullScreenCover(item: $voicing) { target in
            DiagramEditor(diagram: target.diagram, isNew: false, chart: ChordChart()) { saved in
                song.customDiagrams.removeAll { ChordNames.normalize($0.name) == ChordNames.normalize(target.diagram.name) }
                var custom = saved
                custom.name = target.diagram.name
                song.customDiagrams.append(custom)
            }
        }
        .sheet(item: $preview) { file in
            PDFPreviewSheet(file: file)
        }
        .confirmationDialog("Delete this song sheet?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete Song", role: .destructive, action: onDelete)
        }
    }

    // MARK: Details

    private var tempoText: Binding<String> {
        Binding(
            get: { song.tempo.map(String.init) ?? "" },
            set: { text in song.tempo = Int(text.filter { $0.isASCII && $0.isNumber }) }
        )
    }

    private var detailsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            TextField("Song title", text: $song.title)
                .font(.title.bold())
            TextField("Artist", text: $song.artist)
                .foregroundStyle(.secondary)

            Divider()

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 18) { detailControls }
                VStack(alignment: .leading, spacing: 12) { detailControls }
            }

            HStack(spacing: 18) {
                Toggle("Chord diagrams", isOn: $song.showDiagrams)
                if song.showDiagrams {
                    Picker("Diagrams", selection: $song.diagramsAtTop) {
                        Text("At top").tag(true)
                        Text("At bottom").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 200)
                }
                Spacer()
                Text("Text size")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Slider(value: $song.fontSize, in: 10...20, step: 1)
                    .frame(maxWidth: 160)
            }
            .toggleStyle(.button)
        }
        .card()
    }

    @ViewBuilder
    private var detailControls: some View {
        HStack(spacing: 6) {
            Text("Key")
                .foregroundStyle(.secondary)
            TextField("e.g. G", text: $song.key)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .frame(width: 60)
        }
        Stepper(song.capo == 0 ? "No capo" : "Capo \(song.capo)", value: $song.capo, in: 0...12)
            .fixedSize()
        HStack(spacing: 6) {
            Text("♩ =")
                .foregroundStyle(.secondary)
            TextField("BPM", text: tempoText)
                .keyboardType(.numberPad)
                .frame(width: 50)
        }
        HStack(spacing: 6) {
            Text("Transpose")
                .foregroundStyle(.secondary)
            Button {
                withAnimation { song.transpose(by: -1) }
            } label: {
                Image(systemName: "minus")
            }
            Button {
                withAnimation { song.transpose(by: 1) }
            } label: {
                Image(systemName: "plus")
            }
        }
        .buttonStyle(.bordered)
        .disabled(song.uniqueChords.isEmpty)
    }

    // MARK: Lyrics text

    private var textEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Button {
                    pasteLyrics()
                } label: {
                    Label("Paste Lyrics", systemImage: "doc.on.clipboard")
                }
                .buttonStyle(.borderedProminent)

                if ChordSheetImport.hasChordRows(song.text) {
                    Button {
                        withAnimation { song.text = ChordSheetImport.convert(song.text) }
                    } label: {
                        Label("Convert chords above lyrics", systemImage: "arrow.down.to.line")
                    }
                    .buttonStyle(.bordered)
                }
                Spacer()
            }

            TextEditor(text: $song.text)
                .font(.system(size: 16, design: .monospaced))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .scrollContentBackground(.hidden)
                .padding(10)
                .frame(minHeight: 460)
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text("• Paste or type the lyrics, then switch to **Place Chords** and tap the words.")
                Text("• Chords can also be typed in brackets: `[Am]Hello [G]darkness`.")
                Text("• Section titles: start a line with `#`, e.g. `# Chorus` (or `[Verse 1]`).")
                Text("• Sheets copied from chord websites (chords on the line above) are converted automatically when you paste.")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }

    private func pasteLyrics() {
        guard let pasted = UIPasteboard.general.string, !pasted.isEmpty else { return }
        var text = pasted.replacingOccurrences(of: "\r\n", with: "\n")
        if ChordSheetImport.hasChordRows(text) {
            text = ChordSheetImport.convert(text)
        }
        withAnimation {
            song.text = song.text.isEmpty ? text : song.text + "\n\n" + text
        }
    }

    // MARK: Placing chords

    private var entries: [(index: Int, kind: SongLineKind)] {
        song.lineKinds.enumerated().map { (index: $0.offset, kind: $0.element) }
    }

    private var chordPlacer: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Tap a word to put a chord on it · tap a chord to change, move or remove it · ⊕ adds a chord at the end of a line")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if song.text.isEmpty {
                Text("Add lyrics first.")
                    .foregroundStyle(.secondary)
                    .card()
            } else {
                SongLinesView(
                    entries: entries,
                    fontSize: screenFont,
                    interactive: true,
                    onTapWord: { line, position in tapWord(line: line, position: position) },
                    onTapChord: { line, index in tapChord(line: line, index: index) }
                )
                .padding(22)
                .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 8))
                .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
            }
        }
    }

    private func tapWord(line: Int, position: Int) {
        let raw = song.rawLines.indices.contains(line) ? song.rawLines[line] : ""
        let parsed = ChordLine(parsing: raw)
        let characters = Array(parsed.plain)
        var end = position
        while end < characters.count && !characters[end].isWhitespace { end += 1 }
        let word = position < characters.count ? String(characters[position..<end]) : "end of line"
        let existing = parsed.chords.firstIndex { $0.position == position }
        chordTarget = ChordEditTarget(
            line: line,
            position: position,
            chordIndex: existing,
            context: word,
            current: existing.map { parsed.chords[$0].name }
        )
    }

    private func tapChord(line: Int, index: Int) {
        let raw = song.rawLines.indices.contains(line) ? song.rawLines[line] : ""
        let parsed = ChordLine(parsing: raw)
        guard parsed.chords.indices.contains(index) else { return }
        let chord = parsed.chords[index]
        let characters = Array(parsed.plain)
        var start = min(chord.position, characters.count)
        while start > 0 && !characters[start - 1].isWhitespace { start -= 1 }
        var end = min(chord.position, characters.count)
        while end < characters.count && !characters[end].isWhitespace { end += 1 }
        chordTarget = ChordEditTarget(
            line: line,
            position: chord.position,
            chordIndex: index,
            context: start < end ? String(characters[start..<end]) : "end of line",
            current: chord.name
        )
    }

    private func updateLine(_ index: Int, _ change: (inout ChordLine) -> Void) {
        var lines = song.rawLines
        guard lines.indices.contains(index) else { return }
        var line = ChordLine(parsing: lines[index])
        change(&line)
        lines[index] = line.serialized()
        song.text = lines.joined(separator: "\n")
    }

    private func apply(_ name: String, to target: ChordEditTarget) {
        updateLine(target.line) { line in
            if let index = target.chordIndex, line.chords.indices.contains(index) {
                line.chords[index].name = name
            } else if let index = line.chords.firstIndex(where: { $0.position == target.position }) {
                line.chords[index].name = name
            } else {
                line.chords.append(PlacedChord(position: target.position, name: name))
            }
        }
    }

    private func removeChord(_ target: ChordEditTarget) {
        guard let index = target.chordIndex else { return }
        updateLine(target.line) { line in
            if line.chords.indices.contains(index) { line.chords.remove(at: index) }
        }
    }

    private func moveChord(_ target: ChordEditTarget, by delta: Int) {
        guard let index = target.chordIndex else { return }
        updateLine(target.line) { line in
            guard line.chords.indices.contains(index) else { return }
            let moved = line.chords[index].position + delta
            line.chords[index].position = min(max(0, moved), line.plain.count)
        }
    }

    // MARK: Preview

    private var sheetPreview: some View {
        VStack(alignment: .leading, spacing: 18) {
            SongHeaderView(song: song, scale: 1.2)
            if song.showDiagrams && song.diagramsAtTop && !song.uniqueChords.isEmpty {
                diagrams
            }
            SongLinesView(entries: entries, fontSize: screenFont)
            if song.showDiagrams && !song.diagramsAtTop && !song.uniqueChords.isEmpty {
                diagrams
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
    }

    private var diagrams: some View {
        VStack(alignment: .leading, spacing: 6) {
            ChordDiagramStrip(song: song, cardWidth: 74) { name in
                if let diagram = song.diagram(for: name) {
                    voicing = DiagramTarget(diagram: diagram, isNew: false)
                }
            }
            Text("Tap a diagram to choose a different voicing.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}

// MARK: - Chord picker

struct ChordPlacementSheet: View {
    @Environment(\.dismiss) private var dismiss

    let target: ChordEditTarget
    let songChords: [String]
    let onApply: (String) -> Void
    let onRemove: (() -> Void)?
    let onMove: ((Int) -> Void)?

    @State private var root = "C"
    @State private var quality = ""
    @State private var custom = ""

    private static let roots = ["C", "C#", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B"]
    private static let qualities = ["", "m", "7", "m7", "maj7", "sus2", "sus4", "add9", "dim", "5"]

    init(target: ChordEditTarget, songChords: [String], onApply: @escaping (String) -> Void,
         onRemove: (() -> Void)?, onMove: ((Int) -> Void)?) {
        self.target = target
        self.songChords = songChords
        self.onApply = onApply
        self.onRemove = onRemove
        self.onMove = onMove
        if let current = target.current, let parts = ChordNames.split(current) {
            _root = State(initialValue: parts.root)
            _quality = State(initialValue: parts.quality)
            _custom = State(initialValue: current)
        }
    }

    private func use(_ name: String) {
        onApply(name)
        dismiss()
    }

    var body: some View {
        NavigationStack {
            Form {
                if !songChords.isEmpty {
                    Section("In this song") {
                        chips(songChords) { use($0) }
                    }
                }

                Section("Build a chord") {
                    chips(Self.roots, selected: root) { root = $0 }
                    chips(Self.qualities.map { $0.isEmpty ? "maj" : $0 }, selected: quality.isEmpty ? "maj" : quality) {
                        quality = $0 == "maj" ? "" : $0
                    }
                    Button {
                        use(root + quality)
                    } label: {
                        Label("Use \(root + quality)", systemImage: "checkmark.circle.fill")
                            .font(.headline)
                    }
                }

                Section("Any other chord") {
                    HStack {
                        TextField("e.g. C/G, F#m7b5, Gm(maj7)", text: $custom)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .onSubmit { if ChordNames.isChord(custom) { use(custom) } }
                        Button("Use") { use(custom) }
                            .disabled(!ChordNames.isChord(custom))
                    }
                }

                if onMove != nil || onRemove != nil {
                    Section {
                        if let onMove {
                            HStack {
                                Button {
                                    onMove(-1)
                                } label: {
                                    Label("One letter left", systemImage: "arrow.left")
                                }
                                .buttonStyle(.bordered)
                                Spacer()
                                Button {
                                    onMove(1)
                                } label: {
                                    Label("One letter right", systemImage: "arrow.right")
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        if let onRemove {
                            Button("Remove Chord", role: .destructive) {
                                onRemove()
                                dismiss()
                            }
                        }
                    } footer: {
                        Text("Moving keeps this sheet open so you can nudge it to the exact syllable.")
                    }
                }
            }
            .navigationTitle(target.current.map { "Change \($0) on “\(target.context)”" } ?? "Chord on “\(target.context)”")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func chips(_ names: [String], selected: String? = nil, action: @escaping (String) -> Void) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(names, id: \.self) { name in
                    Button(name) { action(name) }
                        .font(.subheadline.weight(.semibold))
                        .buttonStyle(.bordered)
                        .tint(name == selected ? .accentColor : .secondary)
                }
            }
            .padding(.vertical, 2)
        }
    }
}

// MARK: - PDF

enum SongPDF {
    @MainActor
    static func make(_ song: SongSheet) -> URL? {
        let fontSize = CGFloat(song.fontSize)
        var blocks: [AnyView] = [AnyView(SongHeaderView(song: song))]

        let diagrams = AnyView(ChordDiagramStrip(song: song, cardWidth: 50))
        let showDiagrams = song.showDiagrams && !song.uniqueChords.isEmpty
        if showDiagrams && song.diagramsAtTop {
            blocks.append(diagrams)
        }

        // Keep each stanza (lines between blank lines / section titles) together on a page.
        var group: [(index: Int, kind: SongLineKind)] = []
        func flush() {
            guard !group.isEmpty else { return }
            blocks.append(AnyView(SongLinesView(entries: group, fontSize: fontSize, chordColor: .black)))
            group = []
        }
        for (index, kind) in song.lineKinds.enumerated() {
            switch kind {
            case .blank:
                flush()
            case .section:
                flush()
                group.append((index, kind))
            case .lyric:
                group.append((index, kind))
            }
        }
        flush()

        if showDiagrams && !song.diagramsAtTop {
            blocks.append(diagrams)
        }

        let footer = [song.title, song.artist].filter { !$0.isEmpty }.joined(separator: " – ")
        return PDFPaginator.make(
            fileName: footer.isEmpty ? "Song" : footer,
            paper: .regionalDefault,
            footer: footer,
            blocks: blocks
        )
    }
}
