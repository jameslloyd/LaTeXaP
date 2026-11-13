import SwiftUI

public enum VisualToolsGenerator {
    /// Generates a LaTeX matrix (`pmatrix`, `bmatrix`, `vmatrix`, `Bmatrix`) of size `rows` × `cols`.
    public static func generateMatrix(env: String, rows: Int, cols: Int, fillIdentity: Bool = false) -> String {
        let rCount = max(1, min(10, rows))
        let cCount = max(1, min(10, cols))
        var bodyLines: [String] = []

        for r in 1...rCount {
            var cells: [String] = []
            for c in 1...cCount {
                if fillIdentity {
                    cells.append(r == c ? "1" : "0")
                } else {
                    cells.append("a_{\(r)\(c)}")
                }
            }
            let suffix = (r < rCount) ? " \\\\" : ""
            bodyLines.append("  " + cells.joined(separator: " & ") + suffix)
        }

        return """
\\begin{\(env)}
\(bodyLines.joined(separator: "\n"))
\\end{\(env)}
"""
    }

    /// Converts CSV or TSV text into a publication-ready `booktabs` LaTeX table.
    public static func convertCSVToBooktabs(csvText: String, caption: String = "Experimental results.", label: String = "tab:data") -> String {
        let rawLines = csvText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        guard !rawLines.isEmpty else {
            return """
\\begin{table}[htbp]
  \\centering
  \\begin{tabular}{@{}lcc@{}}
    \\toprule
    Column 1 & Column 2 & Column 3 \\\\
    \\midrule
    Value 1 & Value 2 & Value 3 \\\\
    \\bottomrule
  \\end{tabular}
  \\caption{\(caption)}
  \\label{\(label)}
\\end{table}
"""
        }

        let delimiter: Character = rawLines[0].contains("\t") ? "\t" : ","
        let parsedRows: [[String]] = rawLines.map { line in
            line.split(separator: delimiter, omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
        }

        let colCount = parsedRows.map(\.count).max() ?? 1
        let colSpec = "@{}" + "l" + String(repeating: "c", count: max(0, colCount - 1)) + "@{}"

        func formatRow(_ cells: [String], bold: Bool) -> String {
            var padded = cells
            while padded.count < colCount { padded.append("") }
            let formatted = padded.map { cell -> String in
                let escaped = cell.replacingOccurrences(of: "%", with: "\\%").replacingOccurrences(of: "_", with: "\\_")
                return bold && !escaped.isEmpty ? "\\textbf{\(escaped)}" : escaped
            }
            return "    " + formatted.joined(separator: " & ") + " \\\\"
        }

        let headerLine = formatRow(parsedRows[0], bold: true)
        let dataLines = parsedRows.dropFirst().map { formatRow($0, bold: false) }.joined(separator: "\n")

        return """
\\begin{table}[htbp]
  \\centering
  \\begin{tabular}{\(colSpec)}
    \\toprule
\(headerLine)
    \\midrule
\(dataLines.isEmpty ? "    " + Array(repeating: "—", count: colCount).joined(separator: " & ") + " \\\\" : dataLines)
    \\bottomrule
  \\end{tabular}
  \\caption{\(caption)}
  \\label{\(label)}
\\end{table}
"""
    }

    public static let mathSymbols: [(category: String, symbols: [(display: String, latex: String)])] = [
        ("Greek Letters", [
            ("α", "\\alpha"), ("β", "\\beta"), ("γ", "\\gamma"), ("δ", "\\delta"),
            ("ϵ", "\\epsilon"), ("ζ", "\\zeta"), ("η", "\\eta"), ("θ", "\\theta"),
            ("λ", "\\lambda"), ("μ", "\\mu"), ("ν", "\\nu"), ("ξ", "\\xi"),
            ("π", "\\pi"), ("ρ", "\\rho"), ("σ", "\\sigma"), ("τ", "\\tau"),
            ("ϕ", "\\phi"), ("χ", "\\chi"), ("ψ", "\\psi"), ("ω", "\\omega"),
            ("Γ", "\\Gamma"), ("Δ", "\\Delta"), ("Θ", "\\Theta"), ("Λ", "\\Lambda"),
            ("Π", "\\Pi"), ("Σ", "\\Sigma"), ("Φ", "\\Phi"), ("Ψ", "\\Ψ"), ("Ω", "\\Omega")
        ]),
        ("Calculus & Operators", [
            ("∑", "\\sum_{i=1}^{n}"), ("∏", "\\prod_{i=1}^{n}"), ("∫", "\\int_{-\\infty}^{\\infty}"),
            ("∮", "\\oint"), ("∂", "\\partial"), ("∇", "\\nabla"), ("√", "\\sqrt{x}"),
            ("∞", "\\infty"), ("lim", "\\lim_{n \\to \\infty}"), ("ℝ", "\\mathbb{R}"),
            ("𝔼", "\\mathbb{E}"), ("𝒫", "\\mathcal{P}"), ("ℒ", "\\mathcal{L}"), ("‖x‖", "\\lVert x \\rVert")
        ]),
        ("Relations & Arrows", [
            ("≤", "\\le"), ("≥", "\\ge"), ("≠", "\\neq"), ("≈", "\\approx"),
            ("≡", "\\equiv"), ("∝", "\\propto"), ("∈", "\\in"), ("∉", "\\notin"),
            ("⊂", "\\subset"), ("⊆", "\\subseteq"), ("∪", "\\cup"), ("∩", "\\cap"),
            ("→", "\\to"), ("↦", "\\mapsto"), ("⇒", "\\implies"), ("⇔", "\\iff"),
            ("≔", "\\coloneqq"), ("⊗", "\\otimes"), ("⊕", "\\oplus"), ("⊥", "\\perp")
        ])
    ]
}

public struct VisualToolsSheetView: View {
    @ObservedObject var viewModel: DocumentViewModel

