# VisionMark — Progress Notes

> Renamed from **PDFToMarkdown** → **VisionMark** on 2026-07-03 (full rename: project name, both
> targets, bundle IDs `com.pisit.koolplukpol.VisionMark[Tests]`, source folders `VisionMark/` +
> `VisionMarkTests/`, entitlements, `@main VisionMarkApp`, regenerated `VisionMark.xcodeproj`).
> The window title now reads "VisionMark" (derived from `PRODUCT_NAME`). The OUTER container folder
> is still `Work/Apple/PDFToMarkdown/` — rename it with a plain `mv` anytime (left as-is to avoid
> breaking the live session's working directory). Old bundle ID's sandbox container/app-scripts
> under `~/Library/.../com.pisit.koolplukpol.PDFToMarkdown` are now orphaned and harmless.

## Status as of 2026-07-02

Scaffolded and building successfully via `xcodegen` + `xcodebuild`. All 18 unit tests pass
(`MarkdownFormatterTests`, `PageClassifierTests`, `HeadingDetectionTests`). Sandbox output-write
bug is now FIXED and verified.

Implemented:
- `Core/MarkdownDocument.swift` — Block/InlineRun/HeadingLevel model
- `Core/ConversionJob.swift` — job state model
- `Core/PageClassifier.swift` — native-text-vs-OCR routing heuristic
- `Core/PDFTextExtractor.swift` — page-to-CGImage renderer for OCR
- `Core/OCREngine.swift` — Vision-based OCR with paragraph grouping
- `Core/MarkdownFormatter.swift` — heading/bold/italic/bullet/paragraph detection from
  `PDFPage.attributedString` (two-pass font-size clustering; baseline picked by paragraph
  occurrence count with smallest-size tiebreak; heading threshold is body size × 1.15,
  not a fixed +0.5pt, to avoid false positives on minor font variation)
- `Core/ConversionPipeline.swift` — actor orchestrating per-file conversion
- `App/AppSettings.swift`, `App/PDFToMarkdownApp.swift`
- `Features/Conversion/*` — drop zone, file list, view model with bounded-concurrency
  `TaskGroup` batch conversion
- `Features/Settings/SettingsView.swift`

Project generated via XcodeGen (`project.yml` in repo root — not committed to Xcode's own
project format by hand; re-run `xcodegen generate` after editing `project.yml`).

## Output-write permission bug — FIXED (2026-07-02)

**Resolution:** Removed App Sandbox entirely (`ENABLE_APP_SANDBOX: NO` in `project.yml`;
entitlements now `com.apple.security.app-sandbox = false`). This is a personal-use tool so
App Store eligibility was intentionally given up. Also switched `AppSettings` from
security-scoped bookmarks to plain bookmarks (with stale-bookmark re-save) so the custom
output folder works unsandboxed.

**Files changed:** `project.yml`, `PDFToMarkdown/PDFToMarkdown.entitlements`,
`PDFToMarkdown/App/AppSettings.swift`.

**Original issue:** Manually tested via the built app: dropped a real text PDF (generated with
`cupsfilter` from a `.txt` fixture) and clicked "Convert All". Got error: "You don't have
permission to save the file 'sample.md' in the folder 'scratchpad'."

**Root cause:** The app was sandboxed (`com.apple.security.app-sandbox = true`). `NSOpenPanel`
grants read/write access to the exact file(s) the user selected, but the app sandbox does
**not** automatically extend that grant to sibling files in the same directory — so writing
`sample.md` next to `sample.pdf` (the "same folder as source" default in
`AppSettings.useSourceFolderForOutput`) failed. Additionally, the custom-folder path was broken
because `startAccessingSecurityScopedResource()` was never called on the bookmark.

## Verification checklist status (from plan)

- [x] **Write path** — verified 2026-07-02 via UI automation. Converted an 18MB PDF
  (`~/Downloads/Loop_Engineering (1).pdf`), `.md` written next-to-source in ~2s with no permission
  error, native-text extraction (no OCR). This confirms the sandbox fix only.
- [ ] Pure-text PDF → **headings/bold/lists map correctly — NOT verified; known-poor.** On the
  Loop_Engineering deck the output has *zero* headings detected and diagram/multi-column slides come
  out with scrambled reading order (see "Output quality" below). Needs a clean single-column prose
  PDF to fairly assess heading/list mapping.
- [ ] Pure scanned PDF → OCR triggers, produces reasonable text — not yet tried
- [ ] Mixed PDF (text + scanned pages) → correct per-page routing — not yet tried
- [ ] Large PDF (100+ pages) → memory/progress — not yet tried
- [ ] Drag multiple files/a folder → correct per-file output — not yet tried
- [ ] Cancel mid-conversion → partial state handled — not yet tried
- [ ] Password-protected PDF → clear per-file failure — not yet tried

**Note:** Custom output-folder mode and its persist-across-relaunch behaviour (AppSettings
bookmark change) are implemented but NOT yet manually verified.

## UI redesign — DONE + verified (2026-07-03)

Presentation-only polish (no logic changes), macOS 15 APIs. Files: `Features/Conversion/
ContentView.swift`, `DropZoneView.swift`, `FileListView.swift`, `FileRowView.swift`.
- Adaptive drop zone: large hero when empty, slim "Drop more PDFs" bar when files present
  (`DropZoneView(isCompact:)`).
- "Files (N)" section header with count badge.
- Card-style rows: accent-tinted icon badge + filename + status-dependent secondary line (shows
  output `.md` name when done) + a colored **StatusPill** (Queued/Converting w/ inline progress+%/
  Done/Failed). Done pill is the reveal-in-Finder button.
- Toolbar: prominent blue "✨ Convert All" (`.borderedProminent` + `.labelStyle(.titleAndIcon)` so
  the title isn't collapsed to icon-only on macOS Tahoe).
- Verified via screenshots in all states (empty/queued/converting/done); build + 18 tests green.

## Image-safety: memory hardening — DONE + verified (2026-07-03)

Large-PDF image embedding ballooned memory. Fixed by draining the autorelease pool per page.
- Root cause: inside the `ConversionPipeline` actor's page loop, `page.draw` + `CGContext.makeImage`
  create autoreleased CG/PDFKit temporaries that never drain (no run loop) until `convert()` returns.
- Fix: wrap the per-page render/encode in `autoreleasepool { }` — both the image-embed block and the
  OCR render in `ocrBlocks(for:)` (returns the `CGImage` out of the pool so it survives the OCR
  `await`). `Core/ConversionPipeline.swift` only. Build + 18 tests green.
- **Measured on the 352-page `the-pragmatic-programmer.pdf` (fast RSS sampling):**
  - BEFORE: peak RSS **1789 MB** (monotonic climb, drains only at function exit).
  - AFTER: peak RSS **228 MB** (flat/bounded). ~8× lower peak; output identical (352 PNGs, 352 links).
- **Still open (optional):** disk is **80 MB** for 352 pages (~230 KB/page PNG at 150 DPI). Not a
  crash; left as-is. Lever if wanted: lower DPI and/or high-quality JPEG (rings text edges — keep
  ≥0.85). Not done — deferred to a user call.

## Embed page images (Path A) — DONE + verified (2026-07-02)

Added an "Embed page images" mode (default ON) so a downstream AI can read diagrams/pictures the
text extraction can't represent. Each page is rendered to a PNG (150 DPI) in a sibling
`<safeBase>_assets/` folder and referenced from the Markdown as `![Page N](<safeBase>_assets/
page-NN.png)`. Local only — no network, no LLM, no Mermaid.
- Files: `Core/MarkdownDocument.swift` (new `.image` Block), `Core/PDFTextExtractor.swift`
  (`PDFPageRenderer.writePNG`), `Core/ConversionPipeline.swift` (`convert(...,embedImages:...)`,
  assets dir + per-page render, image failures are non-fatal), `App/AppSettings.swift`
  (`embedPageImages`), `Features/Conversion/ConversionViewModel.swift`, `Features/Settings/
  SettingsView.swift` (toggle). Build + 18 unit tests green.
- **Verified E2E:** converted `~/Downloads/Loop_Engineering (1).pdf` with toggle ON → 17 PNGs +
  17 `![Page N]` links, all resolving. The previously-scrambled 7-step circular diagram (page 5)
  is now a crisp, legible embedded image.
- **Known trade-off:** PNGs are large (~5 MB each at 150 DPI → ~80 MB for 17 slides). Halving DPI
  or using JPEG would cut this ~4× with little AI-readability loss — not yet done.

## Output quality — diagnosis (2026-07-02, from Loop_Engineering deck)

The write path works, but conversion *quality* on a diagram-heavy slide deck is poor. Ranked:

1. **Reading-order scrambling (THE real defect).** `PDFPage.attributedString` returns text in
   content-stream (draw) order, not human reading order. On multi-column / diagram slides this
   interleaves fragments from different regions (e.g. the 7-step circular diagram → one jumbled
   line). Fixing requires geometric layout analysis (character-bounds clustering into columns,
   sort top→bottom/left→right) or a Vision layout-aware pass. Big feature, regression risk to the
   already-clean single-column path, and **circular/2D diagrams are fundamentally lossy in linear
   Markdown** — even perfect geometric sorting can't linearize a circle.
2. **No headings detected.** Per-page `bodyFontSize` in `MarkdownFormatter` misfires on sparse
   slides — the baseline picks the title's own font size, so nothing clears the body×1.15 bar. A
   global two-pass body-size estimate would help; payoff uncertain. Deferred.
3. **Repeated boilerplate.** "A NotebookLM" footer repeats on ~every slide (~20×). Safe to strip
   in `ConversionPipeline` (cross-page) by dropping lines present on ≥~50% of pages.
4. **No page separators.** Slides run together. `---` between pages helps *slide-like* pages but
   would fragment prose that flows across a page break — must be gated, not applied globally.
5. **Decorative-glyph noise** (leading `+`, `‹`, truncated tokens like "ve"/"Debugl"). Low value.

## Useful commands

```
cd /Users/pisitkoolplukpol/Work/Apple/PDFToMarkdown
xcodegen generate
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project VisionMark.xcodeproj -scheme VisionMark -destination 'platform=macOS' build
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project VisionMark.xcodeproj -scheme VisionMark -destination 'platform=macOS' test
```
