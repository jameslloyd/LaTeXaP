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

    public static func resolveFont(name: String, size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            if let font = NSFont(name: trimmed, size: size) {
                if weight == .semibold || weight == .bold {
                    return NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
                }
                return font
            }
            let descriptor = NSFontDescriptor(fontAttributes: [.family: trimmed])
            if let familyFont = NSFont(descriptor: descriptor, size: size) {
                if weight == .semibold || weight == .bold {
                    return NSFontManager.shared.convert(familyFont, toHaveTrait: .boldFontMask)
                }
                return familyFont
            }
        }
        return NSFont.monospacedSystemFont(ofSize: size, weight: weight)
    }

    public func highlight(
        textStorage: NSTextStorage,
        fontSize: CGFloat = 13.5,
        fontName: String = "",
        lightBackground: Bool = true
    ) {
        let string = textStorage.string
        let fullRange = NSRange(location: 0, length: (string as NSString).length)
        guard fullRange.length > 0 else { return }

        let baseFont = Self.resolveFont(name: fontName, size: fontSize, weight: .regular)
        let boldFont = Self.resolveFont(name: fontName, size: fontSize, weight: .semibold)

        // High-contrast explicit sRGB palette for effortless reading
        let baseTextColor = lightBackground
            ? NSColor(srgbRed: 0.06, green: 0.09, blue: 0.16, alpha: 1.0) // #0F172A deep ink
            : NSColor(srgbRed: 0.94, green: 0.96, blue: 0.99, alpha: 1.0) // #F0F5FC bright white
        let mathColor = lightBackground
            ? NSColor(srgbRed: 0.04, green: 0.45, blue: 0.40, alpha: 1.0) // #0A7366 deep emerald
            : NSColor(srgbRed: 0.34, green: 0.86, blue: 0.78, alpha: 1.0) // bright teal
        let stdCmdColor = lightBackground
            ? NSColor(srgbRed: 0.01, green: 0.36, blue: 0.68, alpha: 1.0) // #035CAD cobalt blue
            : NSColor(srgbRed: 0.47, green: 0.76, blue: 1.00, alpha: 1.0) // bright sky blue
        let envCmdColor = lightBackground
            ? NSColor(srgbRed: 0.11, green: 0.25, blue: 0.76, alpha: 1.0) // #1C40C2 royal indigo
            : NSColor(srgbRed: 0.65, green: 0.72, blue: 1.00, alpha: 1.0) // bright periwinkle
        let envArgColor = lightBackground
            ? NSColor(srgbRed: 0.71, green: 0.27, blue: 0.03, alpha: 1.0) // #B54508 burnt amber
            : NSColor(srgbRed: 1.00, green: 0.68, blue: 0.35, alpha: 1.0) // warm orange
        let expl3Color = lightBackground
            ? NSColor(srgbRed: 0.42, green: 0.13, blue: 0.74, alpha: 1.0) // #6B21BD deep violet
            : NSColor(srgbRed: 0.84, green: 0.65, blue: 1.00, alpha: 1.0) // bright lavender
        let paramColor = lightBackground
            ? NSColor(srgbRed: 0.75, green: 0.07, blue: 0.24, alpha: 1.0) // #BF123D crimson
            : NSColor(srgbRed: 1.00, green: 0.48, blue: 0.58, alpha: 1.0) // bright coral
        let commentColor = lightBackground
            ? NSColor(srgbRed: 0.27, green: 0.35, blue: 0.45, alpha: 1.0) // #455973 readable slate
            : NSColor(srgbRed: 0.58, green: 0.66, blue: 0.75, alpha: 1.0) // cool steel grey

        textStorage.beginEditing()
        textStorage.setAttributes([
            .font: baseFont,
            .foregroundColor: baseTextColor
        ], range: fullRange)

        // 1. Inline math ($...$)
        inlineMathRegex?.enumerateMatches(in: string, range: fullRange) { match, _, _ in
            guard let range = match?.range else { return }
            textStorage.addAttribute(.foregroundColor, value: mathColor, range: range)
        }

        // 2. Standard LaTeX commands (\section, \alpha, etc.)
        standardCommandRegex?.enumerateMatches(in: string, range: fullRange) { match, _, _ in
            guard let range = match?.range else { return }
            textStorage.addAttribute(.foregroundColor, value: stdCmdColor, range: range)
        }

        // 3. Environments & packages (\begin{...}, \usepackage{...})
        envRegex?.enumerateMatches(in: string, range: fullRange) { match, _, _ in
            guard let match = match else { return }
            textStorage.addAttributes([
                .foregroundColor: envCmdColor,
                .font: boldFont
            ], range: match.range)
            if match.numberOfRanges >= 2 {
                let argRange = match.range(at: 1)
                if argRange.location != NSNotFound {
                    textStorage.addAttribute(.foregroundColor, value: envArgColor, range: argRange)
                }
            }
        }

        // 4. LaTeX3 (expl3 & xparse) commands (\cs_new:Npn, \int_eval:n, \l_tmpa_tl, \NewDocumentCommand)
        expl3CommandRegex?.enumerateMatches(in: string, range: fullRange) { match, _, _ in
            guard let range = match?.range else { return }
            textStorage.addAttributes([
                .foregroundColor: expl3Color,
                .font: boldFont
            ], range: range)
        }

        // 5. Macro parameters (#1, ##1)
        argumentTokenRegex?.enumerateMatches(in: string, range: fullRange) { match, _, _ in
            guard let range = match?.range else { return }
            textStorage.addAttributes([
                .foregroundColor: paramColor,
                .font: boldFont
            ], range: range)
        }

        // 6. Comments (% ...) override everything on the rest of the line
        commentRegex?.enumerateMatches(in: string, range: fullRange) { match, _, _ in
            guard let range = match?.range else { return }
            textStorage.addAttributes([
                .foregroundColor: commentColor,
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
    public var lightBackground: Bool = true {
        didSet {
            if oldValue != lightBackground {
                needsDisplay = true
            }
        }
    }

    public init(textView: NSTextView) {
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        self.clientView = textView
        self.ruleThickness = 46
        self.clipsToBounds = true
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

        let gutterBounds = NSRect(x: 0, y: bounds.minY, width: ruleThickness, height: bounds.height)
        NSBezierPath(rect: gutterBounds).addClip()

        let gutterBg = lightBackground
            ? NSColor(srgbRed: 0.95, green: 0.96, blue: 0.98, alpha: 1.0) // #F1F5F9
            : NSColor(srgbRed: 0.09, green: 0.11, blue: 0.15, alpha: 1.0) // #161B22
        gutterBg.setFill()
        gutterBounds.fill()

        // Subtle separator line on right edge of gutter
        let sepRect = NSRect(x: ruleThickness - 1, y: gutterBounds.minY, width: 1, height: gutterBounds.height)
        let sepColor = lightBackground
            ? NSColor(srgbRed: 0.82, green: 0.85, blue: 0.90, alpha: 1.0)
            : NSColor(srgbRed: 0.20, green: 0.24, blue: 0.30, alpha: 1.0)
        sepColor.setFill()
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

            if isCurrent {
                let activeRowBg = lightBackground
                    ? NSColor(srgbRed: 0.88, green: 0.91, blue: 0.96, alpha: 1.0)
                    : NSColor(srgbRed: 0.14, green: 0.18, blue: 0.25, alpha: 1.0)
                activeRowBg.setFill()
                NSRect(x: 0, y: lineRect.minY, width: ruleThickness - 1, height: lineRect.height).fill()
            }

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
                labelColor = lightBackground
                    ? NSColor(srgbRed: 0.06, green: 0.09, blue: 0.16, alpha: 1.0)
                    : NSColor(srgbRed: 0.95, green: 0.97, blue: 1.00, alpha: 1.0)
            } else {
                labelColor = lightBackground
                    ? NSColor(srgbRed: 0.39, green: 0.45, blue: 0.55, alpha: 1.0)
                    : NSColor(srgbRed: 0.55, green: 0.62, blue: 0.72, alpha: 1.0)
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
        case "bib": return .systemPink
        case "ref": return .systemCyan
        case "user": return .systemGreen
        default: return .secondaryLabelColor
        }
    }
}

// MARK: - Custom NSTextView withInline Ghost Text & Auto-Pair

@MainActor
private final class SpellingMenuPayload: NSObject {
    let issue: SpellingIssue
    let replacement: String?

    init(issue: SpellingIssue, replacement: String?) {
        self.issue = issue
        self.replacement = replacement
    }
}

public final class LaTeXEditorTextView: NSTextView {
    public var onDropImageFile: ((URL) -> Void)?
    public var onDropFontFiles: (([URL]) -> Void)?
    public var onDropBibFile: ((URL) -> Void)?
    public var activeSpellingIssues: [SpellingIssue] = []
    public var onApplySpellingFix: ((SpellingIssue, String) -> Void)?
    public var onIgnoreSpellingWord: ((String) -> Void)?
    public var editorFontSize: CGFloat = 13.5 {
        didSet {
            if oldValue != editorFontSize {
                needsDisplay = true
            }
        }
    }
    public var editorFontName: String = "" {
        didSet {
            if oldValue != editorFontName {
                needsDisplay = true
            }
        }
    }
    public var lightBackground: Bool = true {
        didSet {
            if oldValue != lightBackground {
                needsDisplay = true
            }
        }
    }

    public var ghostSuffix: String = "" {
        didSet {
            if oldValue != ghostSuffix {
                needsDisplay = true
            }
        }
    }

    public override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pboard = sender.draggingPasteboard
        let readOptions: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true
        ]
        if let urls = pboard.readObjects(forClasses: [NSURL.self], options: readOptions) as? [URL],
           !urls.isEmpty {
            let fileURLs = urls.filter { $0.isFileURL }
            let fontURLs = fileURLs.filter { ["ttf", "otf", "ttc"].contains($0.pathExtension.lowercased()) }
            if !fontURLs.isEmpty {
                onDropFontFiles?(fontURLs)
                return true
            }
            if let first = fileURLs.first {
                let ext = first.pathExtension.lowercased()
                if ext == "bib" {
                    onDropBibFile?(first)
                    return true
                }
                if ["png", "jpg", "jpeg", "pdf", "tiff"].contains(ext) {
                    onDropImageFile?(first)
                    return true
                }
            }
        }
        return super.performDragOperation(sender)
    }

    public override func menu(for event: NSEvent) -> NSMenu? {
        let baseMenu = super.menu(for: event) ?? NSMenu()
        guard !activeSpellingIssues.isEmpty else { return baseMenu }

        let viewPoint = convert(event.locationInWindow, from: nil)
        let charIndex = characterIndexForInsertion(at: viewPoint)
        guard let issue = activeSpellingIssues.first(where: { NSLocationInRange(charIndex, $0.nsRange) }) else {
            return baseMenu
        }

        var itemsToPrepend: [NSMenuItem] = []
        if issue.suggestions.isEmpty {
            let noneItem = NSMenuItem(title: "No Spelling Suggestions", action: nil, keyEquivalent: "")
            noneItem.isEnabled = false
            itemsToPrepend.append(noneItem)
        } else {
            for suggestion in issue.suggestions.prefix(5) {
                let item = NSMenuItem(
                    title: "Replace with “\(suggestion)”",
                    action: #selector(handleApplySpellingSuggestion(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = SpellingMenuPayload(issue: issue, replacement: suggestion)
                itemsToPrepend.append(item)
            }
        }

        let ignoreItem = NSMenuItem(
            title: "Ignore “\(issue.word)”",
            action: #selector(handleIgnoreSpellingWord(_:)),
            keyEquivalent: ""
        )
        ignoreItem.target = self
        ignoreItem.representedObject = SpellingMenuPayload(issue: issue, replacement: nil)
        itemsToPrepend.append(ignoreItem)
        itemsToPrepend.append(NSMenuItem.separator())

        for (idx, item) in itemsToPrepend.enumerated() {
            baseMenu.insertItem(item, at: idx)
        }
        return baseMenu
    }

    @objc private func handleApplySpellingSuggestion(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? SpellingMenuPayload,
              let replacement = payload.replacement else { return }
        onApplySpellingFix?(payload.issue, replacement)
    }

    @objc private func handleIgnoreSpellingWord(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? SpellingMenuPayload else { return }
        onIgnoreSpellingWord?(payload.issue.word)
    }

    public override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)

        // Highlight active cursor line across the editor width when no selection is active
        let sel = selectedRange()
        guard sel.length == 0,
              let layoutManager = self.layoutManager
        else { return }

        let nsString = self.string as NSString
        guard sel.location <= nsString.length && nsString.length > 0 else { return }

        let safeCharIdx = min(sel.location, max(0, nsString.length - 1))
        let glyphIdx = layoutManager.glyphIndexForCharacter(at: safeCharIdx)
        var lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIdx, effectiveRange: nil)
        if lineRect.height > 0 {
            lineRect.origin.y += textContainerInset.height
            lineRect.origin.x = 0
            lineRect.size.width = bounds.width

            let activeLineColor = lightBackground
                ? NSColor(srgbRed: 0.94, green: 0.96, blue: 0.99, alpha: 1.0) // Subtle cool highlight #F0F5FC
                : NSColor(srgbRed: 0.10, green: 0.13, blue: 0.19, alpha: 1.0)
            activeLineColor.setFill()
            lineRect.intersection(bounds).fill()
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

        let editorFont = LaTeXSyntaxHighlighter.resolveFont(name: editorFontName, size: editorFontSize, weight: .regular)
        let glyphIndex = layoutManager.glyphIndexForCharacter(at: max(0, sel.location - 1))
        let charPoint: NSPoint
        if sel.location == 0 {
            charPoint = NSPoint(x: textContainerInset.width + 5, y: textContainerInset.height)
        } else {
            let lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
            let loc = layoutManager.location(forGlyphAt: glyphIndex)
            let prevChar = nsString.substring(with: NSRange(location: sel.location - 1, length: 1)) as NSString
            let advance = prevChar.size(withAttributes: [.font: editorFont]).width
            charPoint = NSPoint(
                x: textContainerInset.width + lineRect.origin.x + loc.x + advance,
                y: textContainerInset.height + lineRect.origin.y
            )
        }

        // Only render the first line of the ghost suffix inline so multiline completions stay clean
        let firstLineGhost = ghostSuffix.components(separatedBy: .newlines).first ?? ghostSuffix
        let ghostColor = lightBackground
            ? NSColor(srgbRed: 0.52, green: 0.58, blue: 0.68, alpha: 1.0)
            : NSColor(srgbRed: 0.45, green: 0.52, blue: 0.62, alpha: 1.0)
        let ghostAttrs: [NSAttributedString.Key: Any] = [
            .font: editorFont,
            .foregroundColor: ghostColor
        ]
        (firstLineGhost as NSString).draw(at: charPoint, withAttributes: ghostAttrs)
    }
}

