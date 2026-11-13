import AppKit
import SwiftUI

@MainActor
public final class LaTeXSyntaxHighlighter {
    public static let shared = LaTeXSyntaxHighlighter()

    private let expl3CommandRegex: NSRegularExpression?
    private let standardCommandRegex: NSRegularExpression?
    private let envRegex: NSRegularExpression?
    private let inlineMathRegex: NSRegularExpression?
    private let argumentTokenRegex: NSRegularExpression?
    private let commentRegex: NSRegularExpression?

    private init() {
        // expl3 commands: \module_func:arg or \l_module_var_tl or \g_... or \c_... or \__module_...
        self.expl3CommandRegex = try? NSRegularExpression(
            pattern: #"\\(?:[a-zA-Z@]+_[a-zA-Z0-9_@]+(?::[a-zA-Z]*)?|ExplSyntaxOn|ExplSyntaxOff|NewDocumentCommand|ProvideDocumentCommand|DeclareDocumentCommand|NewExpandableDocumentCommand|NewDocumentEnvironment|DeclareDocumentEnvironment|IfBooleanTF|IfBooleanT|IfBooleanF|IfNoValueTF|IfValueTF)"#
        )
        self.standardCommandRegex = try? NSRegularExpression(
            pattern: #"\\[a-zA-Z@]+\*?"#
        )
        self.envRegex = try? NSRegularExpression(
            pattern: #"\\(?:begin|end|documentclass|usepackage)\b(?:\[[^\]]*\])?\{([^}]*)\}"#
        )
        self.inlineMathRegex = try? NSRegularExpression(
            pattern: #"\$[^$\n]+\$|\\\([^\n]+\\\)"#
        )
        self.argumentTokenRegex = try? NSRegularExpression(
            pattern: #"#{1,2}[1-9]"#
        )
        self.commentRegex = try? NSRegularExpression(
            pattern: #"(?<!\\)%.*$"#,
            options: [.anchorsMatchLines]
        )
    }

    public func highlight(textStorage: NSTextStorage, fontSize: CGFloat = 13.5) {
        let string = textStorage.string
        let fullRange = NSRange(location: 0, length: (string as NSString).length)
        guard fullRange.length > 0 else { return }

        let baseFont = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        let boldFont = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .semibold)

        textStorage.beginEditing()
        textStorage.setAttributes([
            .font: baseFont,
            .foregroundColor: NSColor.labelColor
        ], range: fullRange)

        // 1. Inline math ($...$)
        inlineMathRegex?.enumerateMatches(in: string, range: fullRange) { match, _, _ in
            guard let range = match?.range else { return }
            textStorage.addAttribute(.foregroundColor, value: NSColor.systemTeal, range: range)
        }

        // 2. Standard LaTeX commands (\section, \alpha, etc.)
        standardCommandRegex?.enumerateMatches(in: string, range: fullRange) { match, _, _ in
            guard let range = match?.range else { return }
            textStorage.addAttribute(.foregroundColor, value: NSColor.systemBlue, range: range)
        }

        // 3. Environments & packages (\begin{...}, \usepackage{...})
        envRegex?.enumerateMatches(in: string, range: fullRange) { match, _, _ in
            guard let match = match else { return }
            textStorage.addAttributes([
                .foregroundColor: NSColor.systemIndigo,
                .font: boldFont
            ], range: match.range)
            if match.numberOfRanges >= 2 {
                let argRange = match.range(at: 1)
                if argRange.location != NSNotFound {
                    textStorage.addAttribute(.foregroundColor, value: NSColor.systemOrange, range: argRange)
                }
            }
        }

        // 4. LaTeX3 (expl3 & xparse) commands (\cs_new:Npn, \int_eval:n, \l_tmpa_tl, \NewDocumentCommand)
        expl3CommandRegex?.enumerateMatches(in: string, range: fullRange) { match, _, _ in
            guard let range = match?.range else { return }
            textStorage.addAttributes([
                .foregroundColor: NSColor.systemPurple,
                .font: boldFont
            ], range: range)
        }

