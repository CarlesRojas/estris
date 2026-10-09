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
    let phase: Phase
    let name: String
    let detail: String
}

/// The latest events, newest first, while the Event Viewer is open.
@MainActor
final class EventLog: ObservableObject {
    private static let limit = 300

    @Published private(set) var events: [InputEvent] = []

    func record(_ event: InputEvent) {
        events.insert(event, at: 0)
        if events.count > Self.limit {
            events.removeLast(events.count - Self.limit)
        }
    }

    func clear() {
        events = []
    }
}
