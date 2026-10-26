import Foundation

/// Finds a guitar voicing for any chord name: open shapes from the library first,
/// otherwise a movable E-shape or A-shape barre chord at the lowest position.
enum ChordLibrary {
    private struct Template {
        let offsets: [Int?]     // relative to the root fret, low E → high e
        let fingers: String
    }

    /// Root on the 6th string.
    private static let eShapes: [String: Template] = [
        "": Template(offsets: [0, 2, 2, 1, 0, 0], fingers: "134211"),
        "m": Template(offsets: [0, 2, 2, 0, 0, 0], fingers: "134111"),
        "7": Template(offsets: [0, 2, 0, 1, 0, 0], fingers: "131211"),
        "m7": Template(offsets: [0, 2, 0, 0, 0, 0], fingers: "131111"),
        "sus4": Template(offsets: [0, 2, 2, 2, 0, 0], fingers: "123411"),
        "5": Template(offsets: [0, 2, 2, nil, nil, nil], fingers: "134---"),
    ]

    /// Root on the 5th string.
    private static let aShapes: [String: Template] = [
        "": Template(offsets: [nil, 0, 2, 2, 2, 0], fingers: "-13331"),
        "m": Template(offsets: [nil, 0, 2, 2, 1, 0], fingers: "-13421"),
        "7": Template(offsets: [nil, 0, 2, 0, 2, 0], fingers: "-13141"),
        "m7": Template(offsets: [nil, 0, 2, 0, 1, 0], fingers: "-13121"),
        "maj7": Template(offsets: [nil, 0, 2, 1, 2, 0], fingers: "-13241"),
        "sus2": Template(offsets: [nil, 0, 2, 2, 0, 0], fingers: "-13411"),
        "sus4": Template(offsets: [nil, 0, 2, 2, 3, 0], fingers: "-12341"),
        "6": Template(offsets: [nil, 0, 2, 2, 2, 2], fingers: "-13333"),
        "dim": Template(offsets: [nil, 0, 1, 2, 1, nil], fingers: "-1243-"),
        "m7b5": Template(offsets: [nil, 0, 1, 0, 1, nil], fingers: "-1213-"),
        "5": Template(offsets: [nil, 0, 2, 2, nil, nil], fingers: "-134--"),
    ]

    /// Maps spelling variants to the template keys above.
    private static func canonicalQuality(_ quality: String) -> String {
        switch quality {
        case "", "M", "maj": return ""
        case "m", "min", "-": return "m"
        case "M7", "Δ", "Δ7", "maj7": return "maj7"
        case "min7", "-7", "m7": return "m7"
        case "°", "dim", "o": return "dim"
        case "ø", "ø7", "m7b5", "m7(b5)", "min7b5": return "m7b5"
        case "sus": return "sus4"
        default: return quality
        }
    }

    static func diagram(for name: String) -> FretDiagram? {
        guard let parts = ChordNames.split(name), let root = NoteMath.pitchClass(parts.root) else { return nil }
        let quality = canonicalQuality(parts.quality)
        let base = ChordNames.normalize(parts.root + parts.quality)

        // 1. A known open/common shape with fingerings
        if let preset = ShapePreset.common.first(where: { ChordNames.normalize($0.name) == base }) {
            var diagram = preset.diagram
            diagram.name = name
            return diagram
        }

        // 2. Movable barre shapes, whichever sits lower on the neck
        var candidates: [(fret: Int, template: Template)] = []
        if let template = eShapes[quality] {
            let fret = (root - 4 + 12) % 12
            candidates.append((fret == 0 ? 12 : fret, template))
        }
        if let template = aShapes[quality] {
            let fret = (root - 9 + 12) % 12
            candidates.append((fret == 0 ? 12 : fret, template))
        }
        guard let best = candidates.min(by: { $0.fret < $1.fret }) else { return nil }

        let frets = best.template.offsets
            .map { offset in offset.map { String(best.fret + $0) } ?? "x" }
            .joined(separator: " ")
        var diagram = ShapePreset(name: name, frets: frets, fingers: best.template.fingers).diagram
        diagram.name = name
        return diagram
    }
}
