import SwiftUI

/// Rendered markdown for a note's MD preview mode. Read-only except for one
/// thing: `- [ ] task` / `- [x] task` lines render as tappable checkboxes that
/// write straight back through `text` (see `toggleCheckbox`), same as any
/// other edit — locked-note handling, search, and version-history
/// checkpointing all key off that binding already, so none of them need to
/// know this feature exists. Falls back to the raw text if it fails to parse
/// as markdown, rather than showing a blank pane.
struct MarkdownPreviewView: View {
    @Binding var text: String
    var fontSize: CGFloat

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                    segmentView(segment)
                        .padding(.top, spacing(before: index))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
        }
    }

    // MARK: - Segmentation

    /// One line of source text, classified as either a checkbox item or not.
    private enum Segment {
        /// A maximal run of contiguous non-checkbox lines, rendered through
        /// the block markdown pipeline below.
        case block(String)
        /// A single `- [ ]`/`- [x]` line, rendered as its own tappable row.
        case checkbox(lineIndex: Int, line: CheckboxLine)
    }

    private var segments: [Segment] {
        let lines = text.components(separatedBy: "\n")
        var result: [Segment] = []
        var currentBlock: [String] = []

        func flushBlock() {
            guard !currentBlock.isEmpty else { return }
            result.append(.block(currentBlock.joined(separator: "\n")))
            currentBlock = []
        }

        for (index, line) in lines.enumerated() {
            if let checkbox = Self.parseCheckboxLine(line) {
                flushBlock()
                result.append(.checkbox(lineIndex: index, line: checkbox))
            } else {
                currentBlock.append(line)
            }
        }
        flushBlock()
        return result
    }

    /// Tight spacing between consecutive checkbox rows (they read as one
    /// list); a blank-line-equivalent gap everywhere else — same rule the
    /// block renderer below uses internally for list items vs. other blocks.
    private func spacing(before index: Int) -> CGFloat {
        guard index > 0 else { return 0 }
        if case .checkbox = segments[index], case .checkbox = segments[index - 1] {
            return 2
        }
        return 10
    }

    @ViewBuilder
    private func segmentView(_ segment: Segment) -> some View {
        switch segment {
        case .block(let blockText):
            Text(Self.renderBlock(blockText, fontSize: fontSize))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .checkbox(let lineIndex, let line):
            checkboxRow(lineIndex: lineIndex, line: line)
        }
    }

    private func checkboxRow(lineIndex: Int, line: CheckboxLine) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Button(action: { toggleCheckbox(at: lineIndex) }) {
                Image(systemName: line.checked ? "checkmark.square.fill" : "square")
                    .foregroundStyle(line.checked ? Color.accentColor : .secondary)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .reliableHelp(line.checked ? "Mark Incomplete" : "Mark Complete")
            .accessibilityLabel(line.checked ? "Mark task incomplete" : "Mark task complete")

            Text(Self.renderInline(line.content, fontSize: fontSize, strikethrough: line.checked))
                .foregroundStyle(line.checked ? .secondary : .primary)
                .textSelection(.enabled)
        }
        .padding(.leading, CGFloat(line.indent.count) * 8)
    }

    // MARK: - Checkbox parsing/toggling

    private struct CheckboxLine {
        let indent: String
        let marker: Character
        let checked: Bool
        let content: String
    }

    /// Manual parse rather than a regex — matches this codebase's existing
    /// preference for plain string ops over regex (e.g. `Note.firstLine`).
    /// Recognizes `- [ ] `, `- [x] `, `- [X] `, and the same with `*`. Doesn't
    /// track fenced-code-block state, so a literal `- [ ] x` inside a ``` block
    /// would still render as a live checkbox — a known, documented limitation
    /// (see SPEC.md), not worth the added complexity for a personal notes app.
    private static func parseCheckboxLine(_ line: String) -> CheckboxLine? {
        let indent = line.prefix(while: { $0 == " " || $0 == "\t" })
        let rest = line[indent.endIndex...]
        guard let marker = rest.first, marker == "-" || marker == "*" else { return nil }
        let afterMarker = rest.dropFirst()
        guard afterMarker.first == " " else { return nil }
        let afterSpace = afterMarker.dropFirst()
        guard afterSpace.first == "[" else { return nil }
        let afterBracket = afterSpace.dropFirst()
        guard let checkChar = afterBracket.first, afterBracket.dropFirst().first == "]" else { return nil }
        guard checkChar == " " || checkChar == "x" || checkChar == "X" else { return nil }
        let afterCloseBracket = afterBracket.dropFirst(2)
        guard afterCloseBracket.first == " " else { return nil }
        return CheckboxLine(
            indent: String(indent),
            marker: marker,
            checked: checkChar == "x" || checkChar == "X",
            content: String(afterCloseBracket.dropFirst())
        )
    }

    private func toggleCheckbox(at lineIndex: Int) {
        var lines = text.components(separatedBy: "\n")
        guard lines.indices.contains(lineIndex), let parsed = Self.parseCheckboxLine(lines[lineIndex]) else { return }
        let newChecked = parsed.checked ? " " : "x"
        lines[lineIndex] = "\(parsed.indent)\(parsed.marker) [\(newChecked)] \(parsed.content)"
        text = lines.joined(separator: "\n")
    }

    // MARK: - Block rendering

    /// Parses a run of non-checkbox lines with `.full` syntax so headers/lists/
    /// code-blocks are recognized as distinct block types. Three gotchas, all
    /// found the hard way:
    ///
    /// 1. `.full` parsing does NOT leave block-boundary newlines or list-marker
    ///    characters (`- `, `1. `) in the resulting string at all — it
    ///    represents block structure purely via `presentationIntent` metadata
    ///    and expects the caller to reconstruct visible separators/markers from
    ///    it (this is the same pattern Apple's own AttributedString sample code
    ///    uses). Without this, every block runs together on one line with no
    ///    markers. Fix: walk runs, insert a separator whenever the identity of
    ///    the run's innermost block (`presentationIntent.components.first?.identity`)
    ///    changes, and re-add a bullet/ordinal marker for list items.
    /// 2. A single "\n" between two blocks just moves to the next line — it
    ///    doesn't reproduce the blank *row* the user sees in Text mode between
    ///    two paragraphs separated by a blank line in the source, so a first
    ///    version of this fix (a bare "\n" per block change) still read as
    ///    cramped/squished together. Fix: use a full blank line ("\n\n")
    ///    between blocks, except between consecutive items of the *same* list,
    ///    which should stay tight (no gap between "- one" and "- two").
    /// 3. A single typed Enter *within* a paragraph (no blank line) is a
    ///    CommonMark "soft break" — spec-correct rendering is a plain space,
    ///    not a line break; only two trailing spaces or a backslash count as a
    ///    "hard" break. That's correct for authored markdown but wrong for a
    ///    quick-notes app, where pressing Enter should always start a new
    ///    visual line — without a fix, line breaks only appeared if the user
    ///    wrote literal `<br>` or knew to add trailing hard-break markup. Fix:
    ///    detect `run.inlinePresentationIntent.contains(.softBreak)` and render
    ///    it as `"\n"` instead of the space Foundation puts there.
    ///
    /// Header/code runs are also bumped to the right font here — none of this
    /// is automatic from `Text(AttributedString)` alone.
    private static func renderBlock(_ text: String, fontSize: CGFloat) -> AttributedString {
        var options = AttributedString.MarkdownParsingOptions()
        options.interpretedSyntax = .full

        guard let parsed = try? AttributedString(markdown: text, options: options) else {
            var fallback = AttributedString(text)
            fallback.font = .system(size: fontSize)
            return fallback
        }

        var result = AttributedString()
        var previousIdentity: Int?
        var previousWasListItem = false

        for run in parsed.runs {
            let intent = run.presentationIntent

            if let identity = intent?.components.first?.identity, identity != previousIdentity {
                let isListItem = intent?.components.contains { component in
                    if case .listItem = component.kind { return true }
                    return false
                } ?? false

                if previousIdentity != nil {
                    // A single "\n" just moves to the next line — it doesn't
                    // reproduce the blank row the user actually sees in Text
                    // mode between two paragraphs separated by a blank line, so
                    // MD mode read as cramped/squished together. A full blank
                    // line ("\n\n") between separate blocks matches that, but
                    // items within the *same* list should stay tight (no gap
                    // between "- one" and "- two"), so only list-item-to-list-item
                    // transitions get the single-line spacing.
                    result += AttributedString(isListItem && previousWasListItem ? "\n" : "\n\n")
                }
                previousIdentity = identity
                previousWasListItem = isListItem

                if isListItem, let listItemKind = intent?.components.first(where: {
                    if case .listItem = $0.kind { return true }
                    return false
                })?.kind, case .listItem(let ordinal) = listItemKind {
                    let isOrdered = intent?.components.contains { component in
                        if case .orderedList = component.kind { return true }
                        return false
                    } ?? false
                    var marker = AttributedString(isOrdered ? "\(ordinal). " : "\u{2022} ")
                    marker.font = .system(size: fontSize)
                    result += marker
                }
            }

            var font = Font.system(size: fontSize)
            if let intent {
                for component in intent.components {
                    if case .header(let level) = component.kind {
                        let bump = max(6 - level, 0) * 3
                        font = .system(size: fontSize + CGFloat(bump), weight: .bold)
                    }
                    if case .codeBlock = component.kind {
                        font = .system(size: fontSize, design: .monospaced)
                    }
                }
            }
            if run.inlinePresentationIntent?.contains(.code) == true {
                font = .system(size: fontSize, design: .monospaced)
            }

            // CommonMark renders a single typed Enter within a paragraph as a
            // "soft break" — literally just a space, not a line break; only two
            // trailing spaces or a backslash count as a real ("hard") break.
            // That's correct spec behavior but wrong for a quick-notes app,
            // where pressing Enter should always start a new visual line. So
            // every soft break is rendered as an actual newline here instead of
            // the space Foundation's parser puts in its place.
            if run.inlinePresentationIntent?.contains(.softBreak) == true {
                var lineBreak = AttributedString("\n")
                lineBreak.font = font
                result += lineBreak
                continue
            }

            var slice = parsed[run.range]
            slice.font = font
            result += slice
        }

        return result
    }

    /// Renders a single checklist item's text as inline-only markdown (bold/
    /// italic/code/links), so those still work inside a checkbox line without
    /// needing the block-structure machinery above (a checklist item is never
    /// itself a header/list/code-block).
    private static func renderInline(_ text: String, fontSize: CGFloat, strikethrough: Bool) -> AttributedString {
        var options = AttributedString.MarkdownParsingOptions()
        options.interpretedSyntax = .inlineOnlyPreservingWhitespace

        var result: AttributedString
        if let parsed = try? AttributedString(markdown: text, options: options) {
            result = parsed
        } else {
            result = AttributedString(text)
        }
        result.font = .system(size: fontSize)
        if strikethrough {
            result.strikethroughStyle = .single
        }
        return result
    }
}
