import AppKit
import SwiftUI

/// Turns a rich text entry's saved contents back into styled text SwiftUI can draw:
/// fonts (scaled to the card), bold and italic, colours, underline and strikethrough.
@MainActor
enum RichTextRenderer {
    private struct Key: Hashable {
        let id: UUID
        let size: CGFloat
        let singleLine: Bool
    }

    private static var cache: [Key: AttributedString] = [:]
    private static var sources: [UUID: NSAttributedString] = [:]

    /// Nil when the entry has no readable rich text.
    static func attributed(for item: ClipItem, baseSize: CGFloat, singleLine: Bool) -> AttributedString? {
        guard item.kind == .richText, item.hasPayload == true else { return nil }
        let key = Key(id: item.id, size: baseSize, singleLine: singleLine)
        if let cached = cache[key] { return cached }
        guard let source = source(for: item) else { return nil }
        let result = convert(source, baseSize: baseSize, singleLine: singleLine)
        cache[key] = result
        return result
    }

    private static func source(for item: ClipItem) -> NSAttributedString? {
        if let cached = sources[item.id] { return cached }
        guard let payload = ClipPayloadStore.load(item.id), let types = payload.first else { return nil }
        // RTF first: HTML has to go through WebKit, which is slow.
        let source: NSAttributedString?
        if let rtf = types["public.rtf"] {
            source = NSAttributedString(rtf: rtf, documentAttributes: nil)
        } else if let rtfd = types["com.apple.flat-rtfd"] {
            source = NSAttributedString(rtfd: rtfd, documentAttributes: nil)
        } else if let html = types["public.html"] {
            source = NSAttributedString(html: html, documentAttributes: nil)
        } else {
            source = nil
        }
        sources[item.id] = source
        return source
    }

    private static func convert(_ source: NSAttributedString, baseSize: CGFloat, singleLine: Bool) -> AttributedString {
        let trimmed = trimmingWhitespace(source)
        // Scale so the first run's size becomes the card's text size; relative sizes stay.
        let firstSize = (trimmed.length > 0 ? trimmed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont : nil)?.pointSize ?? baseSize
        let scale = baseSize / max(firstSize, 1)

        var result = AttributedString()
        trimmed.enumerateAttributes(in: NSRange(location: 0, length: trimmed.length)) { attributes, range, _ in
            var text = (trimmed.string as NSString).substring(with: range)
            if singleLine {
                text = text.replacingOccurrences(of: "\n", with: " ⏎ ")
            }
            var run = AttributedString(text)
            let font = (attributes[.font] as? NSFont) ?? NSFont.systemFont(ofSize: firstSize)
            let size = min(max(font.pointSize * scale, baseSize * 0.75), baseSize * 1.8)
            let scaledFont = NSFont(descriptor: font.fontDescriptor, size: size) ?? NSFont.systemFont(ofSize: size)
            run.font = Font(scaledFont as CTFont)
            if let color = attributes[.foregroundColor] as? NSColor, !isNeutral(color) {
                run.foregroundColor = Color(nsColor: color)
            }
            if let underline = attributes[.underlineStyle] as? Int, underline != 0 {
                run.underlineStyle = Text.LineStyle.single
            }
            if let strike = attributes[.strikethroughStyle] as? Int, strike != 0 {
                run.strikethroughStyle = Text.LineStyle.single
            }
            result += run
        }
        return result
    }

    /// Black, white and greys follow the overlay's own text colour, so text copied as black
    /// stays readable on a dark surface. Real colours are kept.
    private static func isNeutral(_ color: NSColor) -> Bool {
        guard let rgb = color.usingColorSpace(.sRGB) else { return true }
        let spread = max(rgb.redComponent, rgb.greenComponent, rgb.blueComponent)
            - min(rgb.redComponent, rgb.greenComponent, rgb.blueComponent)
        return spread < 0.08
    }

    private static func trimmingWhitespace(_ source: NSAttributedString) -> NSAttributedString {
        let string = source.string as NSString
        var start = 0
        var end = string.length
        let whitespace = CharacterSet.whitespacesAndNewlines
        while start < end, let scalar = UnicodeScalar(string.character(at: start)), whitespace.contains(scalar) { start += 1 }
        while end > start, let scalar = UnicodeScalar(string.character(at: end - 1)), whitespace.contains(scalar) { end -= 1 }
        return source.attributedSubstring(from: NSRange(location: start, length: end - start))
    }
}
