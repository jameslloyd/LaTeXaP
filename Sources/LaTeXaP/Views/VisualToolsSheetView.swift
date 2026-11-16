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

    /// Converts CSV or TSV text into a publication-ready `booktabs` LaTeX table using `AcademicToolsGenerator` & `AcademicSanitizer`.
    public static func convertCSVToBooktabs(csvText: String, caption: String = "Experimental results.", label: String = "tab:data") -> String {
        let baseGrid = TableGridData(
            headers: ["Column 1", "Column 2", "Column 3"],
            rows: [["Value 1", "Value 2", "Value 3"]],
            alignments: [.left, .center, .center],
            boldHeader: true,
            caption: caption,
            label: label
        )
        let grid = AcademicToolsGenerator.csvToTableGrid(csvText, base: baseGrid)
        return AcademicToolsGenerator.generateBooktabsTable(from: grid)
    }

    public static let equationTemplates: [(title: String, latex: String, hint: String)] = [
        ("Fraction", "\\frac{a}{b}", "Insert fraction template"),
        ("Piecewise (cases)", "\\begin{cases}\n  x & \\text{if } x \\ge 0 \\\\\n  0 & \\text{otherwise}\n\\end{cases}", "Insert piecewise cases block"),
        ("Summation", "\\sum_{i=1}^{n} x_i", "Insert summation"),
        ("Definite Integral", "\\int_{a}^{b} f(x)\\,dx", "Insert definite integral"),
        ("SI Unit (siunitx)", "\\qty{9.81}{m/s^2}", "Insert siunitx physical quantity")
    ]

    public static let mathSymbols: [(category: String, symbols: [(display: String, latex: String)])] = [
        ("Greek Letters", [
            ("α", "\\alpha"), ("β", "\\beta"), ("γ", "\\gamma"), ("δ", "\\delta"),
            ("ϵ", "\\epsilon"), ("ζ", "\\zeta"), ("η", "\\eta"), ("θ", "\\theta"),
            ("λ", "\\lambda"), ("μ", "\\mu"), ("ν", "\\nu"), ("ξ", "\\xi"),
            ("π", "\\pi"), ("ρ", "\\rho"), ("σ", "\\sigma"), ("τ", "\\tau"),
            ("ϕ", "\\phi"), ("χ", "\\chi"), ("ψ", "\\psi"), ("ω", "\\omega"),
            ("Γ", "\\Gamma"), ("Δ", "\\Delta"), ("Θ", "\\Theta"), ("Λ", "\\Lambda"),
            ("Π", "\\Pi"), ("Σ", "\\Sigma"), ("Φ", "\\Phi"), ("Ψ", "\\Psi"), ("Ω", "\\Omega")
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

@MainActor
private final class VisualToolsUIState: ObservableObject {
    @Published var isVisualGridTableMode: Bool = true
    @Published var showTableLaTeXPreview: Bool = false
}

public struct VisualToolsSheetView: View {
    @ObservedObject var viewModel: DocumentViewModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var uiState = VisualToolsUIState()

    public init(viewModel: DocumentViewModel) {
        self.viewModel = viewModel
    }

    private func validateLabel(_ raw: String, prefixName: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "\(prefixName) label cannot be empty." }
        if trimmed.range(of: #"^[A-Za-z0-9:_-]+$"#, options: .regularExpression) == nil {
            return "Label may contain only letters, digits, ':', '_', or '-'."
        }
        return nil
    }

    private var tableLabelValidationError: String? {
        validateLabel(viewModel.tableGridData.label, prefixName: "Table")
    }

    private var csvLabelValidationError: String? {
        validateLabel(viewModel.tableLabelText, prefixName: "Table")
    }

    private var chartLabelValidationError: String? {
        validateLabel(viewModel.chartConfig.label, prefixName: "Chart")
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Visual Math, Table & Chart Builder", systemImage: "function")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)

                Spacer()

                Picker("", selection: $viewModel.visualToolTab) {
                    Text("Math Palette").tag(0)
                    Text("Matrix Builder").tag(1)
                    Text("Table Editor").tag(2)
                    Text("Chart Builder (pgfplots)").tag(3)
                }
                .pickerStyle(.segmented)
                .frame(width: 470)

                Spacer()

                Button {
                    viewModel.showVisualToolsSheet = false
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
                .accessibilityLabel("Close Visual Tools")
                .accessibilityHint("Closes the visual tools sheet")
            }
            .padding(14)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            if viewModel.visualToolTab == 0 {
                mathPaletteTab
            } else if viewModel.visualToolTab == 1 {
                matrixBuilderTab
            } else if viewModel.visualToolTab == 2 {
                tableEditorTab
            } else {
                chartBuilderTab
            }
        }
        .frame(width: 780, height: 530)
    }

    // MARK: - Tab 0: Math Palette + Academic Equation Templates

    private var mathPaletteTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("ACADEMIC EQUATION TEMPLATES (INSERTS AT CARET)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityAddTraits(.isHeader)

                    HStack(spacing: 8) {
                        ForEach(VisualToolsGenerator.equationTemplates, id: \.title) { tpl in
                            Button {
                                viewModel.insertTextAtCaret(tpl.latex, backtrackOffset: 0)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(tpl.title)
                                        .font(.caption.weight(.semibold))
                                    Text(tpl.latex.replacingOccurrences(of: "\n", with: " "))
                                        .font(.system(size: 9.5, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                                .background(Color(NSColor.controlBackgroundColor))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                            .buttonStyle(.plain)
                            .help(tpl.hint)
                            .accessibilityLabel(tpl.title)
                            .accessibilityHint(tpl.hint)
                        }
                    }
                }

                ForEach(VisualToolsGenerator.mathSymbols, id: \.category) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(group.category.uppercased())
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .accessibilityAddTraits(.isHeader)

                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 7), spacing: 8) {
                            ForEach(group.symbols, id: \.latex) { sym in
                                Button {
                                    viewModel.insertTextAtCaret(sym.latex, backtrackOffset: 0)
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
                                .help("Insert \(sym.latex) at caret")
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
    }

    // MARK: - Tab 1: Matrix Builder

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
                Button("Insert Matrix at Caret (Line \(viewModel.cursorLine))") {
                    viewModel.insertTextAtCaret(preview, backtrackOffset: 0)
                    viewModel.showVisualToolsSheet = false
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
    }

    // MARK: - Tab 2: Table Editor (Visual Spreadsheet Grid + CSV/TSV)

    private var tableEditorTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Picker("Table Mode", selection: $uiState.isVisualGridTableMode) {
                    Text("Visual Grid").tag(true)
                    Text("Paste CSV / TSV").tag(false)
                }
                .pickerStyle(.segmented)
                .frame(width: 240)

                Spacer()

                if uiState.isVisualGridTableMode {
                    Toggle("Bold Header", isOn: $viewModel.tableGridData.boldHeader)
                        .font(.caption)

                    DisclosureGroup("LaTeX Preview", isExpanded: $uiState.showTableLaTeXPreview) {
                        EmptyView()
                    }
                    .frame(width: 135)
                }
            }

            if uiState.isVisualGridTableMode {
                visualGridTableEditor
            } else {
                csvTableBuilderTab
            }
        }
        .padding(16)
    }

    private var visualGridTableEditor: some View {
        let colCount = max(1, viewModel.tableGridData.headers.count)
        let rowCount = viewModel.tableGridData.rows.count

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                TextField("Table Caption", text: $viewModel.tableGridData.caption)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Table caption")

                VStack(alignment: .leading, spacing: 2) {
                    TextField("Label (e.g. tab:results)", text: $viewModel.tableGridData.label)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 185)
                        .accessibilityLabel("Table cross-reference label")
                        .accessibilityValue(tableLabelValidationError ?? viewModel.tableGridData.label)
                    if let err = tableLabelValidationError {
                        Text(err)
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }
                }

                Spacer()

                HStack(spacing: 4) {
                    Button("+ Row") { addGridRow() }
                        .disabled(rowCount >= 30)
                        .accessibilityLabel("Add row")
                    Button("- Row") { removeGridRow() }
                        .disabled(rowCount <= 1)
                        .accessibilityLabel("Remove last row")
                    Button("+ Col") { addGridCol() }
                        .disabled(colCount >= 12)
                        .accessibilityLabel("Add column")
                    Button("- Col") { removeGridCol() }
                        .disabled(colCount <= 1)
                        .accessibilityLabel("Remove last column")
                }
                .controlSize(.small)
            }

            ScrollView([.horizontal, .vertical]) {
                VStack(alignment: .leading, spacing: 4) {
                    // Column Alignments Row
                    HStack(spacing: 6) {
                        Text("Align")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 44, alignment: .leading)

                        ForEach(0..<colCount, id: \.self) { colIdx in
                            Picker("", selection: alignmentBinding(for: colIdx)) {
                                Text("L").tag(TableColumnAlignment.left)
                                Text("C").tag(TableColumnAlignment.center)
                                Text("R").tag(TableColumnAlignment.right)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 118)
                            .accessibilityLabel("Column \(colIdx + 1) alignment")
                        }
                    }

                    // Header Row
                    HStack(spacing: 6) {
                        Text("Header")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 44, alignment: .leading)

                        ForEach(0..<colCount, id: \.self) { colIdx in
                            TextField("Header \(colIdx + 1)", text: headerBinding(for: colIdx))
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12, weight: viewModel.tableGridData.boldHeader ? .bold : .regular))
                                .frame(width: 118)
                                .accessibilityLabel("Row 1, Column \(colIdx + 1), Header")
                        }
                    }

                    Divider()

                    // Data Rows
                    ForEach(0..<rowCount, id: \.self) { rowIdx in
                        HStack(spacing: 6) {
                            Text("R\(rowIdx + 1)")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 44, alignment: .leading)

                            ForEach(0..<colCount, id: \.self) { colIdx in
                                TextField("Cell", text: cellBinding(row: rowIdx, col: colIdx))
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 12))
                                    .frame(width: 118)
                                    .accessibilityLabel("Row \(rowIdx + 2), Column \(colIdx + 1)")
                            }
                        }
                    }
                }
                .padding(8)
            }
            .frame(maxHeight: uiState.showTableLaTeXPreview ? 190 : .infinity)
            .background(Color(NSColor.textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
            )

            if uiState.showTableLaTeXPreview {
                ScrollView {
                    Text(AcademicToolsGenerator.generateBooktabsTable(from: viewModel.tableGridData))
                        .font(.system(size: 11, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .frame(height: 115)
                .background(Color(NSColor.textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            HStack {
                Text("Automatically ensures \\usepackage{booktabs} and inserts at editor caret.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Insert Table at Caret") {
                    viewModel.insertSpreadsheetTable()
                    viewModel.showVisualToolsSheet = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(tableLabelValidationError != nil)
            }
        }
    }

    private var csvTableBuilderTab: some View {
        let csvGrid = AcademicToolsGenerator.csvToTableGrid(
            viewModel.csvInputText,
            base: TableGridData(
                headers: ["Column 1", "Column 2", "Column 3"],
                rows: [["Value 1", "Value 2", "Value 3"]],
                alignments: [.left, .center, .center],
                boldHeader: true,
                caption: viewModel.tableCaptionText,
                label: viewModel.tableLabelText
            )
        )
        let preview = AcademicToolsGenerator.generateBooktabsTable(from: csvGrid)

        return VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 12) {
                    TextField("Caption", text: $viewModel.tableCaptionText)
                        .textFieldStyle(.roundedBorder)
                    TextField("Label (e.g. tab:results)", text: $viewModel.tableLabelText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 180)
                        .accessibilityLabel("CSV Table label")
                        .accessibilityValue(csvLabelValidationError ?? viewModel.tableLabelText)
                }
                if let err = csvLabelValidationError {
                    Label(err, systemImage: "xmark.octagon.fill")
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
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
                    viewModel.applyAcademicFix(.insertPackage(packageName: "booktabs", options: ""))
                    viewModel.insertTextAtCaret(preview, backtrackOffset: 0)
                    viewModel.showVisualToolsSheet = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(csvLabelValidationError != nil)
            }
        }
    }

    // MARK: - Tab 3: Chart Builder (pgfplots)

    private var chartBuilderTab: some View {
        let preview = AcademicToolsGenerator.generatePGFPlotChart(from: viewModel.chartConfig)

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                // Left Controls & CSV
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Chart Type", selection: $viewModel.chartConfig.chartType) {
                        ForEach(PGFPlotChartType.allCases) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel("PGFPlots chart type")

                    TextField("Chart Title", text: $viewModel.chartConfig.title)
                        .textFieldStyle(.roundedBorder)

                    HStack(spacing: 8) {
                        TextField("X-Axis Label", text: $viewModel.chartConfig.xLabel)
                            .textFieldStyle(.roundedBorder)
                        TextField("Y-Axis Label", text: $viewModel.chartConfig.yLabel)
                            .textFieldStyle(.roundedBorder)
                    }

                    HStack(spacing: 12) {
                        Toggle("Grid", isOn: $viewModel.chartConfig.showGrid)
                        Toggle("Legend", isOn: $viewModel.chartConfig.showLegend)
                        Spacer()
                        Button("Load Sample") {
                            viewModel.chartConfig.csvText = "x, y\n1, 1.8\n2, 3.4\n3, 5.1\n4, 7.9\n5, 11.2"
                        }
                        .controlSize(.mini)
                    }
                    .font(.caption)

                    Text("CSV DATA (x, y)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)

                    TextEditor(text: $viewModel.chartConfig.csvText)
                        .font(.system(size: 11.5, design: .monospaced))
                        .frame(maxHeight: .infinity)
                        .padding(4)
                        .background(Color(NSColor.textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 6))

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            TextField("Caption", text: $viewModel.chartConfig.caption)
                                .textFieldStyle(.roundedBorder)
                            TextField("fig:chart", text: $viewModel.chartConfig.label)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 120)
                                .accessibilityLabel("Chart label")
                                .accessibilityValue(chartLabelValidationError ?? viewModel.chartConfig.label)
                        }
                        if let err = chartLabelValidationError {
                            Label(err, systemImage: "xmark.octagon.fill")
                                .font(.caption2)
                                .foregroundStyle(.red)
                        }
                    }
                }
                .frame(width: 340)

                // Right Live Preview
                VStack(alignment: .leading, spacing: 4) {
                    Text("PGFPLOTS LATEX PREVIEW")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)

                    ScrollView {
                        Text(preview)
                            .font(.system(size: 11, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                    }
                    .frame(maxHeight: .infinity)
                    .background(Color(NSColor.textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }

            HStack {
                Text("Automatically ensures \\usepackage{pgfplots} and \\pgfplotsset{compat=1.18}.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Insert Chart at Caret") {
                    viewModel.insertPGFPlotChart()
                    viewModel.showVisualToolsSheet = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(chartLabelValidationError != nil)
            }
        }
        .padding(16)
    }

    // MARK: - Grid Manipulation Helpers

    private func addGridRow() {
        let cols = max(1, viewModel.tableGridData.headers.count)
        viewModel.tableGridData.rows.append(Array(repeating: "", count: cols))
    }

    private func removeGridRow() {
        guard viewModel.tableGridData.rows.count > 1 else { return }
        viewModel.tableGridData.rows.removeLast()
    }

    private func addGridCol() {
        let nextNum = viewModel.tableGridData.headers.count + 1
        viewModel.tableGridData.headers.append("Col \(nextNum)")
        viewModel.tableGridData.alignments.append(.center)
        for idx in viewModel.tableGridData.rows.indices {
            viewModel.tableGridData.rows[idx].append("")
        }
    }

    private func removeGridCol() {
        guard viewModel.tableGridData.headers.count > 1 else { return }
        viewModel.tableGridData.headers.removeLast()
        if viewModel.tableGridData.alignments.count > viewModel.tableGridData.headers.count {
            viewModel.tableGridData.alignments.removeLast()
        }
        for idx in viewModel.tableGridData.rows.indices {
            if !viewModel.tableGridData.rows[idx].isEmpty {
                viewModel.tableGridData.rows[idx].removeLast()
            }
        }
    }

    private func alignmentBinding(for col: Int) -> Binding<TableColumnAlignment> {
        Binding(
            get: {
                col < viewModel.tableGridData.alignments.count ? viewModel.tableGridData.alignments[col] : .center
            },
            set: { newValue in
                while viewModel.tableGridData.alignments.count <= col {
                    viewModel.tableGridData.alignments.append(.center)
                }
                viewModel.tableGridData.alignments[col] = newValue
            }
        )
    }

    private func headerBinding(for col: Int) -> Binding<String> {
        Binding(
            get: {
                col < viewModel.tableGridData.headers.count ? viewModel.tableGridData.headers[col] : ""
            },
            set: { newValue in
                while viewModel.tableGridData.headers.count <= col {
                    viewModel.tableGridData.headers.append("")
                }
                viewModel.tableGridData.headers[col] = newValue
            }
        )
    }

    private func cellBinding(row: Int, col: Int) -> Binding<String> {
        Binding(
            get: {
                guard row < viewModel.tableGridData.rows.count,
                      col < viewModel.tableGridData.rows[row].count else { return "" }
                return viewModel.tableGridData.rows[row][col]
            },
            set: { newValue in
                guard row < viewModel.tableGridData.rows.count else { return }
                while viewModel.tableGridData.rows[row].count <= col {
                    viewModel.tableGridData.rows[row].append("")
                }
                viewModel.tableGridData.rows[row][col] = newValue
            }
        )
    }
}
