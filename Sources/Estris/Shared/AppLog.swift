import Foundation

/// What the utilities noticed and decided, newest first, shown under Developer > Logs and
/// also written to the system log ("Estris" in Console).
@MainActor
final class AppLog: ObservableObject {
    struct Entry: Identifiable {
        let id = UUID()
        let date: Date
        /// The utility that logged it, such as "Auto Quit".
        let source: String
        let message: String
    }

    private static let limit = 500

    @Published private(set) var entries: [Entry] = []

    func record(_ message: String, source: String) {
        NSLog("Estris %@: %@", source, message)
        entries.insert(Entry(date: Date(), source: source, message: message), at: 0)
        if entries.count > Self.limit {
            entries.removeLast(entries.count - Self.limit)
        }
    }

    func clear() {
        entries.removeAll()
    }

    /// Every entry as plain text, oldest first, for pasting into a bug report.
    var text: String {
        Self.text(of: entries)
    }

    /// Oldest first, one line each, for bug reports.
    static func text(of entries: [Entry]) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withTime, .withColonSeparatorInTime, .withFractionalSeconds]
        return entries.reversed()
            .map { "\(formatter.string(from: $0.date)) [\($0.source)] \($0.message)" }
            .joined(separator: "\n")
    }
}
