import SwiftUI

// MARK: - ContentView

struct ContentView: View {
    @ObservedObject var model: MultitudeModel
    @State private var showDebug = false

    var body: some View {
        HSplitView {
            // ── Sidebar ──
            sidebar
                .frame(minWidth: 200, idealWidth: 220, maxWidth: 300)

            // ── Main content ──
            VStack(spacing: 0) {
                // Service pill tabs
                ServicePillBar(model: model)

                Divider()

                // Web view area
                WebViewContainer(webView: model.activeWebView)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Debug panel
                if model.showingDebugPanel {
                    debugPanel
                        .frame(height: 200)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .sheet(isPresented: $model.showingAddAccount) {
            AddAccountView { name, email in
                model.addAccount(displayName: name, email: email)
            }
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Rooms")
                    .font(.headline)
                    .foregroundColor(.secondary)
                Spacer()
                Button { model.showingAddAccount = true } label: {
                    Image(systemName: "plus.circle")
                }
                .buttonStyle(.plain)
                .help("Add Room (⌘⇧N)")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            // Room list
            List {
                ForEach(Array(model.accounts.enumerated()), id: \.element.id) { index, account in
                    RoomRowView(
                        account: account,
                        index: index,
                        isActive: model.activeAccountId == account.id,
                        unreadCount: model.unreadBadges[account.id] ?? 0,
                        onSelect: { model.switchTo(account.id) },
                        onRename: { name in model.renameAccount(account.id, to: name) },
                        onReset: { model.resetAccount(account.id) },
                        onRemove: { model.removeAccount(account.id) }
                    )
                }
                .onMove { source, dest in
                    model.reorderAccounts(from: source, to: dest)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)

            Spacer()

            // Bottom bar
            HStack {
                Text("Multitude")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .background(Color(.controlBackgroundColor))
    }

    // MARK: - Debug panel

    private var debugPanel: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("Debug")
                    .font(.caption.bold())
                Spacer()
                Button("Clear") { model.debugMessages.removeAll() }
                    .buttonStyle(.plain)
                    .font(.caption)
            }
            .padding(.horizontal, 8)
            .padding(.top, 4)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(model.debugMessages.enumerated()), id: \.offset) { i, msg in
                            Text(msg)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(.secondary)
                                .textSelection(.enabled)
                                .id(i)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                }
                .background(Color(.textBackgroundColor))
                .onChange(of: model.debugMessages.count) { _, _ in
                    withAnimation(.none) {
                        proxy.scrollTo(model.debugMessages.count - 1, anchor: .bottom)
                    }
                }
            }
        }
    }
}

// MARK: - Room Row

struct RoomRowView: View {
    let account: MultitudeAccount
    let index: Int
    let isActive: Bool
    let unreadCount: Int
    let onSelect: () -> Void
    let onRename: (String) -> Void
    let onReset: () -> Void
    let onRemove: () -> Void

    @State private var showingRename = false
    @State private var renameText = ""

    private var initial: String {
        String(account.displayName.prefix(1)).uppercased()
    }

    private var shortcut: String {
        index < 9 ? "⌘\(index + 1)" : ""
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                // Avatar circle
                ZStack {
                    Circle()
                        .fill(isActive ? Color.accentColor : Color(.separatorColor))
                        .frame(width: 28, height: 28)
                    Text(initial)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white)
                }

                // Name + shortcut
                VStack(alignment: .leading, spacing: 1) {
                    Text(account.displayName)
                        .font(.system(size: 13, weight: isActive ? .semibold : .regular))
                        .foregroundColor(isActive ? .accentColor : .primary)
                        .lineLimit(1)
                    if !account.email.isEmpty {
                        Text(account.email)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                // Badge
                if unreadCount > 0 {
                    Text("\(unreadCount)")
                        .font(.caption2.bold())
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.red)
                        .clipShape(Capsule())
                }

                // Shortcut hint
                if !shortcut.isEmpty {
                    Text(shortcut)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isActive ? Color.accentColor.opacity(0.08) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Rename…") {
                renameText = account.displayName
                showingRename = true
            }
            Button("Reset Room", role: .destructive, action: onReset)
            Divider()
            Button("Delete Room", role: .destructive, action: onRemove)
        }
        .sheet(isPresented: $showingRename) {
            renameSheet
        }
    }

    private var renameSheet: some View {
        VStack(spacing: 12) {
            Text("Rename Room")
                .font(.headline)
            TextField("Room name", text: $renameText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 250)
            HStack {
                Button("Cancel") { showingRename = false }
                    .keyboardShortcut(.escape)
                Button("Save") {
                    let trimmed = renameText.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty {
                        onRename(trimmed)
                    }
                    showingRename = false
                }
                .keyboardShortcut(.return)
            }
        }
        .padding()
        .frame(width: 300)
    }
}

// MARK: - Add Account Sheet

struct AddAccountView: View {
    let onAdd: (String, String) -> Void

    @State private var displayName = ""
    @State private var email = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.badge.plus")
                .font(.largeTitle)
                .foregroundColor(.accentColor)

            Text("New Room")
                .font(.title2.bold())

            Text("Each room has its own isolated browser session.\nSign into a different Google account in each.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 4) {
                Text("Display Name").font(.caption).foregroundColor(.secondary)
                TextField("e.g. Work, Personal, Client X", text: $displayName)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Email (optional, for display only)").font(.caption).foregroundColor(.secondary)
                TextField("e.g. user@example.com", text: $email)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape)
                Button("Add Room") {
                    let name = displayName.trimmingCharacters(in: .whitespaces)
                    guard !name.isEmpty else { return }
                    onAdd(name, email.trimmingCharacters(in: .whitespaces))
                    dismiss()
                }
                .keyboardShortcut(.return)
                .disabled(displayName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.top, 8)
        }
        .padding()
        .frame(width: 340)
    }
}

// MARK: - Preview

#Preview {
    ContentView(model: MultitudeModel())
}
