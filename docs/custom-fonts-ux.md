# Custom Fonts UX Specification — LaTeXaP

> **Scope:** End-to-end UX specification for adding, managing, previewing, and selecting custom fonts in **LaTeXaP** (macOS SwiftUI + AppKit / Tectonic XeTeX studio).  
> **Non-goals:** Application source code and architecture diagrams (covered separately in `docs/custom-fonts-architecture.md`).

---

## 1. Current State & Codebase Context

In the current codebase (`/Users/james/code/LaTeXaP`):
- **Code Editor (`LaTeXCodeEditorView.swift`)**: `LaTeXSyntaxHighlighter` and `LaTeXEditorTextView` hardcode `NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular | .semibold)`. Users can only scale `editorFontSize` (`10–24 pt`, default `13.5 pt`) via **View → Increase/Decrease Editor Font Size** (`⌘+` / `⌘-`).
- **LaTeX Document Typesetting (`TectonicService.swift`, `LaTeXTemplates.swift`)**: Tectonic runs **XeTeX**, which natively supports OpenType/TrueType fonts via `\usepackage{fontspec}` (`\setmainfont`, `\setsansfont`, `\setmonofont`, `\newfontfamily`), yet `LaTeXCatalog.commonPackages` does not expose `fontspec`, and no UI exists to import font files or insert font declarations.
- **Established UI Patterns (`MainWorkspaceView.swift`, `VisualToolsSheetView.swift`)**:
  - **Left Sidebar (`SidebarTab`)**: Segmented icon tabs (`Outline`, `Packages`, `BibTeX`, `LaTeX3`, `Templates`) in a `230–340 pt` column.
  - **Toolbar & Sheets**: Primary toolbar actions (e.g., `Math & Tables` opening `VisualToolsSheetView`, `Insert Figure` opening `NSOpenPanel`) plus drag-and-drop onto `LaTeXEditorTextView`.
  - **Diagnostics Drawer (`DiagnosticsDrawerView`)**: Collapsible bottom drawer displaying Tectonic errors/warnings and `ContextSuggestionsEngine` advice.

---

## 2. Information Hierarchy & Entry Points

Custom font functionality spans **two distinct user goals** that must be visually separated so users never confuse *typesetting a PDF* with *styling the code editor*:

1. **Document Fonts (PDF Output via XeTeX `fontspec`)** — Primary workflow: importing `.ttf`/`.otf`/`.ttc` files or picking installed macOS fonts and applying them as **Main (Serif)**, **Sans-Serif**, **Monospace**, or a named **`\newfontfamily`** command in the `.tex` preamble.
2. **Editor Font (Source Code View)** — Secondary workflow: selecting a monospace font family for `LaTeXCodeEditorView` alongside `editorFontSize`.

### Entry Points
| Surface | Control | Action |
|---|---|---|
| **Left Sidebar (`SidebarTab`)** | New **Fonts** tab (`textformat`) | Quick-browse custom & active document fonts, 1-click insert/re-apply, and **"Manage & Add Fonts..."** button. |
| **Main Toolbar** | **Fonts** button (`textformat` icon) | Opens the **Font Manager Sheet** (`680 × 480 pt`, matching `VisualToolsSheetView` sheet ergonomics). |
| **Menu Bar (`LaTeXaPApp`)** | **Typeset & LaTeX3 → Manage Fonts...** (`⇧⌘F`) and **View → Editor Font...** | Opens the Font Manager Sheet directly to the Document or Editor scope. |
| **Drag & Drop** | Drop `.ttf`, `.otf`, or `.ttc` onto the Font Manager dropzone (or `LaTeXEditorTextView`) | Triggers the import + validation flow directly. |

### Font Manager Sheet Layout (3-Zone Hierarchy)
1. **Top Header Bar**: Title (`Font Manager`), Scope Segmented Control (`Document Fonts (fontspec)` | `Editor Font`), and Close button (`xmark.circle.fill` / `Esc`).
2. **Left Master List (`240 pt`)**:
   - Search field (`Filter fonts by name or style...`).
   - **Add Font (`+`)** button + compact drag-and-drop target.
   - Grouped sections: **Custom Fonts** (user-added files) followed by **System Fonts** (curated/all macOS fonts; monospace-only filter available/enforced in Editor scope).
   - Each row displays: Family Name (rendered in the font itself when safe, with fallback label), format/origin badge (`OTF`, `TTF`, `TTC`, `System`), and active role pill (`Main`, `Sans`, `Mono`, `Editor`).
