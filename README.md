# LaTeXaP — Modern macOS LaTeX3 Studio

**LaTeXaP** is a native macOS application built with **Swift, SwiftUI, AppKit, and PDFKit**, engineered specifically for authoring and rendering **LaTeX3 (`expl3` + `xparse`)** documents with real-time compilation, automatic CTAN package management via an embedded **Tectonic** engine, and bidirectional **SyncTeX** navigation.

## Key Features

1. **Real-Time LaTeX3 (`expl3` & `xparse`) Compilation**
   - Uses the embedded **Tectonic** engine (`XeTeX` + `LaTeX3` programming layer) with debounced live compilation as you type.
   - Zero TeX Live setup required: Tectonic automatically fetches and caches any missing CTAN packages (`siunitx`, `mathtools`, `tikz`, `booktabs`, `cleveref`, etc.) on demand.

2. **Split-Pane Native Editor & PDF Preview**
   - **Syntax-Highlighted Editor (`NSTextView`)**: Custom highlighting for `expl3` namespaces (`\module_func:Npn`, `\l_tmpa_tl`, `\ExplSyntaxOn`, `\NewDocumentCommand`, `\keys_define:nn`), standard LaTeX commands, environments, inline math, macro tokens (`#1`, `##1`), and comments.
   - **Line Number & Diagnostic Gutter**: Displays line numbers, active cursor row, and inline red/amber markers for compilation errors and warnings.
   - **Bidirectional SyncTeX (`SyncTeXParser`)**:
     - **Backward Sync (PDF → Editor)**: **⌘-Click** (or double-click) anywhere in the rendered PDF preview to jump directly to the corresponding line in the `.tex` editor.
     - **Forward Sync (Editor → PDF)**: Click **Sync PDF** (`⇧⌘J`) or click an item in the Outline sidebar to scroll and highlight the corresponding region in the PDF.

3. **Live Diagnostics & TeX Transcript Console**
   - Structured parser extracts line-accurate LaTeX/Tectonic errors and warnings.
   - Click any diagnostic item to jump directly to the offending source line.

4. **LaTeX3 Snippets, CTAN Package Browser & Starter Templates**
   - Includes ready-to-compile templates:
     - *LaTeX3 (`expl3` + `xparse`) Showcase* (`l3int`, `l3fp`, `l3seq`, custom environments)
     - *LaTeX3 Key-Value Interface (`l3keys`)* (`\keys_define:nn`)
     - *Academic Research Article*
     - *TikZ & PGF Vector Diagrams*
   - One-click insertion of `expl3` blocks, `xparse` commands, and common CTAN packages.

5. **PDF Export**
   - Export compiled PDF documents directly via the toolbar (**Export PDF** / `⇧⌘E`).

## Building & Running

### Run from Terminal
```bash
swift run
```

### Package Standalone macOS `.app` Bundle (with Embedded Tectonic)
```bash
chmod +x scripts/package_app.sh
./scripts/package_app.sh
open build/LaTeXaP.app
```
