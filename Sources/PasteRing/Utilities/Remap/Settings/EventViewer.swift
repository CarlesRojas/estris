import SwiftUI

/// Every key and button pressed and released, newest first, with the device it came from.
struct EventViewer: View {
    let remap: Remap
    @ObservedObject var log: EventLog

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
                    Text(event.name)
                        .frame(width: 170, alignment: .leading)
                        .lineLimit(1)
                    Text(event.detail)
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(.secondary)
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
