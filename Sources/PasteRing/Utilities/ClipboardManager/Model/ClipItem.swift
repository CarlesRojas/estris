import Foundation

struct ClipItem: Identifiable, Equatable, Codable {
    let id: UUID
    let text: String
    let date: Date
    /// App the text was copied from. Missing in entries saved by older versions.
    let sourceBundleID: String?

    init(text: String, sourceBundleID: String?) {
        id = UUID()
        self.text = text
        date = Date()
        self.sourceBundleID = sourceBundleID
    }
}
