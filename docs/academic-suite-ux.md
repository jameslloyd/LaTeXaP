# Academic Paper Authoring Suite (`v0.2.0`) — UX & Accessibility Specification

> **Scope:** User flows, layout hierarchy, interaction states, and VoiceOver/keyboard accessibility for LaTeXaP's Academic Paper Authoring Suite (`v0.2.0`).  
> **Builds on:** Existing workspace patterns in `MainWorkspaceView.swift`, `VisualToolsSheetView.swift`, `LaTeXCodeEditorView.swift`, and `docs/custom-fonts-ux.md`.  
> **Non-goals:** Backend architecture and Swift API signatures (see `docs/academic-suite-architecture.md`) and application source code.

---

## 1. Design Principles for Student Workflows

1. **Hide Boilerplate, Keep Source Transparent**: Every visual builder (Citation Picker, Table Grid, `pgfplots` Chart, Figure Assistant, Paper Wizard) previews the exact LaTeX code it inserts so students learn TeX without wrestling syntax under deadline pressure.
2. **Safe by Default for Submissions**: Prevent broken absolute image paths, unresolved `??` citations, and uncaught prose typos before a student exports to Canvas, Gradescope, Overleaf, or arXiv.
3. **Calm, Progressive Disclosure**: Keep the main split editor + live PDF preview uncluttered; surface advanced stats, rubric budgets, and wizard forms in focused popovers, sheets, and drawer tabs.

---

## 2. Feature UX Flows & Layout Specifications

### 2.1 Smart Citation Search, `.bib` Import & Bibliography Style Switcher
**Surface:** Left Sidebar → **BibTeX** tab (`MainWorkspaceView.bibliographyTabView`) + **Citation Quick-Picker Popover** (`⌘⇧K`).

- **Information Hierarchy (Top → Bottom)**:
  1. **Bibliography Style Bar**: Compact dropdown/segmented selector (`APA`, `IEEE`, `ACM`, `MLA`, `Chicago`, `Nature`) + **"Import .bib"** button (also accepts `.bib` drag-and-drop anywhere on the BibTeX pane).
  2. **Smart Lookup Input**: Unified search field (`"DOI, arXiv ID, ISBN, or Paper Title..."`) with `Return` submit and loading spinner.
     - *Title/Keyword Search*: Displays a compact inline results list (up to 5 CrossRef/arXiv matches showing Title, First Author, Year, Venue) with a 1-click **`+ Add`** button per result.
     - *Direct DOI / arXiv ID*: Fetches and adds immediately, scrolling the new entry into view.
  3. **Library Filter & Entries List**: Search input (`"Filter saved citations & labels..."`) above grouped sections:
     - **Bibliography Entries (`N`)**: Shows cite key, year, title, author, and an **`Uncited`** amber pill if not yet referenced in `sourceText`.
     - **Insertion Controls per Entry**: Quick style chips (**`\cite`**, **`\parencite`**, **`\textcite`**) plus an optional compact locator popover/field (e.g., `p. 12`) that inserts at the active editor caret.
     - **Cross-Reference Labels (`M`)**: Existing `\label{...}` list with 1-click `\ref{...}` / `\cref{...}` insertion.
- **Interaction States**:
  - *Loading*: Inline `ProgressView` next to lookup field; lookup button disabled; existing list stays interactive.
  - *Empty*: Dropzone card (`"No Citations Yet — Drop a .bib file from Zotero/Scholar, or search by DOI, arXiv, or title above."`).
  - *Validation / Error*: Dismissible inline red banner below lookup bar for offline/timeout, invalid DOI/ISBN, malformed `.bib` file (`"Could not parse BibTeX on line N of refs.bib"`), or duplicate key collision (`Replace` / `Keep Both` / `Cancel`).
  - *Success*: Brief confirmation caption (`"Added 'vaswani2017attention' to bibliography"`) + live Tectonic recompile.

---

### 2.2 Plain-English Error Demystifier, 1-Click Auto-Fix & Pre-Flight Linter
**Surface:** Bottom **Diagnostics Drawer** (`DiagnosticsDrawerView`) + Status Bar indicator.

