# GitHub Repository Multi-Project Storage — UX & Accessibility Plan

> **Scope:** Design & UX specification for connecting a GitHub repository as multi-project storage in **LaTeXaP**, including project switching, quick vs. custom commit-on-save flows, commit history/restore, and sync/conflict handling.  
> **Non-goals:** Application source code edits and backend implementation details (see `docs/github-repo-storage-architecture.md`).

---

## 1. UX Goals & Mental Model

1. **Zero Git Jargon Required for Daily Writing**: Students think in terms of **Repositories** (e.g., *"Fall 2026 Papers"*), **Projects** (e.g., *"CS229 Final Paper"*, *"Physics Lab 3"*), and **Saved Versions**—not staging indexes or detached HEADs.
2. **Instant Save, Background Sync**: Saving (`⌘S`) must feel instantaneous like a local file save; committing and pushing happen asynchronously so live Tectonic compilation and typing are never blocked.
3. **One Repo, Many Isolated Projects**: Committing changes in Project A stages only Project A's directory (`projects/<slug>/`), keeping history clean and per-project version restore safe.

---

## 2. Workspace Integration & Information Hierarchy

Building onto LaTeXaP's existing `MainWorkspaceView` without crowding the 6-icon `SidebarTab` picker (`Outline`, `Packages`, `Fonts`, `BibTeX`, `LaTeX3`, `Templates`):

### A. Sidebar Top Strip — Repo & Project Switcher
Pinned cleanly above the `SidebarTab` segmented control in the left sidebar (`230–340 pt`):
- **Connected Repo Header**: Small GitHub/branch pill (`owner/repo • main`) + clickable **Sync Status Badge** (`Synced`, `2 Ahead`, `Syncing...`, `Offline`, `Conflict`).
- **Active Project Picker (`Menu`)**: Displays active project icon + name (e.g., `CS229 Final Paper ▾`) with:
  - List of all projects in the repository (showing last-updated relative time).
  - **`New Project in Repo...`**
  - **`Project Files & History...`** (`⌥⌘H`)
  - **`Repository Settings / Disconnect...`**
- **Unconnected State**: Compact card (`"Connect GitHub Repo"` + `"Sync multiple papers & backups"` button) that stays unobtrusive for users editing standalone local `.tex` files.

### B. Navigation Toolbar — Save, Commit & Sync Controls
In `ToolbarItemGroup(placement: .navigation)` alongside `Open .tex` and `Save`:
- **`Save` (`⌘S`)**: Saves the active project's files and creates a timestamped local commit (plus auto-push if enabled).
- **`Commit...` (`⌥⌘S`)**: Opens the **Save & Commit Popover** to customize the commit message, inspect changed files, and toggle push.
- **Sync Action**: Clicking the Sync badge pulls/pushes immediately or opens conflict/error details.

---

## 3. End-to-End User Journeys

