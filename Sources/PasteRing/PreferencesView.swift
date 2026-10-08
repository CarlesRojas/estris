import SwiftUI

struct PreferencesView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var history: ClipboardHistory

    var body: some View {
        TabView {
            GeneralPreferences(settings: settings)
                .tabItem { Label("General", systemImage: "gearshape") }
            HistoryPreferences(history: history)
                .tabItem { Label("History", systemImage: "clock") }
        }
        .frame(width: 480, height: 440)
    }
}

private struct GeneralPreferences: View {
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
        .onAppear { openAtLogin = LoginItem.isEnabled }
    }

    private var maxItems: Binding<Int> {
        Binding(
            get: { settings.maxItems },
            set: { settings.maxItems = min(max($0, AppSettings.maxItemsRange.lowerBound), AppSettings.maxItemsRange.upperBound) }
        )
    }
}

private struct HistoryPreferences: View {
    @ObservedObject var history: ClipboardHistory
    @State private var confirmingClear = false

    private let mutedRed = Color.red.opacity(0.7)

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
            }
        }
        .confirmationDialog("Delete all clipboard entries?", isPresented: $confirmingClear) {
            Button("Clear All", role: .destructive) { history.clear() }
        }
    }
}