        // 5. Macro parameters (#1, ##1)
        argumentTokenRegex?.enumerateMatches(in: string, range: fullRange) { match, _, _ in
            guard let range = match?.range else { return }
            textStorage.addAttributes([
                .foregroundColor: NSColor.systemPink,
                .font: boldFont
            ], range: range)
        }

        // 6. Comments (% ...) override everything on the rest of the line
        commentRegex?.enumerateMatches(in: string, range: fullRange) { match, _, _ in
            guard let range = match?.range else { return }
            textStorage.addAttributes([
                .foregroundColor: NSColor.secondaryLabelColor,
                .font: baseFont
            ], range: range)
        }

        textStorage.endEditing()
    }
}

public final class LineNumberGutterView: NSRulerView {
    public var diagnosticsByLine: [Int: DiagnosticSeverity] = [:] {
        didSet { needsDisplay = true }
    }
    public var currentCursorLine: Int = 1 {
        didSet {
            if oldValue != currentCursorLine {
                needsDisplay = true
            }
        }
    }

    public init(textView: NSTextView) {
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        self.clientView = textView
        self.ruleThickness = 46
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView = self.clientView as? NSTextView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer
        else { return }

        NSColor.windowBackgroundColor.withAlphaComponent(0.6).setFill()
        rect.fill()

        // Subtle separator line on right edge of gutter
        let sepRect = NSRect(x: bounds.maxX - 1, y: rect.minY, width: 1, height: rect.height)
        NSColor.separatorColor.withAlphaComponent(0.4).setFill()
        sepRect.fill()

        let visibleGlyphRange = layoutManager.glyphRange(forBoundingRect: textView.visibleRect, in: textContainer)
        let visibleCharRange = layoutManager.characterRange(forGlyphRange: visibleGlyphRange, actualGlyphRange: nil)

        let nsString = textView.string as NSString
        let textOffset = textView.textContainerInset.height - textView.visibleRect.origin.y

        // Count line number up to visibleCharRange.location
        var lineNumber = 1
        var index = 0
        while index < visibleCharRange.location && index < nsString.length {
            let lineRange = nsString.lineRange(for: NSRange(location: index, length: 0))
            index = NSMaxRange(lineRange)
            if index <= visibleCharRange.location {
                lineNumber += 1
            }
        }

        var charIndex = visibleCharRange.location
        let maxCharIndex = NSMaxRange(visibleCharRange)

        let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        let activeFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .bold)

        while charIndex < maxCharIndex && charIndex < nsString.length {
            let lineCharRange = nsString.lineRange(for: NSRange(location: charIndex, length: 0))
            let glyphIndex = layoutManager.glyphIndexForCharacter(at: charIndex)
            var lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
            lineRect.origin.y += textOffset

            let isCurrent = (lineNumber == currentCursorLine)
            let severity = diagnosticsByLine[lineNumber]

            // Draw diagnostic indicator dot or row highlight
            if let severity = severity {
                let markerColor: NSColor = severity == .error ? .systemRed : (severity == .warning ? .systemOrange : .systemBlue)
                let dotRect = NSRect(x: 6, y: lineRect.midY - 3.5, width: 7, height: 7)
                let path = NSBezierPath(ovalIn: dotRect)
                markerColor.setFill()
                path.fill()
            }

            let labelColor: NSColor
            if severity == .error {
                labelColor = .systemRed
            } else if severity == .warning {
                labelColor = .systemOrange
            } else if isCurrent {
                labelColor = .labelColor
            } else {
                labelColor = .secondaryLabelColor
            }

            let attrs: [NSAttributedString.Key: Any] = [
                .font: isCurrent ? activeFont : font,
                .foregroundColor: labelColor
            ]
            let label = "\(lineNumber)" as NSString
            let labelSize = label.size(withAttributes: attrs)
            let drawPoint = NSPoint(
                x: ruleThickness - labelSize.width - 8,
                y: lineRect.minY + (lineRect.height - labelSize.height) / 2.0
            )
            label.draw(at: drawPoint, withAttributes: attrs)

            charIndex = NSMaxRange(lineCharRange)
            lineNumber += 1
        }
    }
}

// MARK: - Autocomplete Floating Popup Window & Controller

