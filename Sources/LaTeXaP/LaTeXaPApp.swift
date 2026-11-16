import AppKit
import SwiftUI

enum AppMetadata {
    static let version = "0.1.2"
    static let build = "3"
    static let repoURLString = "https://github.com/jameslloyd/LaTeXaP"
    static let repoGitURLString = "https://github.com/jameslloyd/LaTeXaP.git"
    static let repoURL = URL(string: "https://github.com/jameslloyd/LaTeXaP")!

    @MainActor
    static func showAboutPanel() {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineSpacing = 3

        let bodyFont = NSFont.systemFont(ofSize: 11.5)
        let linkFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)

        let credits = NSMutableAttributedString(
            string: "Modern macOS LaTeX3 (expl3 + xparse) Studio\nEmbedded Tectonic Engine • Live SyncTeX Preview\n\nGitHub Repository:\n",
            attributes: [
                .font: bodyFont,
                .foregroundColor: NSColor.secondaryLabelColor,
                .paragraphStyle: paragraph
            ]
        )

        let linkAttr = NSAttributedString(
            string: repoGitURLString,
            attributes: [
                .font: linkFont,
                .link: repoURL,
                .foregroundColor: NSColor.linkColor,
                .paragraphStyle: paragraph
            ]
        )
        credits.append(linkAttr)

        NSApplication.shared.orderFrontStandardAboutPanel(options: [
            .applicationName: "LaTeXaP",
            .applicationVersion: version,
            .version: build,
            .credits: credits
        ])
    }
}

@main
struct LaTeXaPApp: App {
    @StateObject private var viewModel = DocumentViewModel()

    init() {
        NSApplication.shared.setActivationPolicy(.regular)
        if let icnsPath = Bundle.main.path(forResource: "AppIcon", ofType: "icns"),
           let icon = NSImage(contentsOfFile: icnsPath) {
            NSApplication.shared.applicationIconImage = icon
        } else {
            let devIconURL = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Resources/AppIcon.icns")
            if let icon = NSImage(contentsOf: devIconURL) {
                NSApplication.shared.applicationIconImage = icon
            }
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    var body: some Scene {
        WindowGroup("LaTeXaP — Modern LaTeX3 Studio") {
            MainWorkspaceView(viewModel: viewModel)
                .frame(minWidth: 980, minHeight: 640)
                .onAppear {
                    if ProcessInfo.processInfo.environment["LATEXAP_EXPORT_SCREENSHOTS"] == "1" {
                        Task { @MainActor in
                            await Self.exportScreenshots(viewModel: viewModel)
                        }
                    }
                }
        }
        .defaultSize(width: 1360, height: 860)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About LaTeXaP") {
                    AppMetadata.showAboutPanel()
                }
                Button("Check for Updates...") {
                    viewModel.checkForUpdatesInteractively()
                }
                Button("GitHub Repository (jameslloyd/LaTeXaP)...") {
                    NSWorkspace.shared.open(AppMetadata.repoURL)
                }
            }

            CommandGroup(replacing: .help) {
                Button("LaTeXaP Version \(AppMetadata.version) (Build \(AppMetadata.build))") {
                    AppMetadata.showAboutPanel()
                }
                Button("Check for Updates...") {
                    viewModel.checkForUpdatesInteractively()
                }
                Divider()
                Button("LaTeXaP on GitHub (https://github.com/jameslloyd/LaTeXaP.git)") {
                    NSWorkspace.shared.open(AppMetadata.repoURL)
                }
            }

            CommandGroup(replacing: .newItem) {
                Menu("New from LaTeX3 Template") {
                    ForEach(LaTeXCatalog.templates) { template in
                        Button(template.name) {
                            viewModel.loadTemplate(template)
                        }
                    }
                }
                Button("Open LaTeX File...") {
                    viewModel.openTexFile()
                }
                .keyboardShortcut("o", modifiers: [.command])

                Divider()

                Button("Save") {
                    viewModel.saveTexFile(saveAs: false)
                }
                .keyboardShortcut("s", modifiers: [.command])

                Button("Save As...") {
                    viewModel.saveTexFile(saveAs: true)
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])

                Divider()

                Button("Export PDF...") {
                    viewModel.exportPDF()
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
            }

            CommandMenu("Typeset & LaTeX3") {
                Button("Compile Now (Tectonic)") {
                    Task { await viewModel.compileNow() }
                }
                .keyboardShortcut("b", modifiers: [.command])

                Toggle("Live Auto-Compile", isOn: $viewModel.autoCompileEnabled)

                Divider()

                Button("Forward SyncTeX (Editor → PDF)") {
                    viewModel.triggerForwardSync()
                }
                .keyboardShortcut("j", modifiers: [.command, .shift])

                Button("Toggle Diagnostics Console") {
                    viewModel.showConsoleDrawer.toggle()
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])

                Divider()

                Menu("Insert LaTeX3 (expl3 / xparse) Snippet") {
                    ForEach(LaTeXCatalog.snippets) { snippet in
                        Button(snippet.title) {
                            viewModel.insertSnippet(snippet)
                        }
                    }
                }
            }

