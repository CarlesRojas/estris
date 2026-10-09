import SwiftUI

/// The Mouse settings pane: Middle Click and Pointer Speed tabs.
struct MousePane: View {
    private enum Tab: String, CaseIterable {
        case middleClick = "Middle Click"
        case pointerSpeed = "Pointer Speed"
    }

    @ObservedObject var settings: MouseSettings
    @State private var tab = Tab.middleClick

    var body: some View {
        UtilityPane(
            pane: .mouse,
            summary: "Middle click from the trackpad, and pointer speed beyond System Settings.",
            tab: $tab
        ) { tab in
            switch tab {
            case .middleClick:
                middleClickForm
            case .pointerSpeed:
                pointerSpeedForm
            }
        }
    }

    private var middleClickForm: some View {
        Form {
            Section {
                Picker("Middle click", selection: $settings.middleClick) {
                    ForEach(MiddleClickGesture.allCases) { gesture in
                        Text(gesture.title).tag(gesture)
                    }
                }
            } header: {
                Text("Trackpad")
            } footer: {
                Text("A quick tap with the fingers held still clicks the middle button where the pointer is, for example to open a link in a new tab. If Look Up is set to a three-finger tap in System Settings > Trackpad, turn it off to use three fingers here. Needs Accessibility access.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .settingsPage()
    }

    private var pointerSpeedForm: some View {
        Form {
            speedSection("Mouse", sets: $settings.setsMouseSpeed, speed: $settings.mouseSpeed)
            speedSection("Trackpad", sets: $settings.setsTrackpadSpeed, speed: $settings.trackpadSpeed)
            Section {
            } footer: {
                Text("System Settings goes up to 3. Turning a speed off goes back to the one set in System Settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .settingsPage()
    }

    private func speedSection(_ title: String, sets: Binding<Bool>, speed: Binding<Double>) -> some View {
        Section(title) {
            Toggle("Set \(title.lowercased()) speed", isOn: sets)
            LabeledContent("Speed") {
                HStack {
                    Slider(value: speed, in: MouseSettings.speedRange) {
                        Text("Speed")
                    } minimumValueLabel: {
                        Text("Slow")
                    } maximumValueLabel: {
                        Text("Fast")
                    }
                    .labelsHidden()
                    Text(speed.wrappedValue, format: .number.precision(.fractionLength(1)))
                        .monospacedDigit()
                        .frame(width: 28, alignment: .trailing)
                }
            }
            .disabled(!sets.wrappedValue)
        }
    }
}
