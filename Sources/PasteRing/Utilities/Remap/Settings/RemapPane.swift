import SwiftUI

/// The Remap settings pane: the on/off switch, then Mappings and Event Viewer tabs.
struct RemapPane: View {
    private enum Tab: String, CaseIterable {
        case mappings = "Mappings"
        case eventViewer = "Event Viewer"
    }

    let remap: Remap
    @ObservedObject var settings: RemapSettings
    @State private var tab = Tab.mappings

    var body: some View {
        UtilityPane(
            pane: .remap,
            summary: "Change what keys and mouse buttons do, per device.",
            isOn: $settings.isEnabled,
            tab: $tab
        ) { tab in
            switch tab {
            case .mappings:
                MappingsView(remap: remap, settings: settings, devices: remap.devices)
            case .eventViewer:
                EventViewer(remap: remap, log: remap.eventLog)
            }
        }
    }
}

/// Devices on the left, the selected device's mappings on the right.
private struct MappingsView: View {
    let remap: Remap
    @ObservedObject var settings: RemapSettings
    @ObservedObject var devices: InputDevices
    @State private var selection: String?

    /// Connected devices, then disconnected ones that still have mappings.
    private var listed: [InputDevice] {
        let connected = devices.connected
        let saved = settings.devices
            .filter { id, entry in !entry.mappings.isEmpty && !connected.contains { $0.id == id } }
            .map { id, entry in InputDevice(id: id, name: entry.name, kind: entry.kind, isConnected: false) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return connected + saved
    }

    var body: some View {
        let items = listed
        HStack(spacing: 0) {
            List(selection: $selection) {
                section("Keyboards", devices: items.filter { $0.kind == .keyboard })
                section("Mice and Trackpads", devices: items.filter { $0.kind == .mouse })
            }
            .listStyle(.sidebar)
            .frame(width: 250)

            Divider()

            if let device = items.first(where: { $0.id == selection }) {
                DeviceMappingsView(remap: remap, settings: settings, device: device)
                    .id(device.id)
            } else {
                Text("No device selected")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            devices.refresh()
            if selection == nil { selection = listed.first?.id }
        }
    }

    @ViewBuilder
    private func section(_ title: String, devices: [InputDevice]) -> some View {
        if !devices.isEmpty {
            Section(title) {
                ForEach(devices) { device in
                    HStack {
                        Label(device.name, systemImage: device.kind == .keyboard ? "keyboard" : "computermouse")
                            .lineLimit(1)
                            .opacity(device.isConnected ? 1 : 0.5)
                        Spacer()
                        let count = settings.mappings(for: device.id).count
                        if count > 0 {
                            Text("\(count)")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tag(device.id)
                }
            }
        }
    }
}

/// A device's mappings, each a source and what it becomes.
private struct DeviceMappingsView: View {
    let remap: Remap
    @ObservedObject var settings: RemapSettings
    let device: InputDevice
    @State private var isAdding = false

    var body: some View {
        let mappings = settings.mappings(for: device.id)
        Form {
            Section {
                if mappings.isEmpty {
                    Text("No mappings")
                        .foregroundStyle(.secondary)
                }
                ForEach(mappings) { mapping in
                    HStack(spacing: 10) {
                        InputButton(remap: remap, device: device, input: mapping.input) { input in
                            var changed = mapping
                            changed.input = input
                            settings.update(changed, on: device.id)
                        }
                        Image(systemName: "arrow.right")
                            .foregroundStyle(.secondary)
                        OutputButton(input: mapping.input, output: mapping.output) { output in
                            var changed = mapping
                            changed.output = output
                            settings.update(changed, on: device.id)
                        }
                        Spacer()
                        Button {
                            settings.remove(mapping, from: device.id)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .help("Remove this mapping")
                    }
                }
                Button("Add Mapping") {
                    isAdding = true
                }
            } header: {
                Text(device.isConnected ? device.name : "\(device.name) (not connected)")
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $isAdding) {
            NewMappingSheet(remap: remap, device: device) { mapping in
                settings.add(mapping, to: device)
            }
        }
    }
}

/// Picks the key or button to remap from, by pressing it or from the list.
private struct NewMappingSheet: View {
    let remap: Remap
    let device: InputDevice
    let add: (Mapping) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var input: RemapInput?
    @State private var output: RemapOutput?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Mapping for \(device.name)")
                .font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    Text("From")
                    InputButton(remap: remap, device: device, input: input) { input = $0 }
                }
                GridRow {
                    Text("To")
                    OutputButton(input: input, output: output) { output = $0 }
                }
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add") {
                    if let input, let output {
                        add(Mapping(input: input, output: output))
                    }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(input == nil || output == nil)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}

/// Shows the key or button remapped from; click to change it.
private struct InputButton: View {
    let remap: Remap
    let device: InputDevice
    let input: RemapInput?
    let choose: (RemapInput) -> Void
    @State private var isPicking = false

    var body: some View {
        Button(input?.title ?? "Choose…") { isPicking = true }
            .frame(minWidth: 160, alignment: .leading)
            .popover(isPresented: $isPicking, arrowEdge: .bottom) {
                InputPicker(remap: remap, device: device) { input in
                    isPicking = false
                    choose(input)
                }
            }
    }
}

/// Shows what the input becomes; click to change it.
private struct OutputButton: View {
    let input: RemapInput?
    let output: RemapOutput?
    let choose: (RemapOutput) -> Void
    @State private var isPicking = false

    var body: some View {
        Button(output?.title ?? "Choose…") { isPicking = true }
            .frame(minWidth: 160, alignment: .leading)
            .popover(isPresented: $isPicking, arrowEdge: .bottom) {
                ChoiceList(sections: Choices.outputs(for: input)) { output in
                    isPicking = false
                    choose(output)
                }
                .frame(width: 340, height: 440)
            }
    }
}

/// The list of keys and buttons, with a button to record one by pressing it on the device.
private struct InputPicker: View {
    let remap: Remap
    let device: InputDevice
    let choose: (RemapInput) -> Void
    @State private var isRecording = false

    var body: some View {
        VStack(spacing: 0) {
            Button {
                if isRecording {
                    remap.cancelRecording()
                    isRecording = false
                } else {
                    isRecording = true
                    remap.record(on: device.id) { input in
                        isRecording = false
                        choose(input)
                    }
                }
            } label: {
                Label(isRecording ? "Press a key or button on \(device.name)…" : "Record from \(device.name)",
                      systemImage: isRecording ? "record.circle.fill" : "record.circle")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .disabled(!device.isConnected)
            .padding([.horizontal, .top], 12)

            ChoiceList(sections: Choices.inputs(for: device)) { input in
                remap.cancelRecording()
                choose(input)
            }
        }
        .frame(width: 340, height: 480)
        .onDisappear {
            if isRecording { remap.cancelRecording() }
        }
    }
}