            CommandMenu("View") {
                Toggle("Light Editor Background", isOn: $viewModel.useLightEditorBackground)

                Divider()

                Button("Add Custom Font...") {
                    viewModel.openImportFontPanel()
                }

                Button("Manage Fonts...") {
                    viewModel.showFontManagerSheet = true
                }
                .keyboardShortcut("f", modifiers: [.command, .shift])

                Button("Reset Editor Font to Default") {
                    viewModel.resetEditorFontToDefault()
                }

                Divider()

                Button("Increase Editor Font Size") {
                    viewModel.editorFontSize = min(24, viewModel.editorFontSize + 1)
                }
                .keyboardShortcut("+", modifiers: [.command])

                Button("Decrease Editor Font Size") {
                    viewModel.editorFontSize = max(10, viewModel.editorFontSize - 1)
                }
                .keyboardShortcut("-", modifiers: [.command])
            }
        }
    }

    @MainActor
    private static func exportScreenshots(viewModel: DocumentViewModel) async {
        let outDir = URL(fileURLWithPath: "/Users/james/code/LaTeXaP/docs/screenshots")
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        // Wait for initial compilation & PDF render
        try? await Task.sleep(nanoseconds: 2_600_000_000)

        func snapshotWindow(to filename: String) {
            guard let window = NSApplication.shared.windows.first(where: { $0.isVisible && $0.frame.width > 600 }),
                  let contentView = window.contentView?.superview ?? window.contentView
            else { return }
            let bounds = contentView.bounds
            guard let rep = contentView.bitmapImageRepForCachingDisplay(in: bounds) else { return }
            contentView.cacheDisplay(in: bounds, to: rep)
            if let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: outDir.appendingPathComponent(filename))
            }
        }

        // 1. Main Workspace: LaTeX3 Showcase + Outline + Context Suggestions Drawer
        viewModel.loadTemplate(LaTeXCatalog.defaultTemplate)
        viewModel.selectedSidebarTab = "Outline"
        viewModel.showConsoleDrawer = true
        viewModel.selectedDiagnosticTab = 2
        viewModel.cursorLine = 32
        try? await Task.sleep(nanoseconds: 2_800_000_000)
        snapshotWindow(to: "01-latex3-studio-workspace.png")

        // 2. Academic Research Article Template + Packages Sidebar (showing Python & LaTeX3 packages)
        if let academic = LaTeXCatalog.templates.first(where: { $0.id == "academic-paper" }) {
            viewModel.loadTemplate(academic)
        }
        viewModel.selectedSidebarTab = "Packages"
        viewModel.packageSearchText = ""
        viewModel.showConsoleDrawer = false
        try? await Task.sleep(nanoseconds: 2_800_000_000)
        snapshotWindow(to: "02-academic-paper-and-packages.png")

        // 3. Python & Scientific Computing Template + LaTeX3 Snippets Sidebar
        if let pythonTpl = LaTeXCatalog.templates.first(where: { $0.id == "python-scientific" }) {
            viewModel.loadTemplate(pythonTpl)
        }
        viewModel.selectedSidebarTab = "LaTeX3"
        viewModel.showConsoleDrawer = true
        viewModel.selectedDiagnosticTab = 0
        try? await Task.sleep(nanoseconds: 2_500_000_000)
        snapshotWindow(to: "03-python-scientific-and-snippets.png")

        NSApplication.shared.terminate(nil)
    }
}