@MainActor
public final class AutoCompletePopupController: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    private var panel: NSPanel?
    private var tableView: NSTableView?
    private var detailLabel: NSTextField?
    public private(set) var items: [LaTeXCompletionItem] = []
    public var onAcceptItem: ((LaTeXCompletionItem) -> Void)?

    public var isVisible: Bool {
        panel?.isVisible ?? false
    }

    public var selectedItem: LaTeXCompletionItem? {
        guard let tableView = tableView,
              tableView.selectedRow >= 0,
              tableView.selectedRow < items.count
        else { return items.first }
        return items[tableView.selectedRow]
    }

    public override init() {
        super.init()
        setupPanel()
    }

    private func setupPanel() {
        let panelRect = NSRect(x: 0, y: 0, width: 410, height: 224)
        let panel = NSPanel(
            contentRect: panelRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.hasShadow = true
        panel.backgroundColor = .clear
        panel.isOpaque = false

        let visualEffect = NSVisualEffectView(frame: panelRect)
        visualEffect.material = .menu
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 8
        visualEffect.layer?.masksToBounds = true
        visualEffect.layer?.borderWidth = 1
        visualEffect.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.5).cgColor

        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 26, width: panelRect.width, height: panelRect.height - 26))
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.autoresizingMask = [.width, .height]

        let table = NSTableView(frame: scrollView.bounds)
        table.headerView = nil
        table.rowHeight = 24
        table.intercellSpacing = NSSize(width: 0, height: 2)
        table.backgroundColor = .clear
        table.selectionHighlightStyle = .regular
        table.allowsEmptySelection = false
        table.target = self
        table.doubleAction = #selector(handleDoubleClick(_:))

        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("CompletionCol"))
        col.width = panelRect.width - 16
        table.addTableColumn(col)

        table.dataSource = self
        table.delegate = self

        scrollView.documentView = table
        visualEffect.addSubview(scrollView)

        // Footer bar showing full description + Tab/Return hint
        let footerSep = NSBox(frame: NSRect(x: 0, y: 25, width: panelRect.width, height: 1))
        footerSep.boxType = .separator
        footerSep.autoresizingMask = [.width]
        visualEffect.addSubview(footerSep)

        let detail = NSTextField(labelWithString: "")
        detail.frame = NSRect(x: 8, y: 4, width: panelRect.width - 16, height: 17)
        detail.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        detail.textColor = NSColor.secondaryLabelColor
        detail.lineBreakMode = .byTruncatingTail
        detail.autoresizingMask = [.width]
        visualEffect.addSubview(detail)

        panel.contentView = visualEffect
        self.panel = panel
        self.tableView = table
        self.detailLabel = detail
    }

    @objc private func handleDoubleClick(_ sender: Any?) {
        if let item = selectedItem {
            onAcceptItem?(item)
        }
    }

    public func show(items: [LaTeXCompletionItem], at screenPoint: NSPoint, parentWindow: NSWindow?) {
        guard !items.isEmpty, let panel = panel, let tableView = tableView else {
            hide()
            return
        }
        self.items = items
        tableView.reloadData()
        tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        tableView.scrollRowToVisible(0)
        updateFooterDetail()

        let visibleRows = min(items.count, 8)
        let panelHeight = CGFloat(visibleRows) * 26.0 + 30.0
        let panelWidth: CGFloat = 420.0

        var origin = NSPoint(x: screenPoint.x, y: screenPoint.y - panelHeight - 4)
        if let screenFrame = (parentWindow?.screen ?? NSScreen.main)?.visibleFrame {
            if origin.y < screenFrame.minY {
                // Flip above cursor line if near bottom of screen
                origin.y = screenPoint.y + 20
            }
            if origin.x + panelWidth > screenFrame.maxX {
                origin.x = max(screenFrame.minX + 8, screenFrame.maxX - panelWidth - 8)
            }
        }

        panel.setFrame(NSRect(origin: origin, size: NSSize(width: panelWidth, height: panelHeight)), display: true)
        if !panel.isVisible {
            if let parentWindow = parentWindow {
                parentWindow.addChildWindow(panel, ordered: .above)
            }
            panel.orderFront(nil)
        }
    }

    public func hide() {
        guard let panel = panel, panel.isVisible else { return }
        if let parent = panel.parent {
            parent.removeChildWindow(panel)
        }
        panel.orderOut(nil)
    }

    public func moveSelection(delta: Int) {
        guard let tableView = tableView, !items.isEmpty else { return }
        let current = max(0, tableView.selectedRow)
        let next = (current + delta + items.count) % items.count
        tableView.selectRowIndexes(IndexSet(integer: next), byExtendingSelection: false)
        tableView.scrollRowToVisible(next)
        updateFooterDetail()
    }

    private func updateFooterDetail() {
        if let selected = selectedItem {
            detailLabel?.stringValue = "\(selected.detail)  •  ⇥ Tab / ↩ Return to insert"
        } else {
            detailLabel?.stringValue = ""
        }
    }

    public func numberOfRows(in tableView: NSTableView) -> Int {
        items.count
    }

    public func tableViewSelectionDidChange(_ notification: Notification) {
        updateFooterDetail()
    }

    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row >= 0, row < items.count else { return nil }
        let item = items[row]

        let cellID = NSUserInterfaceItemIdentifier("LaTeXCompletionCell")
        let container = NSTableCellView()
        container.identifier = cellID

        // Badge label (expl3, xparse, env, math, pkg, user)
        let badge = NSTextField(labelWithString: item.category.uppercased())
        badge.font = NSFont.monospacedSystemFont(ofSize: 9.5, weight: .bold)
        badge.alignment = .center
        badge.wantsLayer = true
        badge.layer?.cornerRadius = 4
        let badgeColor = Self.color(for: item.category)
        badge.textColor = badgeColor
        badge.layer?.backgroundColor = badgeColor.withAlphaComponent(0.15).cgColor
        badge.translatesAutoresizingMaskIntoConstraints = false

        // Trigger command title
        let titleField = NSTextField(labelWithString: item.displayTitle)
        titleField.font = NSFont.monospacedSystemFont(ofSize: 12.5, weight: .semibold)
        titleField.textColor = NSColor.labelColor
        titleField.lineBreakMode = .byTruncatingTail
        titleField.translatesAutoresizingMaskIntoConstraints = false

        // Signature preview
        let sigField = NSTextField(labelWithString: item.signature)
        sigField.font = NSFont.monospacedSystemFont(ofSize: 11.5, weight: .regular)
        sigField.textColor = NSColor.secondaryLabelColor
        sigField.lineBreakMode = .byTruncatingTail
        sigField.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(badge)
        container.addSubview(titleField)
        container.addSubview(sigField)

        NSLayoutConstraint.activate([
            badge.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 6),
            badge.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            badge.widthAnchor.constraint(equalToConstant: 48),

            titleField.leadingAnchor.constraint(equalTo: badge.trailingAnchor, constant: 8),
            titleField.centerYAnchor.constraint(equalTo: container.centerYAnchor),

            sigField.leadingAnchor.constraint(equalTo: titleField.trailingAnchor, constant: 6),
            sigField.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -8),
            sigField.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])

        return container
    }

    private static func color(for category: String) -> NSColor {
        switch category {
        case "expl3": return .systemPurple
        case "xparse": return .systemIndigo
        case "env": return .systemTeal
        case "math": return .systemBlue
        case "pkg": return .systemOrange
        case "python": return .systemYellow
        case "user": return .systemGreen
        default: return .secondaryLabelColor
        }
    }
}

