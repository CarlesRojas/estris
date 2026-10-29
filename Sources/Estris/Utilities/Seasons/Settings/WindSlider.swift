import AppKit
import SwiftUI

/// The system slider for the wind, which blows either way: its bar fills from calm in the
/// middle toward the knob, with a small mark at calm, where the system's fills from the left.
struct WindSlider: NSViewRepresentable {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let fill: NSColor

    func makeNSView(context: Context) -> NSSlider {
        let slider = NSSlider()
        slider.cell = CenteredSliderCell()
        slider.minValue = range.lowerBound
        slider.maxValue = range.upperBound
        slider.doubleValue = value
        slider.controlSize = .small
        slider.isContinuous = true
        slider.target = context.coordinator
        slider.action = #selector(Coordinator.changed(_:))
        return slider
    }

    func updateNSView(_ slider: NSSlider, context: Context) {
        context.coordinator.value = $value
        if slider.doubleValue != value { slider.doubleValue = value }
        if let cell = slider.cell as? CenteredSliderCell, cell.fill != fill {
            cell.fill = fill
            slider.needsDisplay = true
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(value: $value)
    }

    final class Coordinator: NSObject {
        var value: Binding<Double>

        init(value: Binding<Double>) {
            self.value = value
        }

        @objc func changed(_ slider: NSSlider) {
            value.wrappedValue = slider.doubleValue
        }
    }
}

/// A slider cell whose bar fills from the middle value, 0, to the knob.
private final class CenteredSliderCell: NSSliderCell {
    var fill: NSColor = .controlAccentColor

    override func drawBar(inside rect: NSRect, flipped: Bool) {
        let radius = rect.height / 2
        NSColor.quaternaryLabelColor.setFill()
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
        // Where the knob's centre is at calm and now, along the stretch it travels.
        let span = maxValue - minValue
        guard span > 0 else { return }
        let travel = rect.width - knobThickness
        let start = rect.minX + knobThickness / 2
        let calm = start + travel * CGFloat((0 - minValue) / span)
        let knob = start + travel * CGFloat((doubleValue - minValue) / span)
        if abs(knob - calm) > 0.5 {
            fill.setFill()
            let filled = NSRect(x: min(calm, knob), y: rect.minY, width: abs(knob - calm), height: rect.height)
            NSBezierPath(roundedRect: filled, xRadius: radius, yRadius: radius).fill()
        }
        NSColor.secondaryLabelColor.setFill()
        NSBezierPath(roundedRect: NSRect(x: calm - 0.75, y: rect.midY - rect.height * 1.25, width: 1.5, height: rect.height * 2.5), xRadius: 0.75, yRadius: 0.75).fill()
    }
}