3. **Right Detail & Live Preview Pane**:
   - **Font Header**: Family name, PostScript name, file format, file size, and available weights/styles (`Regular`, `Bold`, `Italic`, `Bold Italic`).
   - **Live Specimen Preview**: Editable preview text field (default: `"The quick brown fox — \LaTeX3 \alpha + \beta = \gamma  0123456789"`), size slider (`10–36 pt`), and Light/Dark surface toggle matching the editor/PDF contrast.
   - **LaTeX / Role Assignment Controls**:
     - *Document scope*: Segmented role selector (`Main`, `Sans`, `Mono`, `Custom Macro`) + optional macro name input (e.g., `\displayfont`) + live read-only preview of the generated preamble code (`\usepackage{fontspec}` + `\setmainfont[Path=...]{...}`).
     - *Editor scope*: **Apply to Code Editor** button + **Reset to System Mono** action.
   - **Footer Action Bar**: Secondary destructive **Remove Font** (custom fonts only) on the left; primary `.borderedProminent` CTA (**Insert into Preamble** / **Update Preamble** / **Apply Editor Font**) on the right.

---

## 3. End-to-End User Journey

```
[Trigger: Toolbar "Fonts" / ⇧⌘F / Sidebar / File Drop]
   │
   ▼
[1. Discover / Import] ──► Click "Add Font Files..." (NSOpenPanel) or Drag & Drop
   │
   ▼
[2. Validate & Register] ──► Check extension (.ttf/.otf/.ttc), CoreText readability,
   │                         & name collisions; show loading spinner or inline error
   ▼
[3. Preview & Configure] ──► Inspect live specimen (size/text/variants), choose role
   │                         (Main / Sans / Mono / \newfontfamily / Editor)
   ▼
[4. Apply / Insert] ──► Inserts \usepackage{fontspec} + font command in preamble
   │                    (or updates editorFontFamily); shows success confirmation
   ▼
[5. Live Render & Verify] ──► Tectonic auto-compiles; PDF Preview updates; errors
   │                          (if any) surface in DiagnosticsDrawerView
   ▼
[6. Manage / Delete] ──► Filter, switch roles, or remove custom font with confirmation
                         if referenced in the active .tex document
```

---

## 4. Interaction States & Edge Cases

| State | Visual & Behavioral Specification |
|---|---|
| **Loading / Importing** | Show an inline `ProgressView` + `"Validating and importing font..."` status in the dropzone/list header while copying and reading CoreText descriptors. Keep the close button and system font list interactive (non-blocking). After preamble insertion, the existing toolbar `compilationBadge` (`Rendering...`) indicates Tectonic rebuild progress. |
| **Empty (No Custom Fonts Yet)** | Never show a blank list. Render a dedicated **Custom Fonts** dropzone card (`"No Custom Fonts Added"`, icon `doc.badge.plus`, description `"Drop .ttf, .otf, or .ttc font files here to use with XeTeX (fontspec) or the code editor."`, primary `"Choose Font Files..."` button) above the **System Fonts** section. |
| **Empty Search Results** | Display `ContentUnavailableView` (`"No Matching Fonts"`, `"No fonts match '<query>'. Try clearing the filter or adding a custom font."`) with a `"Clear Filter"` action button. |
| **Validation Error: Unsupported Format** | Reject `.woff`, `.woff2`, `.eot`, `.svg`, or non-font files before copying. Show a dismissible inline error banner: `"Unsupported font format (.woff2): '<filename>'. Tectonic (XeTeX) and macOS require .ttf, .otf, or .ttc font files."` |
| **Validation Error: Corrupt / Unreadable Font** | If CoreText/font parser fails to extract a valid `CTFontDescriptor` or PostScript name, abort import and show: `"Could not load '<filename>'. The file appears corrupted, incomplete, or unreadable."` |
| **Validation Error: Invalid Custom Name / Macro** | For `\newfontfamily{\<name>}` or custom display name edits: validate in real time. Display an inline red message directly beneath the text field (`"Macro name must start with a letter and contain only A–Z or a–z (e.g., headingfont)."` for invalid TeX control sequences, or `"Font name cannot be empty."` for blank names). Disable the primary **Insert** button until valid. |
| **Conflict: Duplicate Font** | If a custom font with the same filename or PostScript name already exists, present a focused inline conflict prompt or sheet alert with three choices: **Replace Existing**, **Keep Both**, or **Cancel**. |
| **Warning: Non-Monospace Font in Editor Scope** | In the **Editor Font** scope, filter to monospace fonts by default. If a user enables `"Show proportional fonts"`, show a subtle amber warning badge (`"Proportional fonts may misalign code columns and inline ghost completions."`). |
| **Success Feedback** | On import: select the newly added font immediately, scroll it into view, and show a non-intrusive status banner (`"Added '<FontName>' — ready to preview and insert."`). On preamble insertion: show `"Inserted \<command> into preamble (Line N)"` and update the row's active role pill (`Main`, `Sans`, `Mono`). |
| **Deleting / Managing Added Fonts** | Custom fonts expose a **Remove** button (`trash`) and context menu; system fonts hide/disable removal with tooltip `"macOS system fonts cannot be deleted from LaTeXaP."` If the custom font is currently referenced in `sourceText`, show a confirmation alert: `"Remove '<FontName>'? It is referenced on Line N of your current document and removing the file will cause compilation to fail."` offering **Remove Font**, **Remove Font & Preamble Line**, and **Cancel**. |

