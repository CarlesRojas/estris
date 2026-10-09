import SwiftUI

/// Every key and button pressed and released, newest at the bottom, with the device it came
/// from. Follows new events while scrolled to the bottom.
struct EventViewer: View {
    let remap: Remap
    @ObservedObject var log: EventLog
    /// Opens a new mapping from the clicked key or button on its device.
    let map: (InputDevice, RemapInput) -> Void

    /// Whether the end of the list is on screen, so new events scroll into view.
    @State private var isAtBottom = true
    /// When the list last scrolled itself: the end briefly leaves the screen as a row is
    /// added, which isn't the user scrolling away.
    @State private var lastAutoScroll = Date.distantPast
    private static let bottomID = "bottom"
    /// The row under the pointer, which shows Create Mapping when its input can be remapped.
    @State private var hoveredRow: UUID?

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

            ScrollViewReader { proxy in
                List {
                    ForEach(log.events) { event in
                        row(event)
                    }
                    Color.clear
                        .frame(height: 1)
                        .listRowSeparator(.hidden)
                        .id(Self.bottomID)
                        .onAppear { isAtBottom = true }
                        .onDisappear {
                            if Date().timeIntervalSince(lastAutoScroll) > 0.5 { isAtBottom = false }
                        }
                }
                .listStyle(.inset)
                .onChange(of: log.events.last?.id) { _ in
                    guard isAtBottom else { return }
                    lastAutoScroll = Date()
                    proxy.scrollTo(Self.bottomID, anchor: .bottom)
                }
                .onAppear {
                    proxy.scrollTo(Self.bottomID, anchor: .bottom)
                }
            }
        }
        .onAppear { remap.isViewing = true }
        .onDisappear {
            remap.isViewing = false
            remap.isOverViewerLink = false
        }
    }

    private func row(_ event: InputEvent) -> some View {
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
                Text(event.name)
                Text("(\(event.detail))")
                    .foregroundStyle(.secondary)
                if let result = event.result {
                    Image(systemName: "arrow.right")
                        .foregroundStyle(Color.accentColor)
                    Text(result)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.accentColor)
                }
                if hoveredRow == event.id, let source = event.source, let input = event.input, input != .mouseButton(0) {
                    Button("Create Mapping") {
                        remap.isOverViewerLink = false
                        map(source, input)
                    }
                    .controlSize(.small)
                    .onHover { remap.isOverViewerLink = $0 }
                }
            }
            .lineLimit(1)
            Spacer()
            Text(event.device)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        // Tall enough for the button, so rows don't grow when it appears.
        .frame(minHeight: 22)
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering {
                hoveredRow = event.id
            } else if hoveredRow == event.id {
                hoveredRow = nil
            }
        }
    }
}