- **Drawer Tabs**: `Diagnostics (N)` | `Pre-Flight (M)` | `TeX Transcript` | `Context Suggestions (K)`.
- **Plain-English Diagnostics (`Diagnostics` tab)**:
  - Each row pairs the line badge (`Line 42`) and severity icon with:
    1. **Plain-English Headline** (e.g., *"Unescaped `&` character in body text"* instead of only *"Misplaced alignment tab character &"*).
    2. **Brief Guidance** (1 sentence explaining why TeX stopped, e.g., *"`&` is reserved for table/align columns. Escape it as `\&` in prose."*).
    3. **1-Click Auto-Fix Button** (`.borderedProminent`, `.controlSize(.small)`) when a deterministic fix exists (e.g., **`Escape & → \&`**, **`Add \usepackage{amsmath}`**, **`Wrap in $...$`**), alongside a secondary disclosure/tooltip showing the raw Tectonic log line.
- **Academic Pre-Flight Tab (`Pre-Flight`)**:
  - Categorized readiness checklist computed live:
    - **Unresolved Citations** (`\cite{missing}` not in `.bib`/bibliography) → click to jump to line or open BibTeX search pre-filled with key.
    - **Broken References** (`\ref{missing}` with no `\label{missing}`) → click to jump to line.
    - **Uncited Bibliography Entries** → click to jump/cite or remove unused entry.
    - **Missing Figure Files / Absolute Paths** → 1-click **`Relocate to figures/`** or browse replacement.
    - **Layout Warnings** (`Overfull \hbox` text margin overflows) → click to jump to line.
  - *Empty/Clean State*: Green seal banner: **`"All Pre-Flight Checks Passed — Ready to export PDF or submission bundle."`**

---

### 2.3 Academic Starter Templates & Paper Setup Wizard
**Surface:** Left Sidebar → **Templates** tab + **Paper Setup Wizard Sheet** (`620 × 500 pt`, triggered via **`New with Setup Wizard...`** button in Templates tab or `File → New Academic Paper Wizard...` `⇧⌘N`).

- **Categorized Template Gallery (Sidebar)**:
  - Group templates under clear headers: **Academic Papers** (`APA 7th Student Paper`, `IEEE Conference`, `ACM acmart`, `MLA Essay`), **STEM & Theses** (`STEM Lab Report`, `University Thesis / Dissertation`, `Beamer Presentation`), and **LaTeX3 Core** (existing `expl3` / `l3keys` / `Python` templates).
  - Each card offers **`Load Starter`** (quick load) and **`Customize...`** (opens Wizard pre-selected to that template).
- **Paper Setup Wizard Sheet**:
  1. **Header**: Title (`New Academic Paper`), Template selector grid/list on the left (`200 pt`), Configuration form on the right.
  2. **Form Fields**:
     - *Metadata*: Document Title (required), Author Name(s), Institution / University, Course / Venue, Date (default `\today`).
     - *Formatting*: Paper Size (`US Letter` | `A4`), Line Spacing (`Single` | `1.5×` | `Double`), Citation Style (`APA` | `IEEE` | `ACM` | `MLA` | `Chicago`).
     - *Review & Targets*: **Anonymized Blind Review** toggle (`"Hides author metadata & adds line numbers via lineno"`), optional **Target Word Count** and **Max Pages**.
  3. **Safety & Validation**:
     - Inline validation if Title is blank when required.
     - If the current editor has unsaved changes, show a confirmation prompt (`"Replace current document with new paper?"` → `Create New` / `Cancel`).
     - Footer CTA: **`Create Document`** (`.borderedProminent`).

---

### 2.4 Interactive Spreadsheet Table Editor, `pgfplots` Chart Builder & Figure Assistant
**Surface:** Expanded **`VisualToolsSheetView`** (`740 × 500 pt`) + **`FigureAssistantSheet`** (`560 × 440 pt`).

