import AppKit

/// The icons to choose from for the menu bar: PasteRing's own first, then common symbols. All
/// are template images, so macOS draws them in the menu bar's colour (white on a dark one).
enum MenuBarIcon {
    /// PasteRing's own icon, the default.
    static let app = "app"

    /// 16 per row in Settings, three rows.
    static let all: [String] = [
        app,
        "star.fill", "heart.fill", "flame.fill", "leaf.fill", "sun.max.fill", "moon.fill",
        "moon.stars.fill", "cloud.fill", "cloud.rain.fill", "bolt.fill", "snowflake", "drop.fill",
        "sparkles", "wand.and.stars", "crown.fill", "diamond.fill",
        "circle.fill", "square.fill", "triangle.fill", "hexagon.fill", "seal.fill", "flag.fill",
        "bookmark.fill", "bell.fill", "tag.fill", "paperclip", "pin.fill", "pencil",
        "scissors", "paintbrush.fill", "hammer.fill", "gearshape.fill",
        "cube.fill", "puzzlepiece.fill", "gamecontroller.fill", "music.note", "headphones", "camera.fill",
        "lightbulb.fill", "key.fill", "lock.fill", "house.fill", "globe", "airplane",
        "pawprint.fill", "tortoise.fill", "hare.fill",
    ]

    /// The SF Symbol drawn for an icon. PasteRing's own is a placeholder until it has one.
    static func symbol(for icon: String) -> String {
        icon == app ? "doc.on.clipboard" : icon
    }

    static func image(for icon: String) -> NSImage? {
        let image = NSImage(systemSymbolName: symbol(for: icon), accessibilityDescription: "PasteRing")
            ?? NSImage(systemSymbolName: symbol(for: app), accessibilityDescription: "PasteRing")
        image?.isTemplate = true
        return image
    }
}
