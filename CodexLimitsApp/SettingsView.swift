import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            Section("Codex CLI") {
                TextField("Executable path", text: $model.codexPath)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Text("Uses codex app-server locally and reuses your existing Codex sign-in.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Find Automatically") { model.findCodexAutomatically() }
                }
            }

            Section("Accounts") {
                ForEach($model.profiles) { $profile in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        TextField("Account name", text: $profile.name)
                            .frame(width: 120)

                        if profile.id == CodexAccountProfile.defaultID {
                            Text("~/.codex (CLI default)")
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            TextField(
                                "CODEX_HOME folder",
                                text: Binding(
                                    get: { profile.codexHome ?? "" },
                                    set: { profile.codexHome = $0 }
                                )
                            )
                            .textFieldStyle(.roundedBorder)
                        }

                        if profile.id != CodexAccountProfile.defaultID {
                            Button(role: .destructive) {
                                model.removeProfile(id: profile.id)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .help("Remove account from this dashboard")
                        }
                    }
                }

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Each account needs its own existing CODEX_HOME folder and login.")
                        Text("mkdir -p ~/.codex-work && CODEX_HOME=~/.codex-work codex login")
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    Spacer()

                    Button {
                        chooseAccountFolder()
                    } label: {
                        Label("Add Account Folder…", systemImage: "plus")
                    }
                }
            }

            Section("Updates") {
                Picker("Refresh every", selection: $model.refreshIntervalMinutes) {
                    Text("1 minute").tag(1)
                    Text("5 minutes").tag(5)
                    Text("15 minutes").tag(15)
                    Text("30 minutes").tag(30)
                }
                Toggle(
                    "Launch at login",
                    isOn: Binding(
                        get: { model.launchAtLoginEnabled },
                        set: { model.setLaunchAtLogin($0) }
                    )
                )
            }

            Section {
                HStack {
                    Text("Widget data")
                    Spacer()
                    if let fetchedAt = model.dashboard?.updatedAt {
                        Text(fetchedAt, style: .relative)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Not fetched")
                            .foregroundStyle(.secondary)
                    }
                    Button("Refresh Now") { Task { await model.refresh() } }
                        .disabled(model.isRefreshing)
                    if model.isRefreshing {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel("Refreshing Codex accounts")
                    }
                }

                if let error = model.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.caption)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 680, height: 500)
        .font(CodexType.body)
        .tint(CodexTheme.primary)
        .background(SettingsWindowConfigurator())
    }

    private func chooseAccountFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose a Codex account folder"
        panel.message = "Select an existing CODEX_HOME directory that has its own Codex login."
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true

        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.addProfile(codexHome: url)
    }
}

private struct SettingsWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> SettingsWindowConfigurationView {
        SettingsWindowConfigurationView(frame: .zero)
    }

    func updateNSView(_ nsView: SettingsWindowConfigurationView, context: Context) {}
}

private final class SettingsWindowConfigurationView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        guard let window else { return }
        window.collectionBehavior.insert(.moveToActiveSpace)
        window.collectionBehavior.insert(.fullScreenAuxiliary)
        NSApplication.shared.activate()
        window.makeKeyAndOrderFront(nil)
    }
}