- **Visual Tools Sheet (`Math & Tables` toolbar button)**:
  - Segmented tabs: `Math Palette` | `Matrix Builder` | `Table Editor` | `Chart Builder (pgfplots)`.
  - **Math Palette**: Insert at **exact cursor selection** (not end-of-line); include quick **Academic Equation Templates** row (Fraction `\frac{a}{b}`, Piecewise `cases`, Summation `\sum_{i=1}^n`, Definite Integral `\int_a^b`, `siunitx` `\qty{9.81}{m/s^2}`).
  - **Table Editor (Spreadsheet Grid + CSV)**:
    - Mode toggle: **`Visual Grid`** | **`Paste CSV / TSV`**.
    - Visual Grid: Interactive table of editable `TextField` cells with tab/arrow cell traversal, **`+ Row` / `- Row`**, **`+ Col` / `- Col`** (clamped `1–12` cols, `1–30` rows), per-column alignment selector (`L` / `C` / `R`), **Bold Header Row** toggle, Caption & `tab:` Label fields, and collapsible live `booktabs` LaTeX preview.
    - Validation: Warn inline if label contains spaces/invalid characters; auto-ensure `\usepackage{booktabs}`.
  - **Chart Builder (`pgfplots`)**:
    - Left column: Chart Type (`Line`, `Bar`, `Scatter`), Chart Title, X-Axis Label, Y-Axis Label, and CSV `x, y` (or `label, value`) data editor with sample starter data.
    - Right column: Live generated `\begin{tikzpicture}...\begin{axis}...\end{axis}...\end{tikzpicture}` preview.
    - Footer CTA: **`Insert Chart at Line N`** (auto-adds `\usepackage{pgfplots}` + `\pgfplotsset{compat=1.18}`).

- **Figure Assistant Sheet (`Insert Figure` button or Image Drag-and-Drop)**:
  - Triggered when dropping `.png`/`.jpg`/`.jpeg`/`.pdf`/`.tiff` onto the editor or clicking `Insert Figure`.
  - Shows **Thumbnail Preview** + filename + dimensions.
  - Controls:
    - **Asset Path**: Copies image into a relative `figures/<sanitized-filename>` folder beside the saved `.tex` file (if document is untitled/unsaved, show clear info banner: `"Document is unsaved — save your .tex file to copy into figures/, or insert temporary path for preview."`).
    - **Layout Mode**: `Single Figure` | `Side-by-Side (2 Subfigures)` (second image picker optional).
    - **Width Slider**: `25%` to `100%` of `\textwidth` (default `75%`, live value readout).
    - **Placement**: `Here [htbp]` | `Top [t]` | `Page [p]`.
    - **Caption** & **`fig:` Label** text fields (auto-sanitized default label from filename).
  - Footer: **`Cancel`** and primary **`Insert Figure`** CTA (auto-ensures `graphicx` and `subcaption` when needed).

---

### 2.5 Word & Page Budget Tracker, Prose Spellcheck & Submission `.zip` Export
1. **Word & Page Budget Tracker (`statusBar` → Clickable Pill + Popover)**:
   - Status bar word count becomes an interactive button: e.g., `2,140 / 2,500 words • 6/8p` (or `2,140 words` when no targets are set).
   - **Paper Budget Popover (`280 pt` wide)**:
     - Breakdown rows: **Body Prose Words** (excluding preamble, TeX commands, math, bibliography), **Abstract Words**, **Math Blocks**, **Citations**, **PDF Pages**, and **Est. Reading Time**.
     - **Rubric Targets**: Optional numeric fields for **Target Words** (e.g., `2500`) and **Max Pages** (e.g., `8`).
     - **Progress Bar**: Color + icon + explicit text (`On track: 360 words remaining` in green/neutral, `Near limit (94%)` in amber, `Over limit by 140 words` in red).
2. **LaTeX-Aware Prose Spellcheck Toggle (Editor Header Bar)**:
   - Compact toggle pill (`Spellcheck`, `textformat.abc` icon, `⌥⌘;`) beside the Light/Dark background toggle.
   - Underlines misspelled **prose** words directly in `LaTeXEditorTextView` while ignoring `\commands`, `{arguments}` of `\cite`/`\ref`/`\label`/`\usepackage`, `$math$`, `\ExplSyntaxOn` blocks, and `% comments`.
   - Standard macOS right-click context menu offers spelling suggestions + `Ignore` / `Learn Spelling`.
3. **Submission Bundle Export (`Export Submission (.zip)...`, `⌥⇧⌘E`)**:
   - Accessible from the Toolbar Export menu (`Export PDF...` / `Export Submission Bundle (.zip)...`) and `File` menu.
   - If `Pre-Flight` has errors/warnings (e.g., unresolved `\cite` or absolute figure paths), show a concise pre-export alert listing count of issues with **`Review Pre-Flight`** (opens drawer) vs **`Export Anyway`**.
   - On completion, show a non-intrusive status banner with **`Reveal in Finder`** action; on failure, display an actionable error alert.