    public init(viewModel: DocumentViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Visual Math, Matrix & Table Builder", systemImage: "function")
                    .font(.headline)

                Spacer()

                Picker("", selection: $viewModel.visualToolTab) {
                    Text("Math Palette").tag(0)
                    Text("Matrix Builder").tag(1)
                    Text("CSV / Table Builder").tag(2)
                }
                .pickerStyle(.segmented)
                .frame(width: 340)

                Spacer()

                Button {
                    viewModel.showVisualToolsSheet = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(14)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            if viewModel.visualToolTab == 0 {
                mathPaletteTab
            } else if viewModel.visualToolTab == 1 {
                matrixBuilderTab
            } else {
                csvTableBuilderTab
            }
        }
        .frame(width: 640, height: 420)
    }

    private var mathPaletteTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(VisualToolsGenerator.mathSymbols, id: \.category) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(group.category.uppercased())
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 7), spacing: 8) {
                            ForEach(group.symbols, id: \.latex) { sym in
                                Button {
                                    viewModel.insertInlineText(sym.latex)
                                } label: {
                                    VStack(spacing: 2) {
                                        Text(sym.display)
                                            .font(.system(size: 16, weight: .medium))
                                        Text(sym.latex)
                                            .font(.system(size: 9, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 6)
                                    .background(Color(NSColor.controlBackgroundColor))
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                }
                                .buttonStyle(.plain)
                                .help("Insert \(sym.latex)")
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
    }

    private var matrixBuilderTab: some View {
        let preview = VisualToolsGenerator.generateMatrix(
            env: viewModel.matrixEnvType,
            rows: viewModel.matrixRows,
            cols: viewModel.matrixCols,
            fillIdentity: viewModel.matrixIdentityFill
        )

        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 20) {
                Picker("Bracket Style:", selection: $viewModel.matrixEnvType) {
                    Text("( ) pmatrix").tag("pmatrix")
                    Text("[ ] bmatrix").tag("bmatrix")
                    Text("| | vmatrix").tag("vmatrix")
                    Text("{ } Bmatrix").tag("Bmatrix")
                }
                .frame(width: 220)

                Stepper("Rows: \(viewModel.matrixRows)", value: $viewModel.matrixRows, in: 1...8)
                Stepper("Cols: \(viewModel.matrixCols)", value: $viewModel.matrixCols, in: 1...8)

                Toggle("Identity (0/1)", isOn: $viewModel.matrixIdentityFill)
            }

            Text("GENERATED LATEX CODE")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ScrollView {
                Text(preview)
                    .font(.system(size: 12.5, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .background(Color(NSColor.textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))

            HStack {
                Spacer()
                Button("Insert Matrix at Line \(viewModel.cursorLine)") {
                    viewModel.insertRawBlock(preview)
                    viewModel.showVisualToolsSheet = false
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
    }

    private var csvTableBuilderTab: some View {
        let preview = VisualToolsGenerator.convertCSVToBooktabs(
            csvText: viewModel.csvInputText,
            caption: viewModel.tableCaptionText,
            label: viewModel.tableLabelText
        )

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                TextField("Caption", text: $viewModel.tableCaptionText)
                    .textFieldStyle(.roundedBorder)
                TextField("Label (e.g. tab:results)", text: $viewModel.tableLabelText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
            }

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("PASTE CSV OR TSV DATA")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextEditor(text: $viewModel.csvInputText)
                        .font(.system(size: 11.5, design: .monospaced))
                        .frame(maxHeight: .infinity)
                        .padding(4)
                        .background(Color(NSColor.textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("BOOKTABS TABLE PREVIEW")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ScrollView {
                        Text(preview)
                            .font(.system(size: 11, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                    }
                    .frame(maxHeight: .infinity)
                    .background(Color(NSColor.textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }

            HStack {
                Text("Automatically ensures \\usepackage{booktabs} is loaded.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Insert Booktabs Table") {
                    if let booktabsPreset = LaTeXCatalog.commonPackages.first(where: { $0.package == "booktabs" }) {
                        viewModel.insertPackage(booktabsPreset)
                    }
                    viewModel.insertRawBlock(preview)
                    viewModel.showVisualToolsSheet = false
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
    }
}