// MARK: - Custom NSTextView withInline Ghost Text & Auto-Pair

public final class LaTeXEditorTextView: NSTextView {
    public var ghostSuffix: String = "" {
        didSet {
            if oldValue != ghostSuffix {
                needsDisplay = true
            }
        }
    }

    public override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // Draw inline ghost completion preview right after the caret when cursor is at the end of the line token
        guard !ghostSuffix.isEmpty,
              let layoutManager = self.layoutManager
        else { return }

        let sel = selectedRange()
        guard sel.length == 0 else { return }

        let nsString = self.string as NSString
        guard sel.location <= nsString.length else { return }

        // Only draw ghost text if cursor is at end of line (or only whitespace follows on the line)
        let lineRange = nsString.lineRange(for: NSRange(location: sel.location, length: 0))
        let remainderLen = NSMaxRange(lineRange) - sel.location
        if remainderLen > 0 {
            let remainder = nsString.substring(with: NSRange(location: sel.location, length: remainderLen))
            if !remainder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return
            }
        }

        let glyphIndex = layoutManager.glyphIndexForCharacter(at: max(0, sel.location - 1))
        let charPoint: NSPoint
        if sel.location == 0 {
            charPoint = NSPoint(x: textContainerInset.width + 5, y: textContainerInset.height)
        } else {
            let lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
            let loc = layoutManager.location(forGlyphAt: glyphIndex)
            let prevChar = nsString.substring(with: NSRange(location: sel.location - 1, length: 1)) as NSString
            let font = NSFont.monospacedSystemFont(ofSize: 13.5, weight: .regular)
            let advance = prevChar.size(withAttributes: [.font: font]).width
            charPoint = NSPoint(
                x: textContainerInset.width + lineRect.origin.x + loc.x + advance,
                y: textContainerInset.height + lineRect.origin.y
            )
        }

        // Only render the first line of the ghost suffix inline so multiline completions stay clean
        let firstLineGhost = ghostSuffix.components(separatedBy: .newlines).first ?? ghostSuffix
        let ghostAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 13.5, weight: .regular),
            .foregroundColor: NSColor.placeholderTextColor
        ]
        (firstLineGhost as NSString).draw(at: charPoint, withAttributes: ghostAttrs)
    }
}