public struct LaTeXCodeEditorView: NSViewRepresentable {
    @Binding public var text: String
    @Binding public var cursorLine: Int
    @Binding public var jumpToLineRequest: Int?
    @Binding public var pendingInsertion: EditorInsertionRequest?
    public var diagnostics: [LaTeXDiagnostic]
    public var fontSize: CGFloat
    public var fontName: String
    public var customFonts: [CustomFontRecord]
    public var bibEntries: [BibEntry]
    public var spellingIssues: [SpellingIssue]
    public var spellCheckEnabled: Bool
    public var lightBackground: Bool
    public var onDropImageFile: ((URL) -> Void)?
    public var onDropFontFiles: (([URL]) -> Void)?
    public var onDropBibFile: ((URL) -> Void)?
    public var onApplySpellingFix: ((SpellingIssue, String) -> Void)?
    public var onIgnoreSpellingWord: ((String) -> Void)?

    public init(
        text: Binding<String>,
        cursorLine: Binding<Int>,
        jumpToLineRequest: Binding<Int?>,
        pendingInsertion: Binding<EditorInsertionRequest?> = .constant(nil),
        diagnostics: [LaTeXDiagnostic],
        fontSize: CGFloat = 13.5,
        fontName: String = "",
        customFonts: [CustomFontRecord] = [],
        bibEntries: [BibEntry] = [],
        spellingIssues: [SpellingIssue] = [],
        spellCheckEnabled: Bool = false,
        lightBackground: Bool = true,
        onDropImageFile: ((URL) -> Void)? = nil,
        onDropFontFiles: (([URL]) -> Void)? = nil,
        onDropBibFile: ((URL) -> Void)? = nil,
        onApplySpellingFix: ((SpellingIssue, String) -> Void)? = nil,
        onIgnoreSpellingWord: ((String) -> Void)? = nil
    ) {
        self._text = text
        self._cursorLine = cursorLine
        self._jumpToLineRequest = jumpToLineRequest
        self._pendingInsertion = pendingInsertion
        self.diagnostics = diagnostics
        self.fontSize = fontSize
        self.fontName = fontName
        self.customFonts = customFonts
        self.bibEntries = bibEntries
        self.spellingIssues = spellingIssues
        self.spellCheckEnabled = spellCheckEnabled
        self.lightBackground = lightBackground
        self.onDropImageFile = onDropImageFile
        self.onDropFontFiles = onDropFontFiles
        self.onDropBibFile = onDropBibFile
        self.onApplySpellingFix = onApplySpellingFix
        self.onIgnoreSpellingWord = onIgnoreSpellingWord
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    private func applyTheme(to scrollView: NSScrollView, textView: LaTeXEditorTextView, gutter: LineNumberGutterView?) {
        let bg = lightBackground
            ? NSColor(srgbRed: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
            : NSColor(srgbRed: 0.05, green: 0.07, blue: 0.09, alpha: 1.0)
        scrollView.appearance = NSAppearance(named: lightBackground ? .aqua : .darkAqua)
        scrollView.drawsBackground = true
        scrollView.backgroundColor = bg

        textView.lightBackground = lightBackground
        textView.drawsBackground = true
        textView.backgroundColor = bg
        textView.insertionPointColor = lightBackground
            ? NSColor(srgbRed: 0.06, green: 0.09, blue: 0.16, alpha: 1.0)
            : NSColor.white
        textView.selectedTextAttributes = [
            .backgroundColor: lightBackground
                ? NSColor(srgbRed: 0.74, green: 0.85, blue: 1.0, alpha: 0.65)
                : NSColor(srgbRed: 0.18, green: 0.36, blue: 0.65, alpha: 0.65)
        ]
        gutter?.lightBackground = lightBackground
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
        textView.delegate = context.coordinator
        textView.onDropImageFile = onDropImageFile
        textView.onDropFontFiles = onDropFontFiles
        textView.onDropBibFile = onDropBibFile
        textView.onApplySpellingFix = onApplySpellingFix
        textView.onIgnoreSpellingWord = onIgnoreSpellingWord
        textView.editorFontSize = fontSize
        textView.editorFontName = fontName

        scrollView.documentView = textView

        let gutter = LineNumberGutterView(textView: textView)
        scrollView.verticalRulerView = gutter
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true

        context.coordinator.textView = textView
        context.coordinator.gutterView = gutter
        context.coordinator.lastFontSize = fontSize
        context.coordinator.lastFontName = fontName
        context.coordinator.lastLightBackground = lightBackground

        applyTheme(to: scrollView, textView: textView, gutter: gutter)

        textView.string = text
        LaTeXSyntaxHighlighter.shared.highlight(
            textStorage: textStorage,
            fontSize: fontSize,
            fontName: fontName,
            lightBackground: lightBackground
        )
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

        textView.onDropImageFile = onDropImageFile
        textView.onDropFontFiles = onDropFontFiles
        textView.onDropBibFile = onDropBibFile
        textView.onApplySpellingFix = onApplySpellingFix
        textView.onIgnoreSpellingWord = onIgnoreSpellingWord

        let themeOrFontChanged = (context.coordinator.lastLightBackground != lightBackground) ||
                                 (context.coordinator.lastFontSize != fontSize) ||
                                 (context.coordinator.lastFontName != fontName)

        if themeOrFontChanged {
            context.coordinator.lastLightBackground = lightBackground
            context.coordinator.lastFontSize = fontSize
            context.coordinator.lastFontName = fontName
            textView.editorFontSize = fontSize
            textView.editorFontName = fontName
            applyTheme(to: scrollView, textView: textView, gutter: context.coordinator.gutterView)
        }

        if (textView.string != text && !context.coordinator.isEditingText) || themeOrFontChanged {
            let oldText = textView.string
            let selectedRanges = textView.selectedRanges
            let adjustedRanges: [NSValue]
            if oldText != text {
                let oldNS = oldText as NSString
                let newNS = text as NSString
                let delta = newNS.length - oldNS.length
                let commonPrefixLen = (oldText.commonPrefix(with: text) as NSString).length
                adjustedRanges = selectedRanges.map { value in
                    let r = value.rangeValue
                    if delta != 0,
                       r.location >= commonPrefixLen,
                       r.location + r.length <= oldNS.length,
                       r.location + delta >= 0,
                       r.location + r.length + delta <= newNS.length {
                        let oldSuffix = oldNS.substring(from: r.location)
                        let newSuffix = newNS.substring(from: r.location + delta)
                        if oldSuffix == newSuffix {
                            return NSValue(range: NSRange(location: r.location + delta, length: r.length))
                        }
                    }
                    let clampedLoc = min(max(0, r.location), newNS.length)
                    let clampedLen = min(r.length, newNS.length - clampedLoc)
                    return NSValue(range: NSRange(location: clampedLoc, length: clampedLen))
                }
                textView.string = text
            } else {
                adjustedRanges = selectedRanges
            }
            LaTeXSyntaxHighlighter.shared.highlight(
                textStorage: textStorage,
                fontSize: fontSize,
                fontName: fontName,
                lightBackground: lightBackground
            )
            textView.selectedRanges = adjustedRanges
            textView.needsDisplay = true
            context.coordinator.gutterView?.needsDisplay = true
        }

        context.coordinator.updateSpellingOverlays(
            issues: spellCheckEnabled ? spellingIssues : []
        )
        context.coordinator.updateDiagnostics(diagnostics)

        if let request = pendingInsertion, context.coordinator.lastHandledInsertionID != request.id {
            context.coordinator.lastHandledInsertionID = request.id
            DispatchQueue.main.async {
                context.coordinator.performCaretInsertion(request)
                self.pendingInsertion = nil
            }
        }

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
        var lastFontSize: CGFloat = 13.5
        var lastFontName: String = ""
        var lastLightBackground: Bool = true
        var lastHandledInsertionID: UUID?

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
            LaTeXSyntaxHighlighter.shared.highlight(
                textStorage: textStorage,
                fontSize: parent.fontSize,
                fontName: parent.fontName,
                lightBackground: parent.lightBackground
            )
            updateCursorLine()
            refreshAutoComplete()
            textView.needsDisplay = true
            gutterView?.needsDisplay = true
            isEditingText = false
        }

        public func textViewDidChangeSelection(_ notification: Notification) {
            updateCursorLine()
            textView?.needsDisplay = true
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

            let suggestions = LaTeXAutoCompleteEngine.suggestions(
                for: query,
                in: source,
                customFonts: parent.customFonts,
                bibEntries: parent.bibEntries
            )
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
                LaTeXSyntaxHighlighter.shared.highlight(
                    textStorage: textStorage,
                    fontSize: parent.fontSize,
                    fontName: parent.fontName,
                    lightBackground: parent.lightBackground
                )
                updateCursorLine()
                textView.needsDisplay = true
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

        func updateSpellingOverlays(issues: [SpellingIssue]) {
            guard let textView = textView,
                  let layoutManager = textView.layoutManager else { return }
            let length = (textView.string as NSString).length
            let fullRange = NSRange(location: 0, length: length)
            if length > 0 {
                layoutManager.removeTemporaryAttribute(.underlineStyle, forCharacterRange: fullRange)
                layoutManager.removeTemporaryAttribute(.underlineColor, forCharacterRange: fullRange)
            }
            textView.activeSpellingIssues = issues
            let underlineVal = NSUnderlineStyle.single.rawValue | NSUnderlineStyle.patternDot.rawValue
            for issue in issues {
                guard issue.nsRange.location >= 0,
                      NSMaxRange(issue.nsRange) <= length else { continue }
                layoutManager.addTemporaryAttributes([
                    .underlineStyle: underlineVal,
                    .underlineColor: NSColor.systemRed
                ], forCharacterRange: issue.nsRange)
            }
        }

        func performCaretInsertion(_ request: EditorInsertionRequest) {
            guard let textView = textView,
                  let textStorage = textView.textStorage else { return }
            let sel = textView.selectedRange()
            let length = (textView.string as NSString).length
            let safeRange = NSRange(
                location: min(sel.location, length),
                length: min(sel.length, max(0, length - min(sel.location, length)))
            )
            if textView.shouldChangeText(in: safeRange, replacementString: request.text) {
                isEditingText = true
                textStorage.replaceCharacters(in: safeRange, with: request.text)
                textView.didChangeText()

                let insertedLength = (request.text as NSString).length
                let newLength = (textView.string as NSString).length
                let targetCaret = max(0, min(newLength, safeRange.location + insertedLength - request.cursorBacktrackOffset))
                textView.setSelectedRange(NSRange(location: targetCaret, length: 0))

                parent.text = textView.string
                LaTeXSyntaxHighlighter.shared.highlight(
                    textStorage: textStorage,
                    fontSize: parent.fontSize,
                    fontName: parent.fontName,
                    lightBackground: parent.lightBackground
                )
                updateCursorLine()
                textView.scrollRangeToVisible(NSRange(location: targetCaret, length: 0))
                textView.needsDisplay = true
                gutterView?.needsDisplay = true
                isEditingText = false
            }
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
