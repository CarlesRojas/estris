import SwiftUI

struct GeneralPreferences: View {
    @ObservedObject var settings: AppSettings
    @State private var openAtLogin = LoginItem.isEnabled

    var body: some View {
        Form {
            Picker("Style", selection: $settings.style) {
                ForEach(OverlayStyle.allCases) { style in
                    Text(style.title).tag(style)
                }
            }
            .pickerStyle(.radioGroup)

            Picker("Glass", selection: $settings.glass) {
                ForEach(GlassStyle.allCases) { glass in
                    Text(glass.title).tag(glass)
                }
            }
            .pickerStyle(.segmented)

            if settings.style == .ring {
                LabeledContent("Ring shows") {
                    HStack {
                        Stepper("Ring shows", value: clamped(\.ringSize, to: AppSettings.ringSizeRange), in: AppSettings.ringSizeRange)
                            .labelsHidden()
                        Text("\(settings.ringSize) most recent entries")
                    }
                }
            }

            LabeledContent("History size") {
                HStack {
                    TextField("History size", value: maxItems, format: .number)
                        .labelsHidden()
                        .multilineTextAlignment(.trailing)
                        .frame(width: 60)
                    Stepper("History size", value: maxItems, in: AppSettings.maxItemsRange, step: 5)
                        .labelsHidden()
                    Text("entries")
                }
            }

            Toggle("Open at login", isOn: Binding(
                get: { openAtLogin },
                set: {
                    LoginItem.setEnabled($0)
                    openAtLogin = LoginItem.isEnabled
                }
            ))
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 400)
        .onAppear { openAtLogin = LoginItem.isEnabled }
    }

    private var maxItems: Binding<Int> {
        clamped(\.maxItems, to: AppSettings.maxItemsRange)
    }

    private func clamped(_ keyPath: ReferenceWritableKeyPath<AppSettings, Int>, to range: ClosedRange<Int>) -> Binding<Int> {
        Binding(
            get: { settings[keyPath: keyPath] },
            set: { settings[keyPath: keyPath] = min(max($0, range.lowerBound), range.upperBound) }
        )
    }
}

struct HistoryPreferences: View {
    @ObservedObject var history: ClipboardHistory
    @State private var confirmingClear = false

    private let mutedRed = Color.red.opacity(0.88)

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(history.items.count == 1 ? "1 entry" : "\(history.items.count) entries")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Clear All", role: .destructive) {
                    confirmingClear = true
                }
                .disabled(history.items.isEmpty)
            }
            .padding(12)

            Divider()

            if history.items.isEmpty {
                Text("No clipboard entries yet")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(history.items) { item in
                        HStack(alignment: .top, spacing: 12) {
                            AppIconView(bundleID: item.sourceBundleID, size: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.text.singleLine)
                                    .lineLimit(2)
                                    .truncationMode(.tail)
                                Text(item.date, format: .relative(presentation: .named))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button {
                                history.remove(item)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(mutedRed)
                            .help("Delete this entry")
                        }
                        .padding(.vertical, 2)
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }
        }
        .frame(width: 460, height: 440)
        .confirmationDialog("Delete all clipboard entries?", isPresented: $confirmingClear) {
            Button("Clear All", role: .destructive) { history.clear() }
        }
    }
}
