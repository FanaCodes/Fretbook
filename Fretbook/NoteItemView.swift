import SwiftUI

/// Read-only display of one note inside a lesson.
struct NoteItemView: View {
    let item: NoteItem
    var onToggleDone: (() -> Void)? = nil

    private var category: NoteCategory { item.category }
    private var isDone: Bool { category == .homework && item.done }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            CategoryBadge(category: category)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(item.title.isEmpty ? category.label : item.title)
                        .font(.headline)
                        .strikethrough(isDone)
                        .foregroundStyle(isDone ? Color.secondary : Color.primary)
                    Text(category.label.uppercased())
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(category.color)
                    Spacer(minLength: 0)
                    if category == .homework, let onToggleDone {
                        Button(action: onToggleDone) {
                            Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundStyle(item.done ? Color.green : category.color)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if !item.key.isEmpty || item.bpm != nil {
                    HStack(spacing: 6) {
                        if !item.key.isEmpty {
                            Chip(text: "Key: \(item.key)", systemImage: "key.fill", color: category.color)
                        }
                        if let bpm = item.bpm {
                            Chip(text: "♩ = \(bpm)", systemImage: "metronome", color: category.color)
                        }
                    }
                }

                if let shape = ChordShape(item.frets) {
                    ChordDiagram(shape: shape)
                        .frame(width: 84, height: 100)
                } else if !item.frets.isEmpty {
                    Text(item.frets)
                        .font(.callout.monospaced())
                }

                if !item.strum.isEmpty {
                    StrumView(pattern: item.strum)
                }

                if !item.tab.isEmpty {
                    TabText(text: item.tab)
                }

                if !item.body.isEmpty {
                    Text(item.body)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(category.color.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct CategoryBadge: View {
    let category: NoteCategory
    var size: CGFloat = 30

    var body: some View {
        Image(systemName: category.symbol)
            .font(.system(size: size * 0.47, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(category.color.gradient, in: RoundedRectangle(cornerRadius: size * 0.27, style: .continuous))
    }
}

/// Compact chord card used in a grid.
struct ChordTile: View {
    let item: NoteItem
    var date: Date? = nil

    var body: some View {
        VStack(spacing: 6) {
            Text(item.title.isEmpty ? "Chord" : item.title)
                .font(.headline)
            if let shape = ChordShape(item.frets) {
                ChordDiagram(shape: shape)
                    .frame(width: 76, height: 92)
            } else if !item.frets.isEmpty {
                Text(item.frets)
                    .font(.caption.monospaced())
            }
            if !item.body.isEmpty {
                Text(item.body)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            if let date {
                Text(date.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(NoteCategory.chord.color.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(Rectangle())
    }
}
