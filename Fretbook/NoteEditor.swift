import SwiftUI

struct NoteEditor: View {
    @Environment(\.dismiss) private var dismiss

    @State private var draft: NoteItem
    @State private var confirmDelete = false

    let isNew: Bool
    let onSave: (NoteItem) -> Void
    let onDelete: (() -> Void)?

    init(item: NoteItem, isNew: Bool, onSave: @escaping (NoteItem) -> Void, onDelete: (() -> Void)? = nil) {
        _draft = State(initialValue: item)
        self.isNew = isNew
        self.onSave = onSave
        self.onDelete = onDelete
    }

    private var category: NoteCategory { draft.category }

    private var bpmText: Binding<String> {
        Binding(
            get: { draft.bpm.map(String.init) ?? "" },
            set: { text in draft.bpm = Int(text.filter { $0.isASCII && $0.isNumber }) }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Category", selection: $draft.category) {
                        ForEach(NoteCategory.allCases) { category in
                            Label(category.label, systemImage: category.symbol).tag(category)
                        }
                    }
                    TextField(category.titlePrompt, text: $draft.title)
                        .font(.title3)
                    if category == .homework {
                        Toggle("Done", isOn: $draft.done)
                    }
                }

                if category.showsFrets || !draft.frets.isEmpty {
                    chordSection
                }
                if category.showsStrum || !draft.strum.isEmpty {
                    strumSection
                }
                if category.showsTab || !draft.tab.isEmpty {
                    tabSection
                }
                if category.showsKey || category.showsBPM || !draft.key.isEmpty || draft.bpm != nil {
                    detailsSection
                }

                Section("Notes") {
                    TextField("Anything else to remember…", text: $draft.body, axis: .vertical)
                        .lineLimit(3...12)
                }

                if onDelete != nil {
                    Section {
                        Button("Delete", role: .destructive) {
                            confirmDelete = true
                        }
                    }
                }
            }
            .navigationTitle(isNew ? "New \(category.label)" : category.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isNew ? "Add" : "Save") {
                        onSave(draft)
                        dismiss()
                    }
                    .disabled(draft.isEmpty)
                }
            }
            .confirmationDialog("Delete this note?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    onDelete?()
                    dismiss()
                }
            }
        }
    }

    // MARK: Chord

    private static let commonChords: [ChordPreset] = [
        ChordPreset(name: "C", frets: "x32010"), ChordPreset(name: "D", frets: "xx0232"), ChordPreset(name: "E", frets: "022100"), ChordPreset(name: "G", frets: "320003"), ChordPreset(name: "A", frets: "x02220"),
        ChordPreset(name: "Am", frets: "x02210"), ChordPreset(name: "Em", frets: "022000"), ChordPreset(name: "Dm", frets: "xx0231"), ChordPreset(name: "F", frets: "133211"), ChordPreset(name: "Bm", frets: "x24432"),
        ChordPreset(name: "A7", frets: "x02020"), ChordPreset(name: "B7", frets: "x21202"), ChordPreset(name: "C7", frets: "x32310"), ChordPreset(name: "D7", frets: "xx0212"), ChordPreset(name: "E7", frets: "020100"),
        ChordPreset(name: "G7", frets: "320001"), ChordPreset(name: "Fmaj7", frets: "xx3210"), ChordPreset(name: "Cadd9", frets: "x32030"), ChordPreset(name: "Asus2", frets: "x02200"), ChordPreset(name: "Dsus4", frets: "xx0233"),
    ]

    private var chordSection: some View {
        Section {
            TextField("Frets, low E → high e, e.g. x32010", text: $draft.frets)
                .font(.system(.body, design: .monospaced))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            if let shape = ChordShape(draft.frets) {
                HStack {
                    Spacer()
                    ChordDiagram(shape: shape)
                        .frame(width: 130, height: 150)
                    Spacer()
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Self.commonChords, id: \.name) { chord in
                        Button(chord.name) {
                            draft.frets = chord.frets
                            if draft.title.isEmpty || Self.commonChords.contains(where: { $0.name == draft.title }) {
                                draft.title = chord.name
                            }
                        }
                        .buttonStyle(.bordered)
                        .tint(NoteCategory.chord.color)
                    }
                }
            }
        } header: {
            Text("Chord shape")
        } footer: {
            Text("x = muted, 0 = open, numbers = fret. Use spaces when a fret is above 9, e.g. 8 10 10 9 8 8.")
        }
    }

    // MARK: Strum

    private static let commonStrums = ["D-D-D-D-", "DUDUDUDU", "D-DU-UDU", "D-xUD-xU", "D-DUDUDU"]

    private var strumSection: some View {
        Section {
            TextField("e.g. D-DU-UDU", text: $draft.strum)
                .font(.system(.body, design: .monospaced))
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()

            if !draft.strum.isEmpty {
                StrumView(pattern: draft.strum)
                    .padding(.vertical, 4)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Self.commonStrums, id: \.self) { pattern in
                        Button(pattern) { draft.strum = pattern }
                            .font(.system(.caption, design: .monospaced))
                            .buttonStyle(.bordered)
                            .tint(NoteCategory.rhythm.color)
                    }
                }
            }
        } header: {
            Text("Strumming pattern")
        } footer: {
            Text("D = down, U = up, - = rest (miss the strings), x = muted chuck. Eight symbols = eighth notes, sixteen = sixteenths.")
        }
    }

    // MARK: Tab

    private static let emptyStaff = ["e", "B", "G", "D", "A", "E"]
        .map { "\($0)|----------------|" }
        .joined(separator: "\n")

    private var tabSection: some View {
        Section {
            TextEditor(text: $draft.tab)
                .font(.system(.callout, design: .monospaced))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .frame(minHeight: 150)

            Button {
                draft.tab += (draft.tab.isEmpty ? "" : "\n\n") + Self.emptyStaff
            } label: {
                Label("Insert empty staff", systemImage: "plus.rectangle.on.rectangle")
            }
            .buttonStyle(.borderless)
        } header: {
            Text("Tab")
        } footer: {
            Text("Replace a dash with the fret number (delete one dash per digit) to keep the strings lined up.")
        }
    }

    // MARK: Key / tempo

    private var detailsSection: some View {
        Section("Details") {
            if category.showsKey || !draft.key.isEmpty {
                LabeledContent("Key") {
                    TextField("e.g. G major", text: $draft.key)
                        .multilineTextAlignment(.trailing)
                }
            }
            if category.showsBPM || draft.bpm != nil {
                LabeledContent("Tempo (BPM)") {
                    TextField("e.g. 80", text: bpmText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
    }
}

struct ChordPreset {
    let name: String
    let frets: String
}
