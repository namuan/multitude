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
            // ── Rooms menu with dynamic ⌘1-⌘9 shortcuts ──
            CommandMenu("Rooms") {
                ForEach(Array(model.accounts.prefix(9).enumerated()), id: \.element.id) { i, account in
                    Button {
                        model.switchTo(account.id)
                    } label: {
                        HStack {
                            Text(account.displayName)
                            if model.unreadBadges[account.id] ?? 0 > 0 {
                                Text("(\(model.unreadBadges[account.id] ?? 0))")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: [.command])
                }

                Divider()

                Button("Add Room…") {
                    model.showingAddAccount = true
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])

                Button("Reset Active Room") {
                    if let id = model.activeAccountId {
                        model.resetAccount(id)
                    }
                }
                .keyboardShortcut("r", modifiers: [.command, .option, .shift])
                .disabled(model.activeAccountId == nil)

                Button("Delete Active Room") {
                    if let id = model.activeAccountId {
                        model.removeAccount(id)
                    }
                }
                .keyboardShortcut(.delete, modifiers: [.command, .shift])
                .disabled(model.activeAccountId == nil)
            }

            // ── Go menu ──
            CommandMenu("Go") {
                Button("Gmail") { model.loadService(.gmail) }
                    .keyboardShortcut("1", modifiers: [.command, .shift])
                Button("Calendar") { model.loadService(.calendar) }
                    .keyboardShortcut("2", modifiers: [.command, .shift])
                Button("Drive") { model.loadService(.drive) }
                    .keyboardShortcut("3", modifiers: [.command, .shift])
                Button("Meet") { model.loadService(.meet) }
                    .keyboardShortcut("4", modifiers: [.command, .shift])
                Divider()
                Button("Reload") { model.reload() }
                    .keyboardShortcut("r", modifiers: [.command])
                Button("Back") { model.goBack() }
                    .keyboardShortcut("[", modifiers: [.command])
                Button("Forward") { model.goForward() }
                    .keyboardShortcut("]", modifiers: [.command])
            }

            // ── View menu ──
            CommandMenu("View") {
                Button("Toggle Debug Panel") {
                    model.showingDebugPanel.toggle()
                }
                .keyboardShortcut("d", modifiers: [.command, .option])
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
