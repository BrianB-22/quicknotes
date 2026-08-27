import SwiftUI
import AppKit

/// SwiftUI's `.help()` tooltip modifier is unreliable for icon-only buttons hosted
/// inside an `NSPopover` (a long-standing AppKit/SwiftUI bridging issue for menu
/// bar apps) — hover tooltips frequently just never appear. This uses AppKit's
/// own `NSView.toolTip`, which has always worked reliably in popovers, as a
/// transparent overlay that passes clicks through to the view underneath it.
private final class TooltipNSView: NSView {
    var text: String = "" {
        didSet { toolTip = text }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

private struct TooltipOverlay: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> TooltipNSView {
        let view = TooltipNSView()
        view.text = text
        return view
    }

    func updateNSView(_ nsView: TooltipNSView, context: Context) {
        nsView.text = text
    }
}

extension View {
    func reliableHelp(_ text: String) -> some View {
        overlay(TooltipOverlay(text: text))
    }
}
