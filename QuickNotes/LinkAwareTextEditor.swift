import SwiftUI
import AppKit

/// A plain-text editor that behaves like `TextEditor` but auto-detects URLs and
/// file paths as clickable links (Cmd-click to open, matching the standard
/// AppKit convention for editable text views) and accepts dropped files/folders
/// by inserting their path as text at the drop point.
struct LinkAwareTextEditor: NSViewRepresentable {
    @Binding var text: String
    var fontSize: CGFloat
    @Binding var shouldFocus: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = DroppableTextView()
        textView.delegate = context.coordinator
        textView.isEditable = true
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.drawsBackground = false
        textView.string = text
        textView.font = .systemFont(ofSize: fontSize)
        textView.registerForDraggedTypes([.fileURL])
        textView.textContainer?.widthTracksTextView = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false

        context.coordinator.applyLinkDetection(to: textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        // LinkAwareTextEditor is a struct — without this, the Coordinator (which
        // lives across updates) keeps writing back through whichever `text`
        // binding existed when it was first created, silently saving edits to
        // the wrong note (or nowhere useful) once the selection changes.
        context.coordinator.parent = self

        guard let textView = scrollView.documentView as? NSTextView else { return }

        if textView.string != text {
            textView.string = text
            context.coordinator.applyLinkDetection(to: textView)
        }

        if textView.font?.pointSize != fontSize {
            let font = NSFont.systemFont(ofSize: fontSize)
            textView.font = font
            textView.textStorage?.addAttribute(.font, value: font, range: NSRange(location: 0, length: textView.string.utf16.count))
        }

        // One-shot: consume the request immediately so this doesn't keep firing
        // (and fighting the user's own clicks) on every later re-render, e.g.
        // every keystroke, which is what made typing intermittently stop working.
        if shouldFocus {
            DispatchQueue.main.async {
                if textView.window?.firstResponder !== textView {
                    textView.window?.makeFirstResponder(textView)
                }
                shouldFocus = false
            }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: LinkAwareTextEditor
        private static let webDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

        init(_ parent: LinkAwareTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            applyLinkDetection(to: textView)
        }

        func applyLinkDetection(to textView: NSTextView) {
            guard let textStorage = textView.textStorage else { return }
            let string = textStorage.string
            let fullRange = NSRange(location: 0, length: textStorage.length)

            textStorage.beginEditing()
            textStorage.removeAttribute(.link, range: fullRange)

            Self.webDetector?.enumerateMatches(in: string, range: fullRange) { match, _, _ in
                guard let match, let url = match.url else { return }
                textStorage.addAttribute(.link, value: url, range: match.range)
            }

            // File paths can contain spaces, so they can't be matched token-by-token
            // like a web URL. Since a dropped file always lands on its own line,
            // treat a whole line as a file link when it's nothing but a path —
            // this handles paths with spaces without guessing where one ends
            // inside a normal sentence.
            (string as NSString).enumerateSubstrings(in: fullRange, options: .byLines) { substring, substringRange, _, _ in
                guard let substring else { return }
                let trimmed = substring.trimmingCharacters(in: .whitespaces)
                guard trimmed.hasPrefix("/"), let trimmedRange = substring.range(of: trimmed) else { return }
                let nsRange = NSRange(trimmedRange, in: substring)
                let linkRange = NSRange(location: substringRange.location + nsRange.location, length: nsRange.length)
                textStorage.addAttribute(.link, value: URL(fileURLWithPath: trimmed), range: linkRange)
            }

            textStorage.endEditing()
        }

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            if let url = link as? URL {
                NSWorkspace.shared.open(url)
                return true
            }
            if let string = link as? String, let url = URL(string: string) {
                NSWorkspace.shared.open(url)
                return true
            }
            return false
        }
    }
}

/// Inserts a dropped file or folder's path as plain text at the drop location,
/// instead of AppKit's default (version-dependent) handling of dropped files.
private final class DroppableTextView: NSTextView {
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) {
            return .copy
        }
        return super.draggingEntered(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let urls = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL], !urls.isEmpty else {
            return super.performDragOperation(sender)
        }

        let dropPoint = convert(sender.draggingLocation, from: nil)
        let charIndex = characterIndexForInsertion(at: dropPoint)
        let insertion = urls.map(\.path).joined(separator: "\n") + "\n"
        let range = NSRange(location: charIndex, length: 0)

        if shouldChangeText(in: range, replacementString: insertion) {
            textStorage?.replaceCharacters(in: range, with: insertion)
            didChangeText()
        }
        return true
    }
}
