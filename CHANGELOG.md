# Changelog

All notable changes to **LaTeXaP** are documented in this file.

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
