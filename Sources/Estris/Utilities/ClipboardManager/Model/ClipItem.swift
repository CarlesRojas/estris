import Foundation

/// What an entry holds. Images and files keep their full clipboard contents in a payload
/// file, so pasting them gives back exactly what was copied. Text is always plain.
enum ClipKind: String, Codable {
    case text
    /// Styled text recorded by older versions; shown and pasted as plain text.
    case richText
    case image
    case files
}

struct ClipItem: Identifiable, Equatable, Codable {
    let id: UUID
    /// Plain text to show and search: the text itself, or the file names for files.
    let text: String
    let date: Date
    /// App the entry was copied from. Missing in entries saved by older versions.
    let sourceBundleID: String?
    /// Arrived through Universal Clipboard from another Apple device.
    let isFromOtherDevice: Bool?
    let kindValue: ClipKind?
    /// Identifies the content, for spotting duplicates of non-text entries.
    let fingerprint: String?
    /// Whether full clipboard contents were saved next to the history.
    let hasPayload: Bool?

    var kind: ClipKind { kindValue ?? .text }

    init(
        text: String,
        sourceBundleID: String?,
        kind: ClipKind = .text,
        isFromOtherDevice: Bool = false,
        fingerprint: String? = nil,
        hasPayload: Bool = false
    ) {
        id = UUID()
        self.text = text
        date = Date()
        self.sourceBundleID = sourceBundleID
        self.isFromOtherDevice = isFromOtherDevice
        kindValue = kind
        self.fingerprint = fingerprint
        self.hasPayload = hasPayload
    }

    /// Two entries hold the same content.
    func hasSameContent(as other: ClipItem) -> Bool {
        if let fingerprint, let otherFingerprint = other.fingerprint {
            return fingerprint == otherFingerprint
        }
        return kind == other.kind && text == other.text
    }
}
