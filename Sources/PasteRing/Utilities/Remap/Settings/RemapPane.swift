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
    /// The device shown in Mappings, kept here so the Event Viewer can open one.
    @State private var selection = ""

    var body: some View {
        UtilityPane(
            pane: .remap,
            summary: "Change what keys and mouse buttons do, per device.",
            isOn: $settings.isEnabled,
            tab: $tab
        ) { tab in
            switch tab {
            case .mappings:
                MappingsView(remap: remap, settings: settings, devices: remap.devices, selection: $selection)
            case .eventViewer:
                EventViewer(remap: remap, log: remap.eventLog) { device, input in
                    settings.addMapping(from: input, to: device)
                    selection = device.id
                    self.tab = .mappings
                }
            }
        }
    }
}

/// A device menu at the top, then the chosen device's mappings.
private struct MappingsView: View {
    let remap: Remap
    @ObservedObject var settings: RemapSettings
    @ObservedObject var devices: InputDevices
    @Binding var selection: String
    @State private var isRenaming = false
    @State private var newName = ""

    /// Connected devices, then disconnected ones that still have mappings, with the names
    /// the user gave them.
    private var listed: [InputDevice] {
        let connected = devices.connected
        let saved = settings.devices
            .filter { id, entry in !entry.mappings.isEmpty && !connected.contains { $0.id == id } }
            .map { id, entry in InputDevice(id: id, name: entry.name, kind: entry.kind, isConnected: false) }
        return (connected + saved)
            .map { InputDevice(id: $0.id, name: settings.name(of: $0), kind: $0.kind, isConnected: $0.isConnected) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        let items = listed
        let device = items.first { $0.id == selection }
        Form {
            Section {
                HStack {
                    Picker("Device", selection: $selection) {
                        ForEach(items) { device in
                            deviceLabel(device)
                        }
                    }
                    Button("Rename…") {
                        newName = device?.name ?? ""
                        isRenaming = true
                    }
                    .disabled(device == nil)
                }
            }

            if let device {
                let mappings = settings.mappings(for: device.id)
                Section {
                    if mappings.isEmpty {
                        Text("No mappings")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(mappings) { mapping in
                        row(mapping, on: device)
                    }
                    Button("Add Mapping") {
                        settings.addMapping(to: device)
                    }
                } header: {
                    Text("Mappings")
                }
            }
        }
        .formStyle(.grouped)
        .settingsPage()
        .alert("Rename Device", isPresented: $isRenaming) {
            TextField("Name", text: $newName)
            Button("Rename") {
                if let device { settings.rename(device.id, to: newName) }
            }
            if let device, settings.customNames[device.id] != nil {
                Button("Use Original Name") {
                    settings.rename(device.id, to: "")
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .onAppear {
            devices.refresh()
            if device == nil { selection = listed.first?.id ?? "" }
        }
    }

    private func deviceLabel(_ device: InputDevice) -> some View {
        Label(device.name + (device.isConnected ? "" : " (not connected)"), systemImage: device.symbol)
            .tag(device.id)
    }

    /// The mapping turned around, or nil when its result can't be a source (a system action,
    /// nothing, or the left button).
    private func swapped(_ mapping: Mapping) -> Mapping? {
        var result = mapping
        switch mapping.output {
        case nil: result.input = nil
        case .key(let usage)?: result.input = .key(usage)
        case .mouseButton(let number)? where number > 0: result.input = .mouseButton(number)
        default: return nil
        }
        switch mapping.input {
        case nil: result.output = nil
        case .key(let usage)?: result.output = .key(usage)
        case .mouseButton(let number)?: result.output = .mouseButton(number)
        }
        return result
    }

    private func row(_ mapping: Mapping, on device: InputDevice) -> some View {
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
            let turned = swapped(mapping)
            Button {
                if let turned { settings.update(turned, on: device.id) }
            } label: {
                Image(systemName: "arrow.left.arrow.right")
            }
            .buttonStyle(.borderless)
            .disabled(turned == nil)
            .help("Swap From and To")
            Button {
                settings.remove(mapping, from: device.id)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Remove this mapping")
        }
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
        Group {
            if isRecording {
                // Nothing that takes keys while waiting, so the press reaches the recorder.
                VStack(spacing: 16) {
                    Image(systemName: "record.circle.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.red)
                    Text("Press a key or button on \(device.name)")
                        .font(.headline)
                        .multilineTextAlignment(.center)
                    Button("Cancel") {
                        remap.cancelRecording()
                        isRecording = false
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 0) {
                    Button {
                        isRecording = true
                        remap.record(on: device.id) { input in
                            isRecording = false
                            choose(input)
                        }
                    } label: {
                        Label("Record from \(device.name)", systemImage: "record.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .controlSize(.large)
                    .disabled(!device.isConnected)
                    .padding([.horizontal, .top], 12)

                    ChoiceList(sections: Choices.inputs(for: device)) { input in
                        choose(input)
                    }
                }
            }
        }
        .frame(width: 340, height: 480)
        .onDisappear {
            if isRecording { remap.cancelRecording() }
        }
    }
}
