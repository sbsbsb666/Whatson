import SwiftUI
import AppKit

@main
@MainActor
struct WhatsOnApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var settings: SettingsStore
    @StateObject private var model: AppModel
    @StateObject private var updater: Updater

    init() {
        let settings = SettingsStore()
        _settings = StateObject(wrappedValue: settings)
        _model = StateObject(wrappedValue: AppModel(settings: settings))
        _updater = StateObject(wrappedValue: Updater(settings: settings))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .environmentObject(settings)
                .environmentObject(updater)
                .frame(minWidth: 880, minHeight: 560)
                .task {
                    model.start()
                    updater.startAutomaticChecks()
                }
        }
        .defaultSize(width: 1220, height: 820)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { Task { await updater.check(userInitiated: true) } }
            }
            CommandGroup(after: .toolbar) {
                Button("Refresh") { model.refreshAll() }
                    .keyboardShortcut("r", modifiers: .command)
                Divider()
            }
        }

        Settings {
            SettingsView()
                .environmentObject(settings)
                .environmentObject(model)
                .environmentObject(updater)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
