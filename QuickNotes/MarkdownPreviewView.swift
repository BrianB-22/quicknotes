import SwiftUI

/// Read-only rendered markdown for a note's MD preview mode. Falls back to the
/// raw text if it fails to parse as markdown, rather than showing a blank pane.
struct MarkdownPreviewView: View {
    let text: String
    var fontSize: CGFloat

    var body: some View {
        ScrollView {
            Text(rendered)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
        }
    }

    /// Parses with `.full` syntax so headers/lists/code-blocks are recognized as
    /// distinct block types. Three gotchas, all found the hard way:
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
    private var rendered: AttributedString {
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
}
