import AppKit
import SwiftUI

/// One entry in the settings sidebar: the app-wide General pane, then one per utility.
enum SettingsPane: String, CaseIterable, Identifiable {
    case general
    case clipboard

    var id: Self { self }

    var title: String {
        switch self {
        case .general: "General"
        case .clipboard: "Clipboard Manager"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .clipboard: "doc.on.clipboard"
        }
    }

    /// What the sidebar search matches besides the title.
    var keywords: [String] {
        switch self {
        case .general:
            ["login", "startup", "language", "accessibility", "permission", "date", "time", "format", "version", "about"]
        case .clipboard:
            ["history", "paste", "style", "default", "grid", "carousel", "stack", "ring", "tint", "shadow", "dim", "surface", "entries"]
        }
    }

    func matches(_ search: String) -> Bool {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return true }
        return title.lowercased().contains(query) || keywords.contains { $0.contains(query) }
    }
}

struct SettingsView: View {
    @ObservedObject var general: GeneralSettings
    @ObservedObject var clipboard: ClipboardSettings
    @ObservedObject var appearance: AppearanceSettings
    @ObservedObject var history: ClipboardHistory
    @State private var selection: SettingsPane? = .general
    @State private var search = ""

    private var panes: [SettingsPane] {
        SettingsPane.allCases.filter { $0.matches(search) }
    }

    var body: some View {
        NavigationSplitView {
            List(panes, selection: $selection) { pane in
                Label(pane.title, systemImage: pane.symbol)
            }
            .searchable(text: $search, placement: .sidebar, prompt: "Search")
            .navigationSplitViewColumnWidth(min: 180, ideal: 210)
        } detail: {
            switch selection ?? .general {
            case .general:
                GeneralPane(general: general)
            case .clipboard:
                ClipboardManagerPane(clipboard: clipboard, appearance: appearance, history: history)
            }
        }
        .environment(\.dateTimeFormat, general.dateTimeFormat)
        .frame(minWidth: 820, minHeight: 640)
        // Jump to the first match when the search hides the open pane.
        .onChange(of: search) { _ in
            if let selection, !panes.contains(selection), let first = panes.first {
                self.selection = first
            }
        }
    }
}

// MARK: - General

/// Settings shared by every utility.
struct GeneralPane: View {
    private static let accessibilitySettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!

    @ObservedObject var general: GeneralSettings
    @State private var openAtLogin = LoginItem.isEnabled
    @State private var accessibilityGranted = Paster.isTrusted(prompt: false)

    var body: some View {
        Form {
            if accessibilityGranted {
                Section("Permissions") {
                    LabeledContent("Accessibility") {
                        Label("Allowed", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
            } else {
                Section {
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.title)
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("PasteRing needs Accessibility access")
                                .font(.headline)
                            Text("macOS only lets apps with this permission type into other apps. PasteRing uses it to paste the entry you pick straight into the app you are working in. Without it, entries are only copied to the clipboard.")
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Button("Open Accessibility Settings") {
                                NSWorkspace.shared.open(Self.accessibilitySettingsURL)
                            }
                            .controlSize(.large)
                        }
                    }
                    .padding(.vertical, 6)
                }
            }

            Section("Startup") {
                Toggle("Open at login", isOn: Binding(
                    get: { openAtLogin },
                    set: {
                        LoginItem.setEnabled($0)
                        openAtLogin = LoginItem.isEnabled
                    }
                ))
            }

            Section("Language & Region") {
                Picker("Language", selection: $general.language) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.title).tag(language)
                    }
                }
                Picker("Date format", selection: $general.dateStyle) {
                    ForEach(DateStyle.allCases) { style in
                        Text(DateTimeFormat(language: general.language, dateStyle: style).dateString(from: .now)).tag(style)
                    }
                }
                Picker("Time format", selection: $general.timeStyle) {
                    ForEach(TimeStyle.allCases) { style in
                        let sample = DateTimeFormat(language: general.language, timeStyle: style).timeString(from: .now)
                        Text("\(style.title) (\(sample))").tag(style)
                    }
                }
            }

            Section("About") {
                HStack(spacing: 14) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 56, height: 56)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("PasteRing")
                            .font(.title3.weight(.semibold))
                        Text(Self.versionText)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
                Text("A set of small utilities for macOS. It starts with a clipboard manager: hold ⌘⇧ and press V to pick from everything you have copied.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: refreshStatus)
        // Picks up changes made in System Settings when returning to this window.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshStatus()
        }
    }

    private static var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "development build"
        let build = info?["CFBundleVersion"] as? String
        return build.map { "Version \(version) (\($0))" } ?? "Version \(version)"
    }

    private func refreshStatus() {
        openAtLogin = LoginItem.isEnabled
        accessibilityGranted = Paster.isTrusted(prompt: false)
    }
}

// MARK: - Clipboard Manager

struct ClipboardManagerPane: View {
    private enum Tab: Hashable {
        case settings
        case history
    }

    @ObservedObject var clipboard: ClipboardSettings
    @ObservedObject var appearance: AppearanceSettings
    @ObservedObject var history: ClipboardHistory
    @State private var tab = Tab.settings

    var body: some View {
        VStack(spacing: 0) {
            Picker("View", selection: $tab) {
                Text("Settings").tag(Tab.settings)
                Text("History").tag(Tab.history)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .padding(.vertical, 12)

            switch tab {
            case .settings:
                ClipboardSettingsForm(settings: clipboard, appearance: appearance, history: history)
            case .history:
                HistoryPreferences(history: history)
            }
        }
    }
}