public struct LaTeXCodeEditorView: NSViewRepresentable {
    @Binding public var text: String
    @Binding public var cursorLine: Int
    @Binding public var jumpToLineRequest: Int?
    public var diagnostics: [LaTeXDiagnostic]
    public var fontSize: CGFloat

    public init(
        text: Binding<String>,
        cursorLine: Binding<Int>,
        jumpToLineRequest: Binding<Int?>,
        diagnostics: [LaTeXDiagnostic],
        fontSize: CGFloat = 13.5
    ) {
        self._text = text
        self._cursorLine = cursorLine
        self._jumpToLineRequest = jumpToLineRequest
        self.diagnostics = diagnostics
        self.fontSize = fontSize
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    public func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)

        let textContainer = NSTextContainer(containerSize: NSSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true
        layoutManager.addTextContainer(textContainer)

        let textView = LaTeXEditorTextView(frame: .zero, textContainer: textContainer)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.isRichText = false
        textView.importsGraphics = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.textContainerInset = NSSize(width: 8, height: 10)
        textView.backgroundColor = NSColor.textBackgroundColor
        textView.delegate = context.coordinator

        scrollView.documentView = textView

        let gutter = LineNumberGutterView(textView: textView)
        scrollView.verticalRulerView = gutter
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true

        context.coordinator.textView = textView
        context.coordinator.gutterView = gutter

        textView.string = text
        LaTeXSyntaxHighlighter.shared.highlight(textStorage: textStorage, fontSize: fontSize)
        context.coordinator.updateDiagnostics(diagnostics)

        // Observe scroll notifications to redraw line numbers and hide popup on scroll
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.boundsDidChange(_:)),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
        scrollView.contentView.postsBoundsChangedNotifications = true

