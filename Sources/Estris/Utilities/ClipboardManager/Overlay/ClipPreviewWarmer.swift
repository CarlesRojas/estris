import AppKit

/// Gets entries ready to draw before they are shown: the app's icon and name, the image
/// read and decoded, the rich text parsed. Each is slow the first time (disk, Launch
/// Services, RTF), and done on the spot it made the first steps through the history lag.
/// One entry per turn of the run loop, so key presses are handled in between.
@MainActor
final class ClipPreviewWarmer {
    private var queue: [ClipItem] = []
    private var baseSize: CGFloat = 13
    private var isRunning = false

    /// Replaces whatever was waiting: the latest order is the one that matters.
    func warm(_ items: [ClipItem], baseSize: CGFloat) {
        queue = items
        self.baseSize = baseSize
        guard !isRunning else { return }
        isRunning = true
        step()
    }

    private func step() {
        guard !queue.isEmpty else {
            isRunning = false
            return
        }
        Self.prepare(queue.removeFirst(), baseSize: baseSize)
        // A timer, not the main queue: queued blocks can all run back to back before events.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.001) { [weak self] in
            MainActor.assumeIsolated { self?.step() }
        }
    }

    private static func prepare(_ item: ClipItem, baseSize: CGFloat) {
        _ = AppIcons.icon(for: item.sourceBundleID)
        _ = AppIcons.name(for: item.sourceBundleID)
        // Reading the bitmap's pixels decodes the PNG now rather than when first drawn.
        if let image = ClipThumbnails.image(for: item) {
            for case let bitmap as NSBitmapImageRep in image.representations {
                _ = bitmap.bitmapData
            }
        }
        _ = RichTextRenderer.attributed(for: item, baseSize: baseSize, singleLine: false)
    }
}
