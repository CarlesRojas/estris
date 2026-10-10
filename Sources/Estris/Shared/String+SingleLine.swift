import Foundation

extension String {
    /// Trimmed, with line breaks shown as ⏎ so one-line previews stay meaningful.
    var singleLine: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isNewline)
            .joined(separator: " ⏎ ")
    }
}
