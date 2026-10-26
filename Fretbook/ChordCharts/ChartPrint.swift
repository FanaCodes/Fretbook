import SwiftUI
import PDFKit

/// One printed page of a chart, laid out at real paper size (points).
struct ChartPrintPage: View {
    let chart: ChordChart
    let page: Int

    private let margin: CGFloat = 40
    private let spacing: CGFloat = 16

    private var headerHeight: CGFloat {
        if chart.title.isEmpty && chart.subtitle.isEmpty { return 0 }
        return chart.subtitle.isEmpty ? 40 : 58
    }

    private var footerHeight: CGFloat { 18 }

    private var cellSize: CGSize {
        let paper = chart.paper.size
        let width = (paper.width - margin * 2 - spacing * CGFloat(chart.columns - 1)) / CGFloat(chart.columns)
        let height = (paper.height - margin * 2 - headerHeight - footerHeight - spacing * CGFloat(chart.rows - 1)) / CGFloat(chart.rows)
        return CGSize(width: max(10, width), height: max(10, height))
    }

    var body: some View {
        let paper = chart.paper.size
        let items = Array(chart.diagrams(onPage: page))
        let cell = cellSize
        let nameSize = min(30, max(9, min(cell.width, cell.height) * 0.11))

        VStack(spacing: 0) {
            if headerHeight > 0 {
                VStack(spacing: 2) {
                    if !chart.title.isEmpty {
                        Text(chart.title)
                            .font(.system(size: 22, weight: .bold))
                    }
                    if !chart.subtitle.isEmpty {
                        Text(chart.subtitle)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(height: headerHeight, alignment: .top)
            }

            Grid(horizontalSpacing: spacing, verticalSpacing: spacing) {
                ForEach(0..<chart.rows, id: \.self) { row in
                    GridRow {
                        ForEach(0..<chart.columns, id: \.self) { column in
                            let index = row * chart.columns + column
                            Group {
                                if index < items.count {
                                    DiagramCard(
                                        diagram: items[index],
                                        leftHanded: chart.leftHanded,
                                        showTuning: chart.showTuning,
                                        showNoteNames: chart.showNoteNames,
                                        nameSize: nameSize
                                    )
                                } else {
                                    Color.clear
                                }
                            }
                            .frame(width: cell.width, height: cell.height)
                        }
                    }
                }
            }

            Spacer(minLength: 0)

            HStack {
                Text(footerText)
                Spacer()
                if chart.pageCount > 1 {
                    Text("\(page + 1) / \(chart.pageCount)")
                }
            }
            .font(.system(size: 8))
            .foregroundStyle(.secondary)
            .frame(height: footerHeight)
        }
        .padding(margin)
        .frame(width: paper.width, height: paper.height)
        .background(Color.white)
        .environment(\.colorScheme, .light)
    }

    private var footerText: String {
        let tunings = Set(chart.diagrams.map { Tunings.name(for: $0.tuning) })
        var parts: [String] = []
        if tunings.count == 1, let tuning = tunings.first, tuning != "Standard" {
            parts.append("Tuning: \(tuning)")
        }
        if chart.leftHanded { parts.append("Left-handed") }
        return parts.joined(separator: " · ")
    }
}

enum ChartPDF {
    /// Renders every page of the chart into a vector PDF in the temporary folder.
    @MainActor
    static func make(_ chart: ChordChart) -> URL? {
        let paper = chart.paper.size
        let safeTitle = chart.title
            .components(separatedBy: CharacterSet(charactersIn: "/\\:?*\"<>|"))
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespaces)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(safeTitle.isEmpty ? "Chord Chart" : safeTitle)
            .appendingPathExtension("pdf")

        var box = CGRect(origin: .zero, size: paper)
        guard let pdf = CGContext(url as CFURL, mediaBox: &box, nil) else { return nil }

        for page in 0..<chart.pageCount {
            let renderer = ImageRenderer(content: ChartPrintPage(chart: chart, page: page))
            renderer.proposedSize = ProposedViewSize(paper)
            pdf.beginPDFPage(nil)
            renderer.render { _, draw in
                draw(pdf)
            }
            pdf.endPDFPage()
        }
        pdf.closePDF()
        return url
    }
}

struct PDFFile: Identifiable {
    let url: URL
    var id: URL { url }
}

struct PDFKitView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = .secondarySystemBackground
        view.document = PDFDocument(url: url)
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        if view.document?.documentURL != url {
            view.document = PDFDocument(url: url)
        }
    }
}

struct PDFPreviewSheet: View {
    let file: PDFFile
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            PDFKitView(url: file.url)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("Print Preview")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { dismiss() }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        ShareLink(item: file.url) {
                            Label("Print or Share", systemImage: "printer")
                        }
                    }
                }
        }
    }
}
