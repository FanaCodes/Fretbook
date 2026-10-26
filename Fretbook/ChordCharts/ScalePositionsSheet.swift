import SwiftUI

/// Generates the five classic positions of a scale, each on a full fretboard.
struct ScalePositionsSheet: View {
    @Environment(\.dismiss) private var dismiss

    let woodFretboard: Bool
    let onCreate: ([FretDiagram], String, String) -> Void

    @State private var root = 7
    @State private var scaleName = "Major"
    @State private var labels: ScaleLabels = .fingers
    @State private var length = 15

    private var scale: ScaleType? { Scales.all.first { $0.name == scaleName } }

    private var diagrams: [FretDiagram] {
        guard let scale else { return [] }
        return FretDiagram.scalePositions(scale: scale, root: root, labels: labels, neckLength: length)
    }

    private var keyName: String {
        let flats = diagrams.first?.preferFlats ?? false
        return NoteMath.name(root, flats: flats)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Key", selection: $root) {
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
                    Picker("Labels", selection: $labels) {
                        ForEach(ScaleLabels.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    Stepper("Fretboard: \(length) frets", value: $length, in: 12...22)
                } footer: {
                    Text("Creates 5 fretboards, one per position, laid out 5 per page so they fill an A4/Letter sheet. Roots are drawn as rings.")
                }

                Section("Preview") {
                    ForEach(diagrams) { diagram in
                        DiagramCard(diagram: diagram, showTuning: false, woodFretboard: woodFretboard, nameSize: 15)
                            .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("5 Scale Positions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let title = "The 5 \(keyName) \(scaleName) Positions"
                        let subtitle = labels == .fingers ? "Suggested fingerings · roots shown as rings" : "Roots shown as rings"
                        onCreate(diagrams, title, subtitle)
                        dismiss()
                    }
                    .disabled(diagrams.isEmpty)
                }
            }
        }
    }
}
