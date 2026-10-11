import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Settings shared by every utility.
struct GeneralPane: View {
    private static let accessibilitySettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!

    @ObservedObject var general: GeneralSettings
    @State private var openAtLogin = LoginItem.isEnabled
    @State private var versionTaps: [Date] = []
    @State private var accessibilityGranted = Paster.isTrusted(prompt: false)
    @State private var asksToRelaunch = false
    /// Settings read from a file, waiting for the import to be confirmed.
    @State private var pendingImport: Data?
    @State private var transferError: TransferFailure?

    private struct TransferFailure {
        let title: String
        let message: String
    }

    var body: some View {
        Form {
            Section("Language & Region") {
                Picker("Language", selection: $general.language) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(verbatim: language.title).tag(language)
                    }
                }
                .resetMenu($general.language, to: GeneralSettings.Default.language)
                Picker("Date format", selection: $general.dateStyle) {
                    ForEach(DateStyle.allCases) { style in
                        Text(DateTimeFormat(language: general.language, dateStyle: style).dateString(from: .now)).tag(style)
                    }
                }
                .resetMenu($general.dateStyle, to: GeneralSettings.Default.dateStyle)
                Picker("Time format", selection: $general.timeStyle) {
                    ForEach(TimeStyle.allCases) { style in
                        let sample = DateTimeFormat(language: general.language, timeStyle: style).timeString(from: .now)
                        Text(verbatim: "\(style.title) (\(sample))").tag(style)
                    }
                }
                .resetMenu($general.timeStyle, to: GeneralSettings.Default.timeStyle)
            }

            Section("Startup") {
                Toggle("Open at login", isOn: Binding(
                    get: { openAtLogin },
                    set: {
                        LoginItem.setEnabled($0)
                        openAtLogin = LoginItem.isEnabled
                    }
                ))
                // Off unless turned on.
                .resetMenu(isDefault: !openAtLogin) {
                    LoginItem.setEnabled(false)
                    openAtLogin = LoginItem.isEnabled
                }
            }

            // Asked for when a utility that needs it is turned on, not before.
            Section("Permissions") {
                LabeledContent("Accessibility") {
                    if accessibilityGranted {
                        Label("Allowed", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button("Open Accessibility Settings") {
                            NSWorkspace.shared.open(Self.accessibilitySettingsURL)
                        }
                    }
                }
            }

            Section("About") {
                HStack(spacing: 14) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 56, height: 56)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: "Estris")
                            .font(.title3.weight(.semibold))
                        Text(Self.versionText)
                            .foregroundStyle(.secondary)
                            .contentShape(Rectangle())
                            .onTapGesture(perform: versionTapped)
                    }
                }
            }

            Section {
                HStack {
                    Button("Export Settings…", action: exportSettings)
                    Button("Import Settings…", action: chooseSettingsFile)
                }
            } header: {
                Text("Export & Import")
            } footer: {
                Text("Saves every Estris setting to a file, to keep or use on another Mac. The clipboard history isn't included.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .settingsPage()
        .onAppear(perform: refreshStatus)
        // Picks up changes made in System Settings when returning to this window.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshStatus()
        }
        // A new language only applies after relaunching, so the change waits on a choice:
        // relaunch now, or keep the current language.
        .onChange(of: general.language) { language in
            asksToRelaunch = language != general.launchLanguage
        }
        .alert("Relaunch Estris to change the language?", isPresented: $asksToRelaunch) {
            Button("Relaunch") { Relaunch.now(reopeningSettings: true) }
            Button("Cancel", role: .cancel) { general.language = general.launchLanguage }
        } message: {
            Text("The new language is used once Estris opens again.")
        }
        .alert("Import these settings?", isPresented: Binding(get: { pendingImport != nil }, set: { if !$0 { pendingImport = nil } })) {
            Button("Import", action: importPendingSettings)
            Button("Cancel", role: .cancel) { pendingImport = nil }
        } message: {
            Text("They replace your current settings, and Estris opens again to apply them.")
        }
        .alert(transferError?.title ?? "", isPresented: Binding(get: { transferError != nil }, set: { if !$0 { transferError = nil } })) {
            Button("OK", role: .cancel) { transferError = nil }
        } message: {
            Text(verbatim: transferError?.message ?? "")
        }
    }

    private func exportSettings() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = SettingsTransfer.suggestedFileName
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try SettingsTransfer.exportData().write(to: url, options: .atomic)
        } catch {
            transferError = TransferFailure(title: String(localized: "Couldn't export the settings"), message: error.localizedDescription)
        }
    }

    private func chooseSettingsFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            pendingImport = try Data(contentsOf: url)
        } catch {
            transferError = TransferFailure(title: String(localized: "Couldn't import the settings"), message: error.localizedDescription)
        }
    }

    private func importPendingSettings() {
        guard let data = pendingImport else { return }
        pendingImport = nil
        do {
            try SettingsTransfer.importData(data)
            Relaunch.now(reopeningSettings: true)
        } catch {
            transferError = TransferFailure(title: String(localized: "Couldn't import the settings"), message: error.localizedDescription)
        }
    }

    /// Six clicks on the version within a few seconds unlock the Developer pane.
    private func versionTapped() {
        let now = Date()
        versionTaps = versionTaps.filter { now.timeIntervalSince($0) < 3 } + [now]
        if versionTaps.count >= 6 {
            versionTaps = []
            general.showsDeveloperSettings = true
        }
    }

    private static var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? String(localized: "development build")
        let build = info?["CFBundleVersion"] as? String
        return build.map { String(localized: "Version \(version) (\($0))") } ?? String(localized: "Version \(version)")
    }

    private func refreshStatus() {
        openAtLogin = LoginItem.isEnabled
        accessibilityGranted = Paster.isTrusted(prompt: false)
    }
}
