import SwiftUI

/// Every key and button pressed and released, newest first, with the device it came from.
struct EventViewer: View {
    let remap: Remap
    @ObservedObject var log: EventLog
    /// Opens a new mapping from the clicked key or button on its device.
    let map: (InputDevice, RemapInput) -> Void

    private static let timeFormat: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(log.events.isEmpty ? "No events yet" : "\(log.events.count) events")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Clear") { log.clear() }
                    .disabled(log.events.isEmpty)
            }
            .pinnedAboveList()

            List(log.events) { event in
                HStack(spacing: 12) {
                    Text(Self.timeFormat.string(from: event.time))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 90, alignment: .leading)
                    Text(event.phase.rawValue)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(event.phase == .down ? Color.accentColor : .secondary)
                        .frame(width: 40, alignment: .leading)
                    HStack(spacing: 6) {
                        if let source = event.source, let input = event.input, input != .mouseButton(0) {
                            Button(event.name) { map(source, input) }
                                .buttonStyle(.link)
                                .help("Remap it")
                        } else {
                            Text(event.name)
                        }
                        Text("(\(event.detail))")
                            .foregroundStyle(.secondary)
                    }
                    .lineLimit(1)
                    Spacer()
                    Text(event.device)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .listStyle(.inset)
        }
        .onAppear { remap.isViewing = true }
        .onDisappear { remap.isViewing = false }
    }
}