### 3.1 Connecting a GitHub Repository (`GitHubRepoSetupSheet`, `560 × 460 pt`)
Triggered from **File → Connect GitHub Repository...** (`⇧⌘G`) or the Sidebar `"Connect GitHub Repo"` CTA.
1. **Authentication Step**:
   - **GitHub CLI (`gh`) Detected** (1-click *"Continue as @username"* when `gh auth status` is active).
   - **Personal Access Token (PAT)** (secure `SecureField` saved to **macOS Keychain**, with inline scope guidance: `repo`).
   - **Existing SSH Key** (uses user's configured `~/.ssh` keys).
   - Inline `"Test Connection"` indicator showing green checkmark + authenticated username or clear auth error.
2. **Repository Selection**:
   - Enter/pick repository (`https://github.com/owner/repo` or `owner/repo` picker) and target branch (default `main`).
   - Option: **"Include compiled PDFs in commits"** toggle (off by default; `.gitignore` excludes `*.aux`, `*.log`, `*.synctex.gz`, and optionally `*.pdf` so repos stay lightweight).
3. **Clone & Discovery**:
   - Progress bar (`"Cloning repository..."`).
   - If existing `projects/*` folders exist, load them into the Project Switcher; if empty, offer **`Create First Project`** (can launch the **Paper Setup Wizard**) or **`Import Current Document into Repo`**.

### 3.2 Creating & Switching Between Projects
- **Create Project Sheet (`NewRepoProjectSheet`, `460 × 320 pt`)**:
  - **Project Name** field (e.g., `"NeurIPS Workshop Paper"`).
  - Live read-only **Folder Slug Preview**: `projects/neurips-workshop-paper/` (editable, validated for lowercase alphanumeric + hyphens, preventing path collisions).
  - **Starter Source**: `Blank Paper`, `From Academic Wizard...`, or `Import Current Open Document`.
  - Creates `main.tex`, `references.bib`, `figures/`, and `project.json`, then commits `"Initialize <Project Name>"`.
- **Switching Projects**:
  - Clicking another project in the Sidebar Project Switcher loads its `main.tex`, `.bib`, and `figures/` into `DocumentViewModel` and triggers a Tectonic compile.
  - If the current project has unsaved buffer edits, prompt cleanly: **`Save & Commit Current Project`** | **`Discard Edits`** | **`Cancel`**.

### 3.3 Save & Commit Flows (Default vs. Custom Commit Message)

#### Flow 1: Quick Save & Commit (`⌘S` or Toolbar `Save`)
1. Writes dirty buffers (`main.tex`, `references.bib`, `project.json`) to `projects/<slug>/`.
2. Checks `git status -- projects/<slug>/`:
   - If nothing changed, updates status quietly (`"No changes to commit"`).
   - If changes exist, auto-generates default message:
     ```
     Update <Project Name> — YYYY-MM-DD HH:mm
     ```
     *(Example: `Update CS229 Final Paper — 2026-11-17 14:20`)*
3. Stages only `projects/<slug>/` + commits locally; if **Auto-Push on Save** preference is enabled, pushes asynchronously in the background.
4. Status bar shows a calm confirmation pill: **`Committed "Update CS229 Final Paper — 14:20" • Synced`**.

#### Flow 2: Save & Commit with Custom Message (`⌥⌘S` or Toolbar `Commit...`)
Opens the **Save & Commit Popover** (`360 pt` wide) anchored to the toolbar button:
1. **Changed Files Summary**: Compact list scoped to the active project (`M main.tex`, `A figures/loss_curve.png`, `M references.bib`) with count badge.
2. **Commit Message Input**:
   - Pre-filled and auto-selected with the default timestamped message (`Update <Project Name> — 2026-11-17 14:20`) so the user can either type immediately to replace it or press `⌘Return` to accept.
   - Optional 1-click prefix chips (`Draft:`, `Revisions:`, `Citations:`, `Final:`) that prepend cleanly.
   - Optional multi-line description disclosure (`Add extended notes...`).
3. **Push Toggle**: Checkbox **`Push to GitHub (origin/main)`** (remembers user preference).
4. **Actions**: **`Cancel`** (`Esc`) and primary `.borderedProminent` **`Save & Commit`** / **`Commit & Push`** (`⌘Return`).

### 3.4 Commit History & Version Restore (`ProjectHistorySheet`, `680 × 480 pt`)
Triggered via Sidebar Project Menu → **`Project History...`** (`⌥⌘H`) or clicking the last-commit timestamp in the status bar:
- **Left Pane (`260 pt`)**: Chronological commit timeline filtered strictly to `projects/<slug>/`, showing commit message, relative time (`12m ago`), short SHA, and sync badge (`Pushed` / `Local only`).
- **Right Pane**: Read-only preview of `main.tex` (or file tabs if multiple files changed) at that revision, plus a compact summary of lines added/removed.
- **Restore Action**: **`Restore This Version`** button → confirms (`"Restore 'main.tex' from 'Added Theorem 2 proof'?"`) and creates a **new forward commit** (`"Restore <Project Name> to version from <date>"`) so no prior history is ever lost.

---

## 4. Interaction States & Edge Cases

| State | Visual & Behavioral Specification |
|---|---|
| **No Repo Connected (Standalone Mode)** | LaTeXaP behaves identically to local mode; `⌘S` saves the `.tex` file on disk. Sidebar shows a subtle `"Connect GitHub Repo"` link without nagging dialogs. |
| **Saving / Committing / Pushing** | Toolbar Sync badge animates with a small `ProgressView` (`"Committing..."` → `"Pushing..."`). Editor remains 100% responsive. |
| **Offline / Network Timeout** | Local write + `git commit` **still succeed**. Sync badge shifts to amber (`"1 Local Commit • Offline"`) with tooltip and **`Retry Push`** button; never loses student work. |
| **Validation: Invalid Repo / Auth Expired** | Inline red banner in Setup/Sync popover: `"Authentication failed for github.com — Update token in Keychain or re-run 'gh auth login'."` with **`Update Credentials...`** CTA. |
| **Validation: Invalid Project Name / Duplicate Slug** | Real-time inline error beneath Project Name field (`"A project named 'cs229-final' already exists in this repository."` or `"Project name cannot be empty."`); Create button disabled until valid. |
| **Validation: Empty Commit Message** | If the user clears the custom commit message in `⌥⌘S` popover, show subtle inline helper (`"Leave blank to use default: Update <Project> — 14:20"`) or disable submit if strict—recommending **auto-fallback placeholder** so students are never blocked from saving. |
| **Remote Ahead (Pull Needed)** | When push rejects non-fast-forward, show non-blocking alert/banner: `"GitHub has 2 newer commits. Pull latest changes before pushing."` with **`Pull & Merge`** button. |
| **Merge Conflict** | Open a dedicated **Sync Conflict Sheet**: list conflicted files inside `projects/<slug>/` with 3 clear choices per file—**`Keep My Local Version`**, **`Use GitHub Version`**, or **`Open in Editor to Resolve`**—and disable Tectonic auto-compile on conflicted files until resolved so cryptic `<<<<<<<` TeX errors don't confuse the student. |

---

## 5. Accessibility Requirements (macOS VoiceOver / `NSAccessibility` & ARIA Equivalents)

### Semantic Landmarks & Structure
- **Sidebar Project Switcher (`role="navigation"`, `aria-label="GitHub Repository Projects"`)**: Group repo status, project menu, and sync button inside an explicit `accessibilityElement(children: .contain)` header.
- **Popovers & Sheets (`role="dialog"`, `aria-modal="true"`, `aria-labelledby`)**: `GitHubRepoSetupSheet`, `NewRepoProjectSheet`, `Save & Commit` popover, `ProjectHistorySheet`, and `ConflictResolutionSheet` must expose header traits (`.accessibilityAddTraits(.isHeader)`) and support `Esc` dismissal.
- **Live Announcements (`aria-live="polite"` / `"assertive"`)**: Post `NSAccessibility.post` (`.announcementRequested`) for background commit/push completion (`polite`: `"Committed and pushed Update CS229 Final Paper"`), offline local commit fallback (`polite`: `"Saved and committed locally; offline, push pending"`), and auth/merge conflicts (`assertive`).

### Labels, Hints & Values
- **Sync Status Badge**: Combine icon + text into one VoiceOver readout: `.accessibilityLabel("GitHub sync status")`, `.accessibilityValue("2 unpushed local commits, offline")`, `.accessibilityHint("Activates sync or opens repository status details")`.
- **Commit History Rows**: Combine message, relative time, and push status into a single accessible row string (e.g., `"Update CS229 Final Paper, 14 minutes ago, synced to GitHub"`).
- **Secure Token Field**: Explicitly label `"GitHub Personal Access Token"` with hint `"Stored securely in macOS Keychain"`.

### Focus Management & Keyboard Navigation
- **Commit Popover (`⌥⌘S`)**: On open, `@FocusState` immediately focuses the commit message `TextField` with text selected; `⌘Return` submits and restores focus to the editor; `Esc` cancels and restores focus to the editor.
- **Setup & New Project Sheets**: Focus lands on the primary input (PAT/Repo URL or Project Name); on validation error, focus remains on the invalid input with `.accessibilityValue` announcing the error; on close, focus returns to the triggering control.
- **Shortcuts**:
  - `⌘S`: Quick Save (& auto-commit with default timestamped message when inside a repo project)
  - `⌥⌘S`: Save & Commit with Custom Message popover
  - `⇧⌘G`: Connect / Manage GitHub Repository
  - `⌥⌘H`: Project Commit History & Restore

### Color Contrast & Non-Color Signifiers
- **WCAG 2.1 AA Targets**: Maintain **`>= 4.5:1`** contrast for commit messages, timestamps, inline validation text, and sync labels in both macOS Light (`Aqua`) and Dark (`DarkAqua`) modes; **`>= 3.0:1`** for status pill borders, focus rings, and diff highlights.
- **Never Color-Alone**: Pair every sync state with a distinct SF Symbol + text label: Synced (`checkmark.icloud.fill`), Pending Push (`arrow.up.circle.fill`), Syncing (`arrow.triangle.2.circlepath`), Offline (`wifi.slash`), and Conflict/Error (`exclamationmark.triangle.fill`).
