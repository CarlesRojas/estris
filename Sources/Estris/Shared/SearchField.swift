import AppKit
import SwiftUI

/// A native search field.
struct SearchField: NSViewRepresentable {
    @Binding var text: String
    var prompt = "Search"

    /// A touch lighter than the window behind it, so the field stands out from the page.
    private static let fill = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor.white.withAlphaComponent(0.12)
            : NSColor.white
    }

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.placeholderString = Bundle.main.localizedString(forKey: prompt, value: nil, table: nil)
        field.delegate = context.coordinator
        field.drawsBackground = true
        field.backgroundColor = Self.fill
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        if field.stringValue != text {
            field.stringValue = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField else { return }
            text.wrappedValue = field.stringValue
        }
    }
}
