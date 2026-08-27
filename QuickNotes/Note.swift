import Foundation
import SwiftUI

enum NotePreviewMode: String, Codable {
    case text
    case markdown
}

enum NoteColorLabel: String, Codable, CaseIterable, Identifiable {
    case red, yellow, pink, blue, green, purple

    var id: String { rawValue }

    var label: String { rawValue.capitalized }

    var color: Color {
        switch self {
        case .red: return Color(red: 0.94, green: 0.30, blue: 0.28)
        case .yellow: return Color(red: 0.98, green: 0.85, blue: 0.35)
        case .pink: return Color(red: 0.98, green: 0.65, blue: 0.75)
        case .blue: return Color(red: 0.55, green: 0.75, blue: 0.98)
        case .green: return Color(red: 0.62, green: 0.85, blue: 0.55)
        case .purple: return Color(red: 0.75, green: 0.65, blue: 0.95)
        }
    }
}

struct Note: Identifiable, Codable {
    let id: UUID
    var createdAt: Date
    var modifiedAt: Date
    var isPinned: Bool
    var isLocked: Bool
    var colorLabel: NoteColorLabel?

    /// Plain text content. Always present for unlocked notes; nil for locked notes
    /// (the real content lives only in `encryptedPayload` and, transiently, in
    /// NoteStore's in-memory decrypted cache while unlocked for viewing).
    var plainText: String?

    /// Present only while `isLocked == true`.
    var encryptedPayload: EncryptedPayload?

    /// A first-line snapshot captured at the moment the note was locked, kept only
    /// if "show note preview while locked" was on at that time. Nil means the list
    /// falls back to a generic "Locked Note" label.
    var lockedTitleSnapshot: String?

    /// Nil for every note written before this setting existed — treat nil as
    /// `.text` rather than giving it a non-optional default, since a plain
    /// `JSONDecoder().decode(Note.self, from:)` call with no custom `init(from:)`
    /// would otherwise fail to decode (and silently drop) every note already on
    /// disk that predates this field.
    var previewMode: NotePreviewMode?

    init(id: UUID, createdAt: Date, modifiedAt: Date, isPinned: Bool = false,
         isLocked: Bool = false, colorLabel: NoteColorLabel? = nil, plainText: String? = nil,
         encryptedPayload: EncryptedPayload? = nil, lockedTitleSnapshot: String? = nil,
         previewMode: NotePreviewMode? = nil) {
        self.id = id
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.isPinned = isPinned
        self.isLocked = isLocked
        self.colorLabel = colorLabel
        self.plainText = plainText
        self.encryptedPayload = encryptedPayload
        self.lockedTitleSnapshot = lockedTitleSnapshot
        self.previewMode = previewMode
    }

    var effectivePreviewMode: NotePreviewMode {
        previewMode ?? .text
    }

    /// `showLockedPreview` reflects the current "show note preview while locked"
    /// setting, checked at display time so toggling it takes effect immediately
    /// for every locked note rather than only ones locked after the toggle changed.
    /// `unlockedText` is this note's decrypted content if it's currently unlocked
    /// for viewing this session — when present, the title reflects that live text
    /// (with an open-lock icon) instead of the stale locked snapshot.
    func listTitle(showLockedPreview: Bool, unlockedText: String? = nil) -> String {
        if isLocked {
            if let unlockedText {
                return "🔓 " + Self.firstLine(of: unlockedText, placeholder: "New Note")
            }
            let snapshot = showLockedPreview ? lockedTitleSnapshot : nil
            return "🔒 " + (snapshot ?? "Locked Note")
        }
        return Self.firstLine(of: plainText ?? "", placeholder: "New Note")
    }

    private static func firstLine(of text: String, placeholder: String) -> String {
        let firstLine = text
            .split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
            .first.map(String.init) ?? ""
        let trimmed = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? placeholder : trimmed
    }
}
