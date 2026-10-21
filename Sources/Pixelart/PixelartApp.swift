import SwiftUI
import AppKit

@main
struct JeXelartApp: App {
    @State private var model = AppModel()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup("JeXelart") {
            ContentView(model: model)
                .frame(minWidth: 980, minHeight: 700)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
                .onOpenURL { model.load($0) }
        }
        .defaultSize(width: 1200, height: 820)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Abrir imagen…", action: model.openImage).keyboardShortcut("o")
                Button("Exportar…", action: model.export).keyboardShortcut("s", modifiers: [.command, .shift]).disabled(!model.canExport)
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
