<p align="center">
  <img src="Resources/AppIcon-1024.png" width="136" alt="LaTeXaP Icon" />
</p>

<h1 align="center">LaTeXaP — Modern macOS LaTeX3 Studio</h1>

<p align="center">
  <strong>Native Swift &amp; SwiftUI Studio for Authoring LaTeX3 (<code>expl3</code> + <code>xparse</code>) Documents with Live Tectonic Rendering &amp; Bidirectional SyncTeX</strong>
</p>

---

## Screenshots

### 1. LaTeX3 (`expl3` + `xparse`) Workspace, Structure Outline & Context Suggestions
![LaTeX3 Studio Workspace](docs/screenshots/01-latex3-studio-workspace.png)

### 2. Two-Column Academic Research Article & CTAN Package Browser
![Academic Research Article and CTAN Package Browser](docs/screenshots/02-academic-paper-and-packages.png)

### 3. Python & Scientific Computing in LaTeX3 + Snippet Library
![Python and Scientific Computing in LaTeX3](docs/screenshots/03-python-scientific-and-snippets.png)

---

## Key Features

1. **Real-Time LaTeX3 (`expl3` & `xparse`) Compilation**
   - Uses an embedded **Tectonic** engine (`XeTeX` + `LaTeX3` programming layer) with debounced live compilation as you type.
   - Zero TeX Live setup required: Tectonic automatically fetches and caches any missing CTAN packages (`siunitx`, `mathtools`, `tikz`, `booktabs`, `cleveref`, `pythonhighlight`, etc.) on demand.

2. **Split-Pane Native Editor & PDF Preview**
   - **Syntax-Highlighted Editor (`NSTextView`)**: Custom highlighting for `expl3` namespaces (`\module_func:Npn`, `\l_tmpa_tl`, `\ExplSyntaxOn`, `\NewDocumentCommand`, `\keys_define:nn`), standard LaTeX commands, environments, inline math, macro tokens (`#1`, `##1`), and comments.
   - **Real-Time Line Auto-Completion**: Floating completion popup + inline ghost text for `expl3`/`xparse` commands, full `\begin{...}...\end{...}` environment expansion, `\usepackage{...}` catalog completion, and dynamic indexing of user-defined macros in the current document.
   - **Line Number & Diagnostic Gutter**: Displays line numbers, active cursor row, and inline red/amber markers for compilation errors and warnings.
   - **Bidirectional SyncTeX (`SyncTeXParser`)**:
     - **Backward Sync (PDF → Editor)**: **⌘-Click** (or double-click) anywhere in the rendered PDF preview to jump directly to the corresponding line in the `.tex` editor.
     - **Forward Sync (Editor → PDF)**: Click **Sync PDF** (`⇧⌘J`) or click an item in the Outline sidebar to scroll and highlight the corresponding region in the PDF.

3. **Diagnostics, Full TeX Transcript & Context Suggestions Drawer**
   - **Diagnostics**: Structured parser extracts line-accurate LaTeX/Tectonic errors and warnings; click any diagnostic to jump to the offending line.
   - **Full TeX Transcript**: Inspect the complete `.log` output.
   - **Context Suggestions**: Region-aware guidance that adapts to where your cursor is (`Empty Document — Getting Started`, `Document Preamble`, `LaTeX3 Programming Block (\ExplSyntaxOn)`, or active `\begin{...}` environments) with one-click code & package insertion.

4. **Python & Scientific Computing + Starter Templates**
   - Includes 5 ready-to-compile starter templates:
     - *LaTeX3 (`expl3` + `xparse`) Showcase* (`l3int`, `l3fp`, `l3seq`, custom environments)
     - *Academic Research Article* (Two-column IEEE/ACM-style with spanning abstract, theorems, and bibliography)
     - *Python & Scientific Computing in LaTeX3* (`listings`, `pythonhighlight`, `pythontex`, `minted`, `algorithm2e`)
     - *LaTeX3 Key-Value Interface (`l3keys`)* (`\keys_define:nn`)
     - *TikZ & PGF Vector Diagrams*

5. **Custom Fonts & Editor Typography (`v0.1.2`)**
   - **Font Manager (`⇧⌘F`) & Fonts Sidebar Tab**: Import local `.ttf`, `.otf`, and `.ttc` font files (via **View → Add Custom Font...**, **Add Font...**, or drag-and-drop), preview live customizable specimens (`10–36 pt`, Light/Dark surface), rename, and safely remove managed fonts with reference-aware confirmation.
   - **XeTeX (`fontspec`) & CTAN Font Presets**: Apply custom fonts or macOS system fonts directly to your document's **Main** (`\setmainfont`), **Sans** (`\setsansfont`), **Mono** (`\setmonofont`), or named **`\newfontfamily`** preamble roles, or insert one-click CTAN font packages (`libertinus`, `ebgaramond`, `fira`, `plex`, `lmodern`, `tgpagella`). Managed fonts are stored non-invasively in `~/Library/Application Support/LaTeXaP/Fonts/` and automatically exposed to Tectonic.
   - **Code Editor Font Picker**: Choose System Monospaced, any macOS monospaced font, or an imported custom font (`10–24 pt`) from the editor header popover or Font Manager, persisted across launches.

6. **PDF Export**
   - Export compiled PDF documents directly via the toolbar (**Export PDF** / `⇧⌘E`).

See [CHANGELOG.md](CHANGELOG.md) for release notes and [docs/custom-fonts-architecture.md](docs/custom-fonts-architecture.md) / [docs/custom-fonts-ux.md](docs/custom-fonts-ux.md) for technical and UX design details.

---

## Installation

### Option 1: Install Latest Release via Terminal (Recommended — No Gatekeeper Prompt)
Run these commands in Terminal to download the latest release directly from GitHub into `/Applications` and launch **LaTeXaP**:

```bash
curl -fsSL -o /tmp/LaTeXaP.zip https://github.com/jameslloyd/LaTeXaP/releases/latest/download/LaTeXaP-macOS.zip
ditto -x -k /tmp/LaTeXaP.zip /Applications
xattr -cr /Applications/LaTeXaP.app
rm -f /tmp/LaTeXaP.zip
open /Applications/LaTeXaP.app
```

> *Note*: The `.app` bundle includes a standalone, self-contained **Tectonic** typesetting engine — no separate TeX Live, MacTeX, or Homebrew installation is required.

### Option 2: Download from GitHub Releases (Browser)
1. **Download**: Grab the latest `LaTeXaP-macOS.zip` archive from [**GitHub Releases**](https://github.com/jameslloyd/LaTeXaP/releases/latest).
2. **Unzip**: Double-click `LaTeXaP-macOS.zip` in Finder to extract **`LaTeXaP.app`**.
3. **Move to Applications**: Drag **`LaTeXaP.app`** into your **`/Applications`** folder.
4. **Launch**: Open **LaTeXaP** from `/Applications` or Spotlight (`⌘Space`).
   - *macOS Gatekeeper tip*: Because the release binary is ad-hoc signed (not notarized with a paid Apple Developer ID), macOS may show *"Apple could not verify LaTeXaP"* when downloaded through a web browser. Either click **Open Anyway** in **System Settings → Privacy & Security**, or strip the browser quarantine attribute in Terminal:
     ```bash
     xattr -cr /Applications/LaTeXaP.app
     ```

---

## Building from Source

### Run Directly via Swift Package Manager
```bash
git clone https://github.com/jameslloyd/LaTeXaP.git
cd LaTeXaP
swift run
```

### Package Standalone macOS `.app` Bundle (with Embedded Tectonic)
```bash
./scripts/package_app.sh
open build/LaTeXaP.app
```