        return scrollView
    }

    public func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = context.coordinator.textView,
              let textStorage = textView.textStorage
        else { return }

        if textView.string != text && !context.coordinator.isEditingText {
            let selectedRanges = textView.selectedRanges
            textView.string = text
            LaTeXSyntaxHighlighter.shared.highlight(textStorage: textStorage, fontSize: fontSize)
            textView.selectedRanges = selectedRanges
            context.coordinator.gutterView?.needsDisplay = true
        }

        context.coordinator.updateDiagnostics(diagnostics)

        if let targetLine = jumpToLineRequest {
            DispatchQueue.main.async {
                context.coordinator.scrollToLine(targetLine)
                self.jumpToLineRequest = nil
            }
        }
    }

    @MainActor
    public final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: LaTeXCodeEditorView
        weak var textView: LaTeXEditorTextView?
        weak var gutterView: LineNumberGutterView?
        var isEditingText = false

        let popupController = AutoCompletePopupController()
        var activeQuery: CompletionQueryContext?

        override init() {
            fatalError("Use init(_:)")
        }

        init(_ parent: LaTeXCodeEditorView) {
            self.parent = parent
            super.init()
            popupController.onAcceptItem = { [weak self] item in
                self?.acceptCompletion(item)
            }
        }

        @objc func boundsDidChange(_ notification: Notification) {
            gutterView?.needsDisplay = true
            popupController.hide()
        }

        public func textDidChange(_ notification: Notification) {
            guard let textView = textView, let textStorage = textView.textStorage else { return }
            isEditingText = true
            let newString = textView.string
            parent.text = newString
            LaTeXSyntaxHighlighter.shared.highlight(textStorage: textStorage, fontSize: parent.fontSize)
            updateCursorLine()
            refreshAutoComplete()
            gutterView?.needsDisplay = true
            isEditingText = false
        }

        public func textViewDidChangeSelection(_ notification: Notification) {
            updateCursorLine()
            if !isEditingText {
                // Hide autocomplete when user clicks elsewhere or moves cursor outside active token
                refreshAutoComplete(onlyUpdateIfAlreadyVisible: true)
            }
        }

        public func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if popupController.isVisible {
                if commandSelector == #selector(NSResponder.moveDown(_:)) {
                    popupController.moveSelection(delta: 1)
                    updateGhostText()
                    return true
                }
                if commandSelector == #selector(NSResponder.moveUp(_:)) {
                    popupController.moveSelection(delta: -1)
                    updateGhostText()
                    return true
                }
                if commandSelector == #selector(NSResponder.insertTab(_:)) ||
                   commandSelector == #selector(NSResponder.insertNewline(_:)) {
                    if let selected = popupController.selectedItem {
                        acceptCompletion(selected)
                        return true
                    }
                }
                if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                    dismissAutoComplete()
                    return true
                }
            } else {
                // Allow manual trigger with Escape / Option+Escape
                if commandSelector == #selector(NSResponder.complete(_:)) ||
                   commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                    refreshAutoComplete(onlyUpdateIfAlreadyVisible: false)
                    if popupController.isVisible {
                        return true
                    }
                }
            }
            return false
        }

        private func refreshAutoComplete(onlyUpdateIfAlreadyVisible: Bool = false) {
            guard let textView = textView else { return }
            let sel = textView.selectedRange()
            guard sel.length == 0 else {
                dismissAutoComplete()
                return
            }

            let source = textView.string
            guard let query = LaTeXAutoCompleteEngine.extractQuery(in: source, cursorLocation: sel.location) else {
                dismissAutoComplete()
                return
            }

            if onlyUpdateIfAlreadyVisible && !popupController.isVisible {
                return
            }

            let suggestions = LaTeXAutoCompleteEngine.suggestions(for: query, in: source)
            guard !suggestions.isEmpty else {
                dismissAutoComplete()
                return
            }

            self.activeQuery = query
            let caretScreenPoint = screenPointForCharacter(at: query.replacementRange.location, in: textView)
            popupController.show(items: suggestions, at: caretScreenPoint, parentWindow: textView.window)
            updateGhostText()
        }

        private func updateGhostText() {
            guard let textView = textView,
                  let query = activeQuery,
                  let selected = popupController.selectedItem
            else {
                textView?.ghostSuffix = ""
                return
            }
            let plain = selected.plainInsertion.text
            if plain.lowercased().hasPrefix(query.prefix.lowercased()) {
                let suffix = String(plain.dropFirst(query.prefix.count))
                textView.ghostSuffix = suffix
            } else {
                textView.ghostSuffix = ""
            }
        }

        private func dismissAutoComplete() {
            activeQuery = nil
            textView?.ghostSuffix = ""
            popupController.hide()
        }

        public func acceptCompletion(_ item: LaTeXCompletionItem) {
            guard let textView = textView,
                  let textStorage = textView.textStorage,
                  let query = activeQuery
            else { return }

            let nsString = textView.string as NSString
            guard NSMaxRange(query.replacementRange) <= nsString.length else {
                dismissAutoComplete()
                return
            }

            // Preserve leading indentation of the current line for multi-line expansions (like \begin{align}...\end{align})
            let lineRange = nsString.lineRange(for: NSRange(location: query.replacementRange.location, length: 0))
            let lineText = nsString.substring(with: lineRange)
            let leadingIndent = String(lineText.prefix { $0 == " " || $0 == "\t" })

            let rawLines = item.insertText.components(separatedBy: "\n")
            let indentedInsert: String
            if rawLines.count > 1 && !leadingIndent.isEmpty {
                indentedInsert = ([rawLines[0]] + rawLines.dropFirst().map { leadingIndent + $0 }).joined(separator: "\n")
            } else {
                indentedInsert = item.insertText
            }

            let (cleanText, cursorOffset) = LaTeXCompletionItem(
                trigger: item.trigger,
                category: item.category,
                detail: item.detail,
                insertText: indentedInsert
            ).plainInsertion

            dismissAutoComplete()

            if textView.shouldChangeText(in: query.replacementRange, replacementString: cleanText) {
                isEditingText = true
                textStorage.replaceCharacters(in: query.replacementRange, with: cleanText)
                textView.didChangeText()

                let newCursorLocation = query.replacementRange.location + cursorOffset
                textView.setSelectedRange(NSRange(location: newCursorLocation, length: 0))

                parent.text = textView.string
                LaTeXSyntaxHighlighter.shared.highlight(textStorage: textStorage, fontSize: parent.fontSize)
                updateCursorLine()
                gutterView?.needsDisplay = true
                isEditingText = false
            }
        }

        private func screenPointForCharacter(at charIndex: Int, in textView: NSTextView) -> NSPoint {
            guard let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer,
                  let window = textView.window
            else { return .zero }

            let safeIdx = max(0, min(charIndex, (textView.string as NSString).length))
            let glyphRange = layoutManager.glyphRange(forCharacterRange: NSRange(location: safeIdx, length: 0), actualCharacterRange: nil)
            var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            rect.origin.x += textView.textContainerInset.width
            rect.origin.y += textView.textContainerInset.height

            let viewPoint = NSPoint(x: rect.minX, y: rect.maxY)
            let windowPoint = textView.convert(viewPoint, to: nil)
            return window.convertPoint(toScreen: windowPoint)
        }

        private func updateCursorLine() {
            guard let textView = textView else { return }
            let selectedRange = textView.selectedRange()
            let nsString = textView.string as NSString
            let safeLoc = min(selectedRange.location, nsString.length)
            let prefix = nsString.substring(to: safeLoc)
            let line = prefix.components(separatedBy: .newlines).count
            if parent.cursorLine != line {
                DispatchQueue.main.async {
                    self.parent.cursorLine = line
                }
            }
            gutterView?.currentCursorLine = line
        }

        func updateDiagnostics(_ diagnostics: [LaTeXDiagnostic]) {
            var map: [Int: DiagnosticSeverity] = [:]
            for diag in diagnostics {
                guard let line = diag.line else { continue }
                if let existing = map[line] {
                    if existing != .error && diag.severity == .error {
                        map[line] = .error
                    }
                } else {
                    map[line] = diag.severity
                }
            }
            gutterView?.diagnosticsByLine = map
        }

        func scrollToLine(_ targetLine: Int) {
            guard let textView = textView else { return }
            let nsString = textView.string as NSString
            var currentLine = 1
            var index = 0
            while index < nsString.length && currentLine < targetLine {
                let lineRange = nsString.lineRange(for: NSRange(location: index, length: 0))
                index = NSMaxRange(lineRange)
                currentLine += 1
            }
            let targetRange = nsString.lineRange(for: NSRange(location: min(index, max(0, nsString.length - 1)), length: 0))
            textView.window?.makeFirstResponder(textView)
            textView.setSelectedRange(targetRange)
            textView.scrollRangeToVisible(targetRange)
            textView.showFindIndicator(for: targetRange)
            updateCursorLine()
        }
    }
}
