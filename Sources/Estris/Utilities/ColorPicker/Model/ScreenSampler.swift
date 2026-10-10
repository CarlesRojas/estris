import AppKit

/// Reads what is on screen around a point, for the loupe and the color under the pointer.
/// Needs the Screen Recording permission; without it, nothing is captured.
enum ScreenSampler {
    private typealias CreateImage = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?

    /// `CGWindowListCreateImage`, looked up at run time: newer SDKs mark it unavailable in
    /// favour of ScreenCaptureKit, whose captures are asynchronous and too slow to follow the
    /// pointer.
    private static let createImage: CreateImage? = dlsym(dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_NOW), "CGWindowListCreateImage")
        .map { unsafeBitCast($0, to: CreateImage.self) }

    /// Never asked for by picking: the Color Picker pane offers it, as optional.
    static var isAllowed: Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// A square of `size` points centred on `point` (AppKit coordinates), of what is on
    /// screen below the window `windowNumber`.
    static func capture(around point: NSPoint, size: CGFloat, below windowNumber: Int) -> CGImage? {
        guard let createImage else { return nil }
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        let rect = CGRect(x: (point.x - size / 2).rounded(.down), y: (top - point.y - size / 2).rounded(.down), width: size, height: size)
        return createImage(
            rect,
            CGWindowListOption.optionOnScreenBelowWindow.rawValue,
            UInt32(windowNumber),
            CGWindowImageOption.bestResolution.rawValue
        )?.takeRetainedValue()
    }

    /// The color of the image's centre pixel, in sRGB.
    static func centerColor(of image: CGImage) -> NSColor? {
        let center = CGRect(x: image.width / 2, y: image.height / 2, width: 1, height: 1)
        guard let pixel = image.cropping(to: center),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.draw(pixel, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        guard let data = context.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        return NSColor(srgbRed: CGFloat(data[0]) / 255, green: CGFloat(data[1]) / 255, blue: CGFloat(data[2]) / 255, alpha: 1)
    }
}
