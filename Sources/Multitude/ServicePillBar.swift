import SwiftUI

// MARK: - Service Toolbar

/// Toolbar row with navigation controls (left) and pill-shaped service tabs.
struct ServicePillBar: View {
    @ObservedObject var model: MultitudeModel
    @State private var showingServiceConfig = false

    var body: some View {
        HStack(spacing: 0) {
            // ── Navigation controls ──
            navButton(systemName: "chevron.left", action: model.goBack)
                .help("Back (⌘[)")
                .disabled(model.activeWebView?.canGoBack == false)

            navButton(systemName: "chevron.right", action: model.goForward)
                .help("Forward (⌘])")
                .disabled(model.activeWebView?.canGoForward == false)

            navButton(systemName: "arrow.clockwise", action: model.reload)
                .help("Reload (⌘R)")

            // Separator
            Rectangle()
                .fill(Color(.separatorColor).opacity(0.3))
                .frame(width: 1, height: 20)
                .padding(.horizontal, 8)

            // ── Service pills ──
            HStack(spacing: 6) {
                ForEach(model.enabledServices, id: \.self) { service in
                    pill(for: service)
                }
            }

            navButton(systemName: "gearshape", action: { showingServiceConfig = true })
                .help("Configure services")
                .padding(.leading, 6)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity)
        .background(
            Rectangle()
                .fill(Color(.windowBackgroundColor).opacity(0.85))
                .background(Material.ultraThin)
        )
        .sheet(isPresented: $showingServiceConfig) {
            ServiceConfigView(model: model)
        }
    }

    // MARK: - Nav Button

    private func navButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.primary)
                .frame(width: 28, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(.separatorColor).opacity(0.12))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(.separatorColor).opacity(0.2), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Pill

    private func pill(for service: GoogleService) -> some View {
        let isActive = model.currentService == service
        let unread = service == .gmail ? model.activeAccountId.map { model.unreadBadges[$0] ?? 0 } ?? 0 : 0
        let activeId = model.activeAccountId?.uuidString ?? "nil"
        let badgeCount = model.unreadBadges.count

        // Log every render of the Gmail pill with its unread state
        if service == .gmail {
            FileLogger.shared.debug("pill(for: gmail) activeId=\(activeId) unread=\(unread) badgeDictSize=\(badgeCount)")
        }

        return Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                model.loadService(service)
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: service.symbol)
                    .font(.system(size: 11, weight: .semibold))
                Text(service.title)
                    .font(.system(size: 12, weight: isActive ? .semibold : .medium))

                if unread > 0 {
                    Text("\(unread)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.red)
                        .clipShape(Capsule())
                }
            }
            .foregroundColor(isActive ? .white : .primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(isActive
                        ? Color.accentColor
                        : Color(.separatorColor).opacity(0.18)
                    )
            )
            .overlay(
                Capsule()
                    .stroke(Color(.separatorColor).opacity(isActive ? 0 : 0.25), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .help(unread > 0 ? "\(service.title) — \(unread) unread" : service.title)
    }
}

// MARK: - Service Config

struct ServiceConfigView: View {
    @ObservedObject var model: MultitudeModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Configure Services")
                    .font(.title2.weight(.semibold))
                Text("Choose which Google services appear in the toolbar. Services are shown in the order you enable them.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding([.top, .horizontal], 20)
            .padding(.bottom, 12)

            List {
                ForEach(GoogleService.allAvailable, id: \.self) { service in
                    Toggle(isOn: binding(for: service)) {
                        Label {
                            Text(service.title)
                        } icon: {
                            Image(systemName: service.symbol)
                                .foregroundStyle(.secondary)
                                .frame(width: 18)
                        }
                    }
                    .toggleStyle(.checkbox)
                    .disabled(model.enabledServices.count == 1 && model.enabledServices.contains(service))
                    .help(disableHelp(for: service))
                }
            }
            .listStyle(.inset)
            .frame(minHeight: 320)

            Divider()

            HStack {
                Text("At least one service must remain enabled.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(20)
        }
        .frame(width: 420, height: 520)
    }

    private func binding(for service: GoogleService) -> Binding<Bool> {
        Binding(
            get: { model.enabledServices.contains(service) },
            set: { model.setService(service, enabled: $0) }
        )
    }

    private func disableHelp(for service: GoogleService) -> String {
        if model.enabledServices.count == 1 && model.enabledServices.contains(service) {
            return "At least one service must remain enabled"
        }
        return service.title
    }
}

// MARK: - Preview

#Preview {
    let model = MultitudeModel()
    model.currentService = .gmail
    return ServicePillBar(model: model)
        .frame(width: 500)
        .padding()
}
