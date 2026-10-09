import Foundation

/// One key or button press or release, as shown in the Event Viewer.
struct InputEvent: Identifiable {
    enum Phase: String {
        case down = "Down"
        case up = "Up"
    }

    let id = UUID()
    let time = Date()
    let device: String
    /// The device and input it came from, when it can be remapped.
    let source: InputDevice?
    let input: RemapInput?
    let phase: Phase
    let name: String
    let detail: String
    /// What it was remapped to, if it was.
    var result: String?
}

/// The latest events, oldest first, while the Event Viewer is open.
@MainActor
final class EventLog: ObservableObject {
    private static let limit = 300

    @Published private(set) var events: [InputEvent] = []

    func record(_ event: InputEvent) {
        events.append(event)
        if events.count > Self.limit {
            events.removeFirst(events.count - Self.limit)
        }
    }

    func clear() {
        events = []
    }
}
