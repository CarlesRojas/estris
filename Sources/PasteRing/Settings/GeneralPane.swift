import AppKit
import SwiftUI

/// Settings shared by every utility.
struct GeneralPane: View {
    private static let accessibilitySettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!

    @ObservedObject var general: GeneralSettings
    @State private var openAtLogin = LoginItem.isEnabled
    @State private var versionTaps: [Date] = []
    @State private var accessibilityGranted = Paster.isTrusted(prompt: false)

    var body: some View {
        Form {
            // Missing permission: a warning at the very top. Once granted, it is a plain row
            // further down.
            if !accessibilityGranted {
                Section {
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.title)
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("PasteRing needs Accessibility access")
                                .font(.headline)
                            Text("macOS only lets apps with this permission type into other apps. PasteRing uses it to paste the entry you pick straight into the app you are working in, Auto Quit uses it to see each app's windows, and Middle Click uses it to click the middle button. Without it, entries are only copied to the clipboard, and Auto Quit and the middle click do nothing.")
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

            Section("Startup") {
                Toggle("Open at login", isOn: Binding(
                    get: { openAtLogin },
                    set: {
                        LoginItem.setEnabled($0)
                        openAtLogin = LoginItem.isEnabled
                    }
                ))
            }

            if accessibilityGranted {
                Section("Permissions") {
                    LabeledContent("Accessibility") {
                        Label("Allowed", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
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
                            .contentShape(Rectangle())
                            .onTapGesture(perform: versionTapped)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .settingsPage()
        .onAppear(perform: refreshStatus)
        // Picks up changes made in System Settings when returning to this window.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshStatus()
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
        let version = info?["CFBundleShortVersionString"] as? String ?? "development build"
        let build = info?["CFBundleVersion"] as? String
        return build.map { "Version \(version) (\($0))" } ?? "Version \(version)"
    }

    private func refreshStatus() {
        openAtLogin = LoginItem.isEnabled
        accessibilityGranted = Paster.isTrusted(prompt: false)
    }
}
