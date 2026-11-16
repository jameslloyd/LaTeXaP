# Changelog

All notable changes to **LaTeXaP** are documented in this file.

## [0.2.0] — 2026-11-16

### Added — Academic Paper Authoring Suite
- **Smart Citations & `.bib` Management (`⇧⌘K`)**:
  - Added CrossRef title/author/keyword search, ISBN/URL lookup, and `.bib` file import (file picker & drag-and-drop) via `BibliographyService`, with `references.bib` staging inside `TectonicService`.
  - Added **Quick Citation Picker (`⇧⌘K`)** (`CitationPickerPopoverView`) and upgraded BibTeX sidebar with `Uncited` badges, citation mode selection (`\cite`, `\parencite`, `\textcite`, `\autocite`, `\footcite`) + optional page locators, and a 1-click Bibliography Style switcher (`APA`, `IEEE`, `ACM`, `MLA`, `Chicago`, `Nature`).
- **Plain-English Error Demystifier & Academic Pre-Flight Linter**:
  - Added `ContextSuggestionsEngine.demystify(...)` mapping common TeX/LaTeX errors to plain-English explanations and **1-Click Auto-Fix** actions (`AcademicFixOperation`).
  - Added `AcademicPreflightService` & `PreflightChecklistView` checking unresolved `\cite`/`\ref` keys, uncited `.bib` entries, missing or absolute figure paths, typography hygiene, and budget targets.
- **Academic Starter Templates & Paper Setup Wizard (`⇧⌘N`)**:
  - Added 7 academic templates in `LaTeXCatalog.templates`: APA 7th Ed. Student Paper, IEEE Conference Paper, ACM Computing Article, MLA Humanities Essay, STEM Lab Report (`siunitx` + `booktabs`), University Thesis, and Beamer Presentation Slides.
  - Added **Paper Setup Wizard (`⇧⌘N`)** (`PaperWizardSheetView`) for metadata, paper size, font size, double-spacing (`setspace`), and Anonymized Blind Review (`lineno`).
- **Interactive Spreadsheet Table Grid, `pgfplots` Chart Builder & Relative Figure Assistant**:
  - Upgraded `VisualToolsSheetView` with a 2D editable **Spreadsheet Grid** (`L`/`C`/`R` column alignments, bold headers -> `booktabs`), a **CSV → `pgfplots`** chart builder (`Line`, `Bar`, `Scatter`), equation templates, and undo-preserving exact-caret insertion (`EditorInsertionRequest`).
  - Added `FigureAssistantSheetView` & `AcademicToolsGenerator` copying dropped/selected images into relative `figures/` folders (with `TempFigures` staging for unsaved documents) and generating single or side-by-side (`subcaption`) figure blocks.
- **Rubric Word/Page Budgets, LaTeX-Aware Prose Spellcheck (`⌥⌘;`) & Submission `.zip` Export (`⌥⇧⌘E`)**:
  - Added `AcademicDocumentStats` (prose-only, abstract, reference, figure, table, and page counts) and `RubricTargetsPopoverView` with configurable word/abstract/page budgets and **Student Mode** (hiding `expl3` metrics).
  - Added `LaTeXSpellCheckService` (prose-masked `NSSpellChecker` ignoring preamble, commands, math, comments, and `expl3`) with editor underlines and context-menu replacement suggestions.
  - Added `SubmissionExportService` (`⌥⇧⌘E`) packaging `.tex`, `\input` files, `.bib`, relative `figures/`, and custom fonts into a clean `.zip` archive with pre-flight verification and Finder reveal.

### Security & Hardening
- Enforced finite coordinate/data validation in `PGFPlots` chart generation, TeX metacharacter sanitization across CrossRef/BibTeX/`\bibitem`/Wizard/Table/Figure inputs, 2 MB network response caps + HTTPS URL validation, and isolated Tectonic verification workspaces with symlink/path-traversal guards for `figures/` and `.zip` bundling.

---

## [0.1.2] — 2026-11-16

### Added
- **Custom Fonts & Font Manager (`⇧⌘F`)**:
  - Added a dedicated **Font Manager** sheet (toolbar **Fonts** button, `⇧⌘F`, and **View → Manage Fonts...**) plus a quick-access **Fonts** tab in the left sidebar.
  - Added support for importing `.ttf`, `.otf`, and `.ttc` font files via file picker (**View → Add Custom Font...**) or drag-and-drop, validated with CoreText and stored non-invasively in `~/Library/Application Support/LaTeXaP/Fonts/` with an atomic `fonts.json` manifest.
  - Added live interactive specimen preview (editable sample text, `10–36 pt` size slider, Light/Dark preview surface), font renaming, and reference-aware deletion confirmation.
- **XeTeX (`fontspec`) & CTAN Font Presets**:
  - Added one-click document preamble insertion for `\setmainfont`, `\setsansfont`, `\setmonofont`, and `\newfontfamily\<cmd>` for both imported custom fonts and macOS system fonts.
  - Added `fontspec` and curated CTAN font presets (`libertinus`, `ebgaramond`, `fira`, `plex`, `lmodern`, `tgpagella`) to `LaTeXCatalog`, plus `fontspec` brace-argument autocomplete in `LaTeXAutoCompleteEngine`.
  - Updated `TectonicService` to stage managed font files and inject `OPENTYPEFONTS`, `TTFONTS`, and `OSFONTDIR` into the compilation environment.
- **Code Editor Typography Picker**:
  - Added an **Editor Font** popover in the editor header bar (and **Editor Font** scope in Font Manager + **View → Reset Editor Font to Default**) to customize the code editor font family and size (`10–24 pt`), persisted via `UserDefaults`.

### Security & Hardening
- Enforced regular-file checks (no symlinks), a `64 MB` import size cap, SHA-256 duplicate detection, and path-containment validation on `fonts.json` and managed font files.
- Added strict TeX argument and command-name sanitization (`sanitizeTeXArgument`, `sanitizeCustomCommandName`) to prevent LaTeX/macro injection when inserting `fontspec` declarations or autocomplete items.
- Hardened `TectonicService` font environment injection and symlink staging to ignore invalid/control-character paths and non-regular font files.

### Fixed
- Updated `LaTeXCodeEditorView` inline ghost-text completion rendering and `acceptCompletion` re-highlighting to respect the active editor font family and `editorFontSize`.

---

## [0.1.1] — 2026-11-16

### Added
- Non-intrusive background GitHub release update check with toolbar pill.
- Application version and build metadata in the Help menu and About panel.
- Self-contained release packaging script (`scripts/package_app.sh`) embedding the standalone Tectonic binary and ad-hoc deep code signing.
