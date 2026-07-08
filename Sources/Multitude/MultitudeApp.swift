import SwiftUI

@main
struct MultitudeApp: App {
    @StateObject private var model = MultitudeModel()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .frame(minWidth: 840, minHeight: 500)
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentSize)
        .commands {
            // ── View menu ──
            CommandMenu("View") {
                Button("Toggle Debug Panel") {
                    model.showingDebugPanel.toggle()
                }
                .keyboardShortcut("d", modifiers: [.command, .option])

                Divider()

                Button("External Link Rules…") {
                    model.showingExternalLinkConfig = true
                }

                Divider()

                // Room-switching shortcuts (⌘1-⌘9)
                ForEach(Array(model.accounts.prefix(9).enumerated()), id: \.element.id) { i, account in
                    Button {
                        model.switchTo(account.id)
                    } label: {
                        Text(account.displayName)
                    }
                    .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: [.command])
                }
            }
        }
    }
}

// MARK: - App Delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
