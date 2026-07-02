# VisionMark

[![CI](https://github.com/atomsbaza/VisionMark/actions/workflows/ci.yml/badge.svg)](https://github.com/atomsbaza/VisionMark/actions/workflows/ci.yml)

**Convert PDFs into AI-readable Markdown — including the pictures.**

VisionMark is a native macOS app that turns PDFs into Markdown. Beyond extracting text, it can
embed a rendered image of every page alongside the text, so a **vision-capable AI** (Claude,
GPT-4o, Gemini, …) reading the output can *see* the diagrams, charts, and figures that plain text
extraction can't represent.

It runs entirely on your Mac — **no network, no cloud, no LLM calls.** Your documents never leave
the machine.

---

## Why

Most PDF→Markdown tools only give you text, and they mangle diagram-heavy or multi-column pages
(a flowchart becomes a jumble of scrambled labels). VisionMark keeps the extracted text *and*
attaches a faithful image of each page. When the downstream reader is a multimodal AI, that image
is the best possible representation of a diagram — the model reads it directly.

## Features

- **Drag & drop or pick** files and folders; **batch conversion** (up to 4 files concurrently).
- **Smart per-page routing** — native text extraction for digital PDFs, **Vision OCR** for scanned
  pages. Mode is configurable: Auto-detect / Always OCR / Never.
- **Structure inference** — headings, bold, italic, and bullet lists are inferred from the PDF's
  font attributes.
- **Embed page images** (default on) — each page is rendered to a PNG in a sibling
  `<name>_assets/` folder and linked from the Markdown as `![Page N](...)`.
- **Flexible output** — write the `.md` next to the source PDF, or into a folder you choose.
- **Memory-safe on large PDFs** — pages render inside an autorelease pool so batch conversion stays
  bounded (a 352-page book peaks around ~230 MB instead of ballooning to gigabytes).

## Output layout

Converting `report.pdf` produces:

```
report.md
report_assets/
  page-01.png
  page-02.png
  …
```

With image embedding off, you get just `report.md` (text only).

## Requirements

- **macOS 15.0+**
- **Xcode** (Swift 6)
- **[XcodeGen](https://github.com/yonwoo9/XcodeGen)** — `brew install xcodegen`

The Xcode project is generated from `project.yml`, so `VisionMark.xcodeproj` is **not** checked in.

## Build & run

```bash
brew install xcodegen        # once, if you don't have it
xcodegen generate            # creates VisionMark.xcodeproj from project.yml
open VisionMark.xcodeproj     # then Run (⌘R) in Xcode
```

Or build/test from the command line:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project VisionMark.xcodeproj -scheme VisionMark -destination 'platform=macOS' build

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project VisionMark.xcodeproj -scheme VisionMark -destination 'platform=macOS' test
```

## Architecture

Swift 6 with strict concurrency; SwiftUI front end, an actor-based conversion pipeline.

| Area | Responsibility |
|------|----------------|
| `Core/PageClassifier` | Decides native-text vs OCR per page |
| `Core/PDFTextExtractor` (`PDFPageRenderer`) | Renders pages to images (for OCR + embedding) |
| `Core/OCREngine` | Vision-based OCR with paragraph grouping |
| `Core/MarkdownFormatter` | Attributed string → structured blocks (font-size clustering) |
| `Core/MarkdownDocument` | Block model + Markdown rendering |
| `Core/ConversionPipeline` | `actor` orchestrating per-file conversion |
| `Features/Conversion/*` | SwiftUI drop zone, file list, view model |
| `Features/Settings/*` | Settings screen |
| `App/VisionMarkApp.swift` | App entry point |

## Privacy & distribution

- **Fully local** — nothing is uploaded; there are no network calls.
- **Unsandboxed** by design, so it can write output next to the source PDF freely. This means it is
  **not** intended for App Store distribution — it's a personal-use utility.

## Notes & limitations

- Reading order on 2D/circular diagrams can't be linearized into text — that's why page images
  exist; let a vision AI read the image.
- Heading detection is heuristic (font-size based) and can miss headings on slide-style layouts.
- Diagram→Mermaid / structured transcription is intentionally out of scope (that would require an
  LLM and would send content off-device).

## Best for

Feeding PDFs — especially slide decks and diagram-heavy documents — to a **vision-capable AI**. The
embedded page images let the model read diagrams that text extraction alone would lose.