---

## 5. Accessibility Requirements

LaTeXaP is a native macOS SwiftUI/AppKit application; requirements below specify **macOS VoiceOver / SwiftUI (`NSAccessibility`)** implementations alongside their **semantic/ARIA equivalents** for cross-platform consistency.

### Semantic Landmarks & Structure
- **Modal Sheet (`role="dialog"`, `aria-modal="true"`, `aria-labelledby`)**: Present the Font Manager as a true macOS sheet/dialog with a clear title header (`accessibilityAddTraits(.isHeader)`).
- **Sidebar / Navigation Region (`role="navigation"`)**: Group the left font list with explicit section headers (`Custom Fonts`, `System Fonts`) using `.accessibilityAddTraits(.isHeader)`.
- **Preview & Inspector Region (`role="region"`, `aria-label="Font preview and actions"`)**: Group the preview specimen, TeX snippet preview, and role controls into logical `accessibilityElement(children: .contain)` containers.
- **Live Feedback Region (`aria-live="polite"` / `"assertive"`)**: Announce import completion, preamble insertion, and validation errors via `NSAccessibility.post(element:notification:userInfo:)` (`.announcementRequested`)—polite for success/loading, assertive for validation errors.

### ARIA / Accessibility Attributes & Labels
- **Icon-Only Buttons**: Every icon button (`+`, `trash`, `xmark.circle.fill`, toolbar `Fonts`) must define `.accessibilityLabel(...)` and `.accessibilityHint(...)` (e.g., `"Close Font Manager"`, `"Remove custom font FiraCode Regular"`).
- **Font List Rows**: Combine row subviews (`.accessibilityElement(children: .combine)`) so VoiceOver reads a single concise string: `"Fira Code, OpenType custom font, active as Document Mono"`.
- **Invalid Form Inputs (`aria-invalid="true"`, `aria-describedby`)**: When a custom font name or macro name fails validation, expose the error string in `.accessibilityValue` / `.accessibilityHint` and announce it immediately.
- **Interactive Dropzone**: Label as a button/drop target: `.accessibilityLabel("Add custom font files")`, `.accessibilityHint("Opens file picker or accepts dropped TTF, OTF, or TTC files")`.

### Focus Management
- **On Sheet Open**: Move initial focus (`@FocusState` / `@AccessibilityFocusState`) to the search field (if fonts exist) or the `"Choose Font Files..."` primary button (if custom fonts are empty).
- **On Validation Error**: Keep focus on the invalid field (or move accessibility focus to the error banner if triggered by file drop).
- **On Font Deletion**: Automatically advance selection and focus to the next font in the list, or to the empty-state `"Choose Font Files..."` button if the last custom font was deleted.
- **On Sheet Close (`Esc` or Close button)**: Restore focus to the control that opened the sheet (toolbar `Fonts` button or Sidebar `Fonts` tab).

### Keyboard Navigation
- `⇧⌘F`: Open Font Manager Sheet from anywhere in the workspace.
- `Tab` / `Shift+Tab`: Move cleanly between Scope picker → Search field → Add button → Font list → Preview controls → Role selector → Primary/Destructive footer buttons (no focus traps; standard macOS focus ring visible).
- `↑` / `↓`: Navigate font list items and immediately update the live preview pane.
- `Return` (when list item focused): Apply/Insert the selected font into the active scope; `⌘Return` submits from anywhere in the sheet.
- `⌘Backspace` (when custom font row focused): Trigger Remove Font flow (with confirmation if in use).
- `Esc`: Dismiss inline error banner first if focused, otherwise close the Font Manager Sheet.

### Color Contrast & Visual Accessibility
- **Text Contrast**: Achieve **WCAG 2.1 AA (`>= 4.5:1`)** for all body text, metadata, badges, and error messages in both macOS Light (`Aqua`) and Dark (`DarkAqua`) modes. Use semantic `NSColor.labelColor` / `secondaryLabelColor` and avoid low-alpha custom greys for readable labels.
- **UI Controls & Focus Rings**: Maintain **`>= 3.0:1`** contrast for input borders, segmented control boundaries, dropzone dashed borders, and keyboard focus outlines.
- **Large Specimen Text (`>= 18 pt`)**: Maintain **`>= 3.0:1`** minimum (`>= 4.5:1` target) on both Light and Dark preview surfaces.
- **No Color-Only Signifiers**: Always pair semantic colors (red for validation errors, green for success, amber for warnings/in-use pills) with SF Symbols (`xmark.octagon.fill`, `checkmark.circle.fill`, `exclamationmark.triangle.fill`) and explicit text labels.
