import SwiftUI

@main
struct CodexLimitsApp: App {
    @StateObject private var model: AppModel

    init() {
        let model = AppModel()
        _model = StateObject(wrappedValue: model)
        model.startMonitoring()
    }

    var body: some Scene {
        MenuBarExtra {
            MenuPanelView()
                .environmentObject(model)
        } label: {
            MenuBarStatusIcon(remaining: menuBarRemaining)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(model)
        }
    }

    private var menuBarRemaining: Int? {
        let remainingValues = model.dashboard?.successfulAccounts.flatMap { account in
            account.limits?.windows.map(\.remainingPercent) ?? []
        } ?? []
        return remainingValues.min()
    }
}

private struct MenuBarStatusIcon: View {
    let remaining: Int?

    var body: some View {
        Image(systemName: "terminal.fill")
            .symbolRenderingMode(.monochrome)
            .imageScale(.medium)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        guard let remaining else { return "Codex Limits" }
        return "Codex Limits, lowest account has \(remaining) percent remaining"
    }
}
