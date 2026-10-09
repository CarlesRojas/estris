import AppKit
import Carbon.HIToolbox
import SwiftUI

/// A button showing a shortcut; click it, then press the new combination. Esc cancels.
/// Global hotkeys are paused while recording so the combination reaches this view.
struct ShortcutRecorder: View {
    @Binding var shortcut: Shortcut
    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        Button {
            isRecording ? stop() : start()
        } label: {
            Text(isRecording ? String(localized: "Press keys…") : shortcut.displayString)
                .monospacedDigit()
                .frame(minWidth: 90)
        }
        .help(isRecording ? String(localized: "Press the new shortcut, or Esc to cancel") : String(localized: "Click to change"))
        .onDisappear(perform: stop)
    }

    private func start() {
        isRecording = true
        HotKeyCenter.shared.suspend()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == UInt16(kVK_Escape) {
                stop()
            } else if let recorded = Shortcut(event: event) {
                shortcut = recorded
                stop()
            } else {
                // Needs ⌘, ⌥ or ⌃.
                NSSound.beep()
            }
            return nil
        }
    }

    private func stop() {
        guard isRecording else { return }
        isRecording = false
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        HotKeyCenter.shared.resume()
    }
}
