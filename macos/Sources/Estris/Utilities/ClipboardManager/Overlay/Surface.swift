import AppKit
import SwiftUI

extension View {
    /// Frosted material background for overlay elements, tinted as configured in Appearance.
    /// Pass `.infinity` as the radius for a capsule.
    func surface(cornerRadius: CGFloat, isSelected: Bool = false) -> some View {
        modifier(Surface(cornerRadius: cornerRadius, isSelected: isSelected))
    }
}

private struct Surface: ViewModifier {
    let cornerRadius: CGFloat
    let isSelected: Bool
    @EnvironmentObject private var appearance: AppearanceSettings
    @Environment(\.surfaceHovered) private var isHovered

    func body(content: Content) -> some View {
        content
            .background(shape.fill(appearance.surfaceTint(isSelected: isSelected, isHovered: isHovered) ?? .clear))
            .background(.regularMaterial, in: shape)
            .background {
                if appearance.shadowRadius > 0 {
                    OuterShadow(shape: shape, radius: appearance.shadowRadius, opacity: isSelected ? 0.35 : 0.22)
                }
            }
    }

    private var shape: AnyShape {
        cornerRadius.isInfinite
            ? AnyShape(Capsule())
            : AnyShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

/// A shadow drawn only outside `shape`. A plain `.shadow` on the whole view also shadows
/// the text and shows through translucent surfaces, darkening secondary text.
private struct OuterShadow: View {
    let shape: AnyShape
    let radius: CGFloat
    let opacity: Double

    var body: some View {
        shape
            .fill(Color.black)
            .shadow(color: .black.opacity(opacity), radius: radius, y: radius / 3)
            .mask {
                ZStack {
                    // Negative padding draws past the frame without changing the layout size.
                    Rectangle().padding(-radius * 4)
                    shape.fill(Color.black).blendMode(.destinationOut)
                }
                .compositingGroup()
            }
    }
}
