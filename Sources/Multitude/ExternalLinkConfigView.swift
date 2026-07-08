import SwiftUI

// MARK: - External Link Config

struct ExternalLinkConfigView: View {
    @ObservedObject var model: MultitudeModel
    @Environment(\.dismiss) private var dismiss

    @State private var showingAddRule = false
    @State private var editingRule: ExternalLinkRule?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 6) {
                Text("External Link Rules")
                    .font(.title2.weight(.semibold))
                Text("Every link you click prompts you to open it in your default browser. Domains saved as 'Always open externally' skip the prompt and open straight away.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding([.top, .horizontal], 20)
            .padding(.bottom, 12)

            // Browser picker
            browserPickerSection

            if model.externalLinkRules.isEmpty {
                emptyState
            } else {
                rulesList
            }

            // Suggestions
            suggestionsSection

            Divider()

            // Footer
            HStack {
                Text("Only link clicks are intercepted. Form submissions, JavaScript redirects and authentication flows are never affected.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(20)
        }
        .frame(width: 480, height: 520)
        .sheet(isPresented: $showingAddRule) {
            AddExternalLinkRuleView(model: model)
        }
        .sheet(item: $editingRule) { rule in
            EditExternalLinkRuleView(model: model, rule: rule)
        }
    }

    // MARK: - Browser Picker

    private var browserPickerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
                .padding(.horizontal, 0)

            HStack(spacing: 8) {
                Text("Open links in:")
                    .font(.subheadline.weight(.medium))

                Picker("Browser", selection: $model.selectedBrowserBundleID) {
                    Text("System Default").tag(nil as String?)
                    ForEach(model.installedBrowsers) { browser in
                        Text(browser.displayName).tag(browser.id as String?)
                    }
                }
                .labelsHidden()
                .fixedSize()

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 6)

            Text("When a rule has its own browser set, that browser is used instead of this global preference.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "arrow.up.right.square")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No external link rules")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("You will be prompted for every link you click.\nAdd a domain here to always open it without asking.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }

    // MARK: - Rules List

    private var rulesList: some View {
        List {
            ForEach(model.externalLinkRules) { rule in
                RuleRowView(rule: rule, model: model, onEdit: { editingRule = rule })
            }
            .onDelete { indexSet in
                for idx in indexSet {
                    let rule = model.externalLinkRules[idx]
                    model.removeExternalLinkRule(rule.id)
                }
            }
        }
        .listStyle(.inset)
        .frame(minHeight: 180)
        .overlay(alignment: .bottomTrailing) {
            addButton
                .padding(.trailing, 8)
                .padding(.bottom, 8)
        }
    }

    private var addButton: some View {
        Button {
            showingAddRule = true
        } label: {
            Label("Add", systemImage: "plus")
                .font(.subheadline.weight(.medium))
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
    }

    // MARK: - Suggestions

    private var suggestionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
                .padding(.horizontal, 0)

            Text("Suggestions")
                .font(.headline)
                .padding(.horizontal, 20)

            Text("Tap a suggestion to add it as an external link rule.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)

            HStack(spacing: 8) {
                ForEach(MultitudeModel.defaultExternalLinkSuggestions, id: \.domain) { suggestion in
                    let alreadyAdded = model.externalLinkRules.contains(where: { $0.domain == suggestion.domain })
                    Button {
                        if !alreadyAdded {
                            model.addExternalLinkRule(domain: suggestion.domain, action: .alwaysOpen)
                        }
                    } label: {
                        Text(suggestion.domain)
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(alreadyAdded)
                    .help(alreadyAdded ? "Already added" : "Add \(suggestion.domain)")
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
        }
    }
}

// MARK: - Rule Row

private struct RuleRowView: View {
    let rule: ExternalLinkRule
    let model: MultitudeModel
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.up.right.square")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 18)

            Text(rule.domain)
                .font(.body.weight(.medium))
                .lineLimit(1)

            Spacer()

            Text(rule.action.label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(Color(.separatorColor).opacity(0.15))
                )

            // Browser badge
            if let browserID = rule.browserBundleID,
               let browser = model.installedBrowsers.first(where: { $0.id == browserID }) {
                Text(browser.displayName)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .stroke(Color(.separatorColor).opacity(0.3), lineWidth: 0.5)
                    )
            }

            Menu {
                Button("Edit…") { onEdit() }
                Button("Delete", role: .destructive) {
                    model.removeExternalLinkRule(rule.id)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Rule options")
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Browser Picker Helper

/// Shared browser picker used in both the Add and Edit rule sheets.
private struct BrowserPicker: View {
    @Binding var selectedBrowserBundleID: String?
    let installedBrowsers: [InstalledBrowser]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Open with").font(.caption).foregroundColor(.secondary)
            Picker("Open with", selection: $selectedBrowserBundleID) {
                Text("System Default").tag(nil as String?)
                ForEach(installedBrowsers) { browser in
                    Text(browser.displayName).tag(browser.id as String?)
                }
            }
            .labelsHidden()
        }
    }
}

// MARK: - Add Rule Sheet

private struct AddExternalLinkRuleView: View {
    @ObservedObject var model: MultitudeModel
    @Environment(\.dismiss) private var dismiss

    @State private var domain = ""
    @State private var action: LinkAction = .alwaysOpen
    @State private var selectedBrowserBundleID: String? = nil
    @State private var validationError: String?

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.up.right.square")
                .font(.largeTitle)
                .foregroundColor(.accentColor)

            Text("Add External Link Rule")
                .font(.title2.bold())

            Text("Links to this domain will open without prompting, using the chosen browser.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 4) {
                Text("Domain").font(.caption).foregroundColor(.secondary)
                TextField("e.g. zoom.us", text: $domain)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: domain) { _, _ in validationError = nil }
            }

            if let error = validationError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Action").font(.caption).foregroundColor(.secondary)
                Picker("Action", selection: $action) {
                    ForEach(LinkAction.allCases, id: \.self) { act in
                        Text(act.label).tag(act)
                    }
                }
                .pickerStyle(.radioGroup)
            }

            BrowserPicker(selectedBrowserBundleID: $selectedBrowserBundleID, installedBrowsers: model.installedBrowsers)

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape)
                Spacer()
                Button("Add Rule") {
                    let trimmed = domain.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else {
                        validationError = "Domain cannot be empty."
                        return
                    }
                    guard !trimmed.contains(" ") else {
                        validationError = "Domain cannot contain spaces."
                        return
                    }
                    guard trimmed.contains(".") else {
                        validationError = "Enter a valid domain like 'zoom.us'."
                        return
                    }
                    guard !model.externalLinkRules.contains(where: { $0.domain == trimmed.lowercased() }) else {
                        validationError = "A rule for '\(trimmed)' already exists."
                        return
                    }
                    model.addExternalLinkRule(domain: trimmed, action: action, browserBundleID: selectedBrowserBundleID)
                    dismiss()
                }
                .keyboardShortcut(.return)
                .disabled(domain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .frame(width: 360)
    }
}

// MARK: - Edit Rule Sheet

private struct EditExternalLinkRuleView: View {
    @ObservedObject var model: MultitudeModel
    @Environment(\.dismiss) private var dismiss
    let rule: ExternalLinkRule

    @State private var domain: String
    @State private var action: LinkAction
    @State private var selectedBrowserBundleID: String?
    @State private var validationError: String?

    init(model: MultitudeModel, rule: ExternalLinkRule) {
        self.model = model
        self.rule = rule
        _domain = State(initialValue: rule.domain)
        _action = State(initialValue: rule.action)
        _selectedBrowserBundleID = State(initialValue: rule.browserBundleID)
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.up.right.square")
                .font(.largeTitle)
                .foregroundColor(.accentColor)

            Text("Edit External Link Rule")
                .font(.title2.bold())

            VStack(alignment: .leading, spacing: 4) {
                Text("Domain").font(.caption).foregroundColor(.secondary)
                TextField("e.g. zoom.us", text: $domain)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: domain) { _, _ in validationError = nil }
            }

            if let error = validationError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Action").font(.caption).foregroundColor(.secondary)
                Picker("Action", selection: $action) {
                    ForEach(LinkAction.allCases, id: \.self) { act in
                        Text(act.label).tag(act)
                    }
                }
                .pickerStyle(.radioGroup)
            }

            BrowserPicker(selectedBrowserBundleID: $selectedBrowserBundleID, installedBrowsers: model.installedBrowsers)

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape)
                Button("Delete", role: .destructive) {
                    model.removeExternalLinkRule(rule.id)
                    dismiss()
                }
                Spacer()
                Button("Save") {
                    let trimmed = domain.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else {
                        validationError = "Domain cannot be empty."
                        return
                    }
                    guard !trimmed.contains(" ") else {
                        validationError = "Domain cannot contain spaces."
                        return
                    }
                    guard trimmed.contains(".") else {
                        validationError = "Enter a valid domain like 'zoom.us'."
                        return
                    }
                    // Allow saving with the same domain (the rule is the same), but
                    // flag a conflict if another rule already uses this domain.
                    let otherRuleWithSameDomain = model.externalLinkRules.first {
                        $0.domain == trimmed.lowercased() && $0.id != rule.id
                    }
                    guard otherRuleWithSameDomain == nil else {
                        validationError = "Another rule for '\(trimmed)' already exists."
                        return
                    }
                    model.updateExternalLinkRule(rule.id, domain: trimmed, action: action, browserBundleID: selectedBrowserBundleID)
                    dismiss()
                }
                .keyboardShortcut(.return)
                .disabled(domain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .frame(width: 360)
    }
}