---

## 3. Accessibility Requirements (macOS VoiceOver / `NSAccessibility` & ARIA Equivalents)

### Semantic Landmarks & Structure
- **Sheets / Modals (`role="dialog"`, `aria-modal="true"`, `aria-labelledby`)**: `PaperSetupWizardView`, `VisualToolsSheetView`, and `FigureAssistantSheet` must expose clear header titles (`.accessibilityAddTraits(.isHeader)`) and support `Esc` dismissal.
- **Drawer & Sidebar Regions (`role="region"`, `role="navigation"`)**: Group Diagnostics/Pre-Flight rows, BibTeX results, and Template categories with `.accessibilityElement(children: .contain)` and section headers marked `.isHeader`.
- **Live Announcements (`aria-live="polite"` / `"assertive"`)**: Post `NSAccessibility.post(element:notification:userInfo:)` (`.announcementRequested`) when:
  - Citation search finishes or fails (`assertive` on error, `polite` on `"5 results found"`).
  - A 1-click Auto-Fix modifies the document (`"Applied fix: escaped ampersand on line 42"`).
  - Pre-Flight or Submission `.zip` export completes or fails.

### Labels, Hints & Interactive Grids
- **Icon-Only Buttons**: Every toolbar/row icon button (`+ Row`, `- Col`, `L/C/R` alignment, `Spellcheck`, `Auto-Fix`, `Import .bib`) must provide `.accessibilityLabel(...)` and `.accessibilityHint(...)`.
- **Spreadsheet Table Grid (`role="grid"`)**: Label each cell with row/column coordinates (e.g., `"Row 2, Column 3, Header"` or `"Row 2, Column 3"`) so VoiceOver users can edit cells confidently without losing spatial orientation.
- **Status Bar Budget Pill**: Combine into one clear readout: `.accessibilityLabel("Word and page budget")`, `.accessibilityValue("2,140 of 2,500 target words, 6 of 8 pages, on track")`, `.accessibilityHint("Opens breakdown and rubric target settings")`.
- **Inline Validation (`aria-invalid="true"`, `aria-describedby`)**: Expose validation text in `.accessibilityValue` / `.accessibilityHint` for invalid labels, empty wizard titles, or malformed CSV/DOI inputs.

### Focus Management & Keyboard Navigation
- **Focus Transfer & Restoration**:
  - Opening any sheet (`⇧⌘N` Wizard, `Math & Tables`, `Figure Assistant`) moves `@FocusState` to the first primary input (Title field, search box, or caption field) and restores focus to the triggering button on dismiss.
  - Clicking **`Apply Fix`** in Diagnostics preserves or moves focus cleanly to the next remaining diagnostic (or the empty-state banner if all errors are resolved).
  - Opening the **Paper Budget Popover** focuses the Target Words field; `Esc` closes and returns focus to the status bar pill.
- **Keyboard Shortcuts**:
  - `⇧⌘N`: New Academic Paper Wizard
  - `⌘⇧K`: Citation Quick-Picker / Jump to BibTeX Search
  - `⌥⌘;`: Toggle LaTeX-Aware Prose Spellcheck
  - `⌥⇧⌘E`: Export Submission Bundle (`.zip`)
  - `Tab` / `Shift+Tab` inside Table Editor moves cell-to-cell across rows; `↑`/`↓` navigates list/search results; `Return` inserts/confirms; `Esc` closes active popover/sheet.

### Color Contrast & Non-Color Signifiers
- **WCAG 2.1 AA Targets**: Maintain **`>= 4.5:1`** contrast for all body text, inline error captions, plain-English diagnostic explanations, and badges in both macOS Light (`Aqua`) and Dark (`DarkAqua`) modes; **`>= 3.0:1`** for table grid lines, dropzone borders, progress track outlines, and keyboard focus rings.
- **Never Color-Alone**: Pair every status color (green Pre-Flight pass / budget on-track, amber near-limit / uncited warning, red error / over-budget) with explicit SF Symbols (`checkmark.seal.fill`, `exclamationmark.triangle.fill`, `xmark.octagon.fill`) and text labels.
