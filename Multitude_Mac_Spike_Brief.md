# Multitude for Mac — WKWebView Isolation Spike Brief

**Audience:** Junior macOS developer  
**Owner:** Product / Engineering Lead  
**Estimated duration:** 5 working days  
**Primary goal:** Prove whether the core Multitude architecture is technically viable before building the product UI.

---

## 1. Purpose

This spike is a short, focused engineering investigation. It is not the full Multitude app.

The purpose is to prove or disprove whether a native macOS app can run multiple Google accounts side by side using `WKWebView`, while keeping each account isolated from the others.

The spike should answer these questions:

- Can a Swift macOS app host multiple `WKWebView` instances?
- Can at least two different Google accounts sign in independently?
- Can each account keep separate cookies, local storage, cache, IndexedDB, and visible Google login state?
- Can both accounts stay signed in after quitting and reopening the app?
- Can one account be reset without affecting the others?
- Do Google sign-in restrictions, WebKit storage behavior, App Sandbox, camera/microphone permissions, or Google Meet create blockers?

---

## 2. Non-goals

Do not build the final product UI.

Do not build a custom Gmail client.

Do not use the Gmail, Calendar, Drive, or Meet APIs.

Do not create a backend or server.

Do not store Google passwords.

Do not attempt to bypass Google sign-in restrictions.

Do not spoof user agents.

Do not use private Apple APIs.

Do not implement production notifications, compose overlays, subscription logic, billing, analytics, or auto-update.

Do not ship this spike to real users.

---

## 3. Critical questions and pass criteria

### Question 1: Can two Google accounts sign in independently?

This is the foundation of the product.

Pass criteria:

- Account slot 1 signs into Google account A.
- Account slot 2 signs into Google account B.
- Both accounts can open Gmail at the same time.
- Account 1 shows account A's Gmail inbox.
- Account 2 shows account B's Gmail inbox.
- Switching between accounts does not cause either web view to become the other account.

### Question 2: Does account state persist after app restart?

Users should not need to sign in every time they open the app.

Pass criteria:

- Sign into two accounts.
- Quit the app completely.
- Reopen the app.
- Both accounts are still signed in.
- Each account still shows the correct Gmail inbox.

### Question 3: Can one account be reset without affecting another?

Multitude needs a local recovery path per account.

Pass criteria:

- Both accounts are signed in.
- Clear or reset Account 1.
- Account 1 becomes signed out or reset.
- Account 2 remains signed in and usable.

### Question 4: Does Google block sign-in inside `WKWebView`?

This could make the product impossible or risky.

Pass criteria:

- The developer records exactly what happens during sign-in.
- Any error message is captured.
- Any `disallowed_useragent` or embedded-browser warning is captured.
- No workaround violates Google policy or Apple platform rules.

### Question 5: Can Gmail, Calendar, Drive, and Meet load?

The product depends on the real Google web apps.

Pass criteria:

- Gmail loads.
- Calendar loads.
- Drive loads.
- Meet loads.
- Meet camera and microphone permission behavior is recorded.

### Question 6: Can this work with App Sandbox enabled?

A real Mac app should run under normal macOS security constraints.

Pass criteria:

- The spike is tested with App Sandbox enabled.
- Any behavior difference between sandboxed and non-sandboxed builds is documented.

---

## 4. Important platform facts

Use these as constraints. Do not treat them as optional details.

`WKWebView` is created from a `WKWebViewConfiguration`.

The `websiteDataStore` must be assigned on the configuration before creating the `WKWebView`.

If no `websiteDataStore` is assigned, `WKWebViewConfiguration` uses the default persistent website data store.

`WKWebsiteDataStore.nonPersistent()` creates an in-memory private data store. This is useful for isolation testing, but it may not satisfy the product requirement because data does not persist after restart.

Google documents a `disallowed_useragent` error when OAuth authorization is shown inside embedded user agents such as `WKWebView` on iOS or macOS. The spike must record exactly what happens with normal Google web-app sign-in.

`WKUIDelegate` includes media-capture permission handling. This matters for Google Meet camera and microphone testing.

Reference links are listed at the end of this document.

---

## 5. Success definition

The spike is successful only if the must-have checks pass.

It is acceptable for nice-to-have checks to fail, but failures must be documented clearly.

### Must-have outcomes

The spike must prove all of the following:

- At least two Google accounts can be active in separate web views at the same time.
- Switching between accounts does not reload the page.
- Account A and Account B show different Gmail inboxes and account identities.
- Reloading Account A does not affect Account B.
- Clearing Account A data does not sign out Account B.
- The developer provides screenshots or short recordings as evidence.
- The developer provides a pass/fail report.

### Strongly desired outcomes

These are not strictly required, but they are important:

- Both accounts remain signed in after quitting and reopening the app.
- The app works with App Sandbox enabled.
- Calendar works for both accounts.
- Drive works for both accounts.
- Meet loads for both accounts.
- Meet camera and microphone permissions are controllable and understandable.

### Hard failure conditions

Any of these results should stop the project or force an architecture pivot:

- Google sign-in is blocked in `WKWebView` and there is no compliant path to establish a web session.
- Accounts share login state and cannot be isolated.
- Only one persistent website data store can be used, causing account bleed.
- Per-account reset cannot be implemented without resetting every account.
- The implementation requires private APIs.
- The implementation requires user-agent spoofing.
- The implementation requires behavior that violates Google policy.

---

## 6. Implementation requirements

### 6.1 Project setup

Create a new macOS app in Xcode using Swift.

Use SwiftUI for the shell if that is fastest. Host `WKWebView` through `NSViewRepresentable` or `NSViewControllerRepresentable`.

AppKit-only is also acceptable.

Do not spend time optimizing for old macOS versions during the spike. Use the current development machine OS as the initial target.

Add the WebKit framework.

Create a simple UI with:

- Account 1 button
- Account 2 button
- Optional Account 3 button
- Gmail button
- Calendar button
- Drive button
- Meet button
- Main web view area
- Debug controls
- Debug output area

The UI can be ugly. The goal is to test behavior, not design.

### 6.2 Recommended spike UI

Use a simple layout.

Left side:

- Account 1
- Account 2
- Account 3, optional

Top or left service controls:

- Gmail
- Calendar
- Drive
- Meet

Main area:

- The active `WKWebView`

Debug buttons:

- Reload Active
- Clear Active Website Data
- Print Cookies
- Run Storage Probe
- Print Current URL
- Print Page Title

Debug output should show:

- Active account slot
- Account UUID
- Storage mode
- Current URL
- Page title
- Last navigation event
- Last navigation error, if any
- Cookie domains and names, but never cookie values

### 6.3 Account session object

Create a small model for each account slot. Do not over-engineer this.

```swift
struct SpikeAccount: Identifiable {
    let id: UUID
    let displayName: String
    let slotNumber: Int
    let storageMode: StorageMode
}

enum StorageMode {
    case defaultPersistent
    case nonPersistent
    case experimentalIsolatedPersistent
}
```

For the spike, start with two or three account slots.

Each account slot should own its own `WKWebView` instance.

Do not recreate the web view every time the user switches accounts. Switching should show an existing web view.

### 6.4 WebView factory

Create all web views through one factory so configuration is consistent and easy to change.

```swift
import WebKit

final class WebViewFactory {
    static func makeWebView(for account: SpikeAccount) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.javaScriptCanOpenWindowsAutomatically = true

        switch account.storageMode {
        case .defaultPersistent:
            config.websiteDataStore = .default()

        case .nonPersistent:
            config.websiteDataStore = .nonPersistent()

        case .experimentalIsolatedPersistent:
            // Implement this only if a public, stable approach is identified.
            // Do not use private APIs.
            config.websiteDataStore = .default()
        }

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.allowsBackForwardNavigationGestures = true
        return webView
    }
}
```

Important rule:

Set `config.websiteDataStore` before creating the `WKWebView`.

Do not try to change `websiteDataStore` after the web view already exists.

### 6.5 Navigation URLs

Use these initial URLs:

Gmail:

```text
https://mail.google.com/
```

Calendar:

```text
https://calendar.google.com/
```

Drive:

```text
https://drive.google.com/
```

Meet:

```text
https://meet.google.com/
```

Do not rely on `/u/0`, `/u/1`, or browser-profile-style Google account indexes.

The product should rely on isolated web sessions, not Google's multi-login URL numbering.

### 6.6 Debug logging

Log important events to both the Xcode console and the on-screen debug panel.

Log these fields:

- Account slot number
- Account UUID
- Storage mode
- URL loaded
- Navigation start
- Navigation finish
- Redirects
- Navigation failures
- Page title changes
- Web content process termination
- Media permission requests
- Cookie count
- Cookie names and domains

Do not log:

- Cookie values
- OAuth tokens
- Email contents
- Message subjects
- Personal data from Gmail
- Passwords

### 6.7 JavaScript storage probe

Add a debug button that runs JavaScript in the active web view.

The script should write and read a harmless value in `localStorage`.

This is not a complete isolation test, but it helps confirm whether each web view has a separate storage view.

Example:

```swift
let js = """
localStorage.setItem('multitude_spike_account_marker', 'ACCOUNT_SLOT_1');
localStorage.getItem('multitude_spike_account_marker');
"""

webView.evaluateJavaScript(js) { result, error in
    print("Storage probe result:", result ?? "nil", "error:", error ?? "none")
}
```

Run the probe on each account using a different value.

Expected behavior:

- Account 1 stores marker `ACCOUNT_SLOT_1`.
- Account 2 stores marker `ACCOUNT_SLOT_2`.
- Switching accounts should not cause the marker to become the other account's marker.

Do not run destructive JavaScript on Google pages.

### 6.8 Cookie inspection

Add a debug button that prints cookie names and domains.

Never print cookie values.

Example:

```swift
let cookieStore = webView.configuration.websiteDataStore.httpCookieStore

cookieStore.getAllCookies { cookies in
    for cookie in cookies {
        print("cookie name=\(cookie.name), domain=\(cookie.domain), path=\(cookie.path)")
    }
}
```

Expected behavior for truly isolated stores:

- Account 1 and Account 2 should not expose the same login session to each other.
- If both account slots use the same default persistent store, they will probably share Google login state.
- Shared login state fails the product's account-isolation requirement.

### 6.9 Clearing one account

Implement a `Clear Active Website Data` button.

The button should clear website data for the active account/session only, if that is possible.

If clearing data affects every account, document that as a failure or major limitation.

Example:

```swift
let store = webView.configuration.websiteDataStore
let dataTypes = WKWebsiteDataStore.allWebsiteDataTypes()

store.fetchDataRecords(ofTypes: dataTypes) { records in
    records.forEach { record in
        print("record displayName=\(record.displayName)")
    }

    store.removeData(ofTypes: dataTypes, for: records) {
        print("Finished clearing active store")
    }
}
```

Important:

- Print the records before clearing.
- Do not assume this is isolated until it is tested.
- After clearing Account 1, immediately verify Account 2 is still signed in.

### 6.10 Keyboard switching

Add basic keyboard shortcuts.

Required shortcuts:

- `Command-1` activates Account 1.
- `Command-2` activates Account 2.
- `Command-3` activates Account 3 if present.

Expected behavior:

- Switching should hide/show existing web views.
- Switching should not recreate web views.
- Switching should not reload pages.
- Keyboard focus should return to the active `WKWebView`.

---

## 7. Step-by-step test plan

Use two normal Google test accounts.

Do not use a production account with sensitive data unless explicitly approved.

Capture screenshots or short screen recordings for each important test.

### Test 1: Baseline single-account Gmail load

1. Launch the app.
2. Open Account 1.
3. Load Gmail.
4. Sign in with test Google account A.
5. Confirm Gmail inbox is visible.
6. Capture a screenshot.
7. Record whether there were warnings, redirects, or errors.

### Test 2: Second account isolation

1. Open Account 2.
2. Load Gmail.
3. Sign in with test Google account B.
4. Confirm Gmail inbox for account B is visible.
5. Switch back to Account 1.
6. Confirm Account 1 still shows account A, not account B.
7. Capture screenshots of both account views.
8. Record whether account identity is stable.

### Test 3: Fast switching without reload

1. Open Gmail in both account slots.
2. Use `Command-1` and `Command-2` to switch at least ten times.
3. Confirm switching is instant or near-instant.
4. Confirm the pages do not reload each time.
5. Type in the Gmail search box on Account 1.
6. Switch to Account 2.
7. Switch back to Account 1.
8. Confirm the search box state is preserved.

### Test 4: Persistence after restart

1. Sign into Account 1 and Account 2.
2. Quit the app completely.
3. Reopen the app.
4. Open Account 1.
5. Open Account 2.
6. Confirm both accounts are still signed in.
7. Record whether either account requires sign-in again.

### Test 5: Per-account clear/reset

1. Start with both accounts signed in.
2. Clear Account 1 website data using the debug button.
3. Reload Account 1.
4. Confirm Account 1 is signed out or reset.
5. Open Account 2.
6. Confirm Account 2 is still signed in.
7. If Account 2 is also signed out, mark this test as failed.

### Test 6: Service smoke test

For Account 1:

1. Open Gmail.
2. Open Calendar.
3. Open Drive.
4. Open Meet.
5. Record whether each service loads.

For Account 2:

1. Open Gmail.
2. Open Calendar.
3. Open Drive.
4. Open Meet.
5. Record whether each service loads.

For Meet:

1. Start or join a safe test meeting only if appropriate.
2. Record camera permission behavior.
3. Record microphone permission behavior.
4. Record screen-sharing behavior if tested.
5. Do not conduct real meetings during the spike.

### Test 7: App Sandbox test

1. Turn on App Sandbox in Xcode under Signing & Capabilities.
2. Repeat Test 1.
3. Repeat Test 2.
4. Repeat Test 4.
5. Repeat Test 5.
6. Record any differences between sandboxed and non-sandboxed builds.

### Test 8: Unsupported account types

Run this only if test accounts are available.

1. Try a passkey-only Google account.
2. Record whether sign-in succeeds or fails.
3. Try an Advanced Protection Google account if available.
4. Record whether sign-in succeeds or fails.
5. Do not spend more than two hours trying to fix this.
6. The expected result may be that these account types are unsupported.

---

## 8. Results template

Copy this section into the spike report and fill it in.

### Single-account Gmail load

Pass/fail:

Evidence:

Notes:

Follow-up:

### Second account isolation

Pass/fail:

Evidence:

Notes:

Follow-up:

### Fast switching

Pass/fail:

Evidence:

Notes:

Follow-up:

### Persistence after restart

Pass/fail:

Evidence:

Notes:

Follow-up:

### Per-account clear/reset

Pass/fail:

Evidence:

Notes:

Follow-up:

### Gmail, Calendar, Drive, and Meet smoke test

Pass/fail:

Evidence:

Notes:

Follow-up:

### App Sandbox test

Pass/fail:

Evidence:

Notes:

Follow-up:

### Unsupported account type test

Pass/fail:

Evidence:

Notes:

Follow-up:

---

## 9. Required deliverables

The developer must provide:

- A working Xcode project.
- A `README.md` explaining how to run the spike app.
- Screenshots or short screen recordings for each major test.
- A completed pass/fail report.
- Exact error messages encountered.
- A short recommendation.
- A list of technical blockers.
- A list of non-compliant or risky approaches that were intentionally avoided.

The final recommendation must be one of:

- Proceed
- Proceed with Caveats
- Stop / Pivot

---

## 10. README template for the developer

Use this as the project README.

```markdown
# Multitude WKWebView Isolation Spike

## Goal

Test whether multiple Google accounts can run in isolated WKWebView sessions in a native macOS app.

## How to Run

1. Open `MultitudeSpike.xcodeproj` in Xcode.
2. Select the `MultitudeSpike` scheme.
3. Run the macOS app.
4. Use Account 1 and Account 2 to sign into different Google accounts.

## Debug Controls

- Reload Active: reloads the visible WKWebView.
- Clear Active Website Data: clears data for the active web session if possible.
- Print Cookies: prints cookie names/domains only, not values.
- Storage Probe: writes/reads a harmless localStorage marker.

## Test Accounts Used

- Account A: [fill in non-sensitive description]
- Account B: [fill in non-sensitive description]

## Results Summary

Independent sign-in: PASS/FAIL

Persistence after restart: PASS/FAIL

Per-account reset: PASS/FAIL

App Sandbox: PASS/FAIL

Meet media permissions: PASS/FAIL

## Recommendation

Proceed / Proceed with Caveats / Stop-Pivot

## Notes

[Add observations, errors, screenshots, and limitations.]
```

---

## 11. Minimal code skeleton

This skeleton is only a starting point.

The developer may adapt it, but should keep the same responsibilities:

- Account model
- Web view factory
- Session manager
- Debug controls

```swift
import SwiftUI
import WebKit

@main
struct MultitudeSpikeApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands {
            CommandMenu("Accounts") {
                Button("Account 1") {
                    NotificationCenter.default.post(name: .switchAccount, object: 1)
                }
                .keyboardShortcut("1", modifiers: [.command])

                Button("Account 2") {
                    NotificationCenter.default.post(name: .switchAccount, object: 2)
                }
                .keyboardShortcut("2", modifiers: [.command])
            }
        }
    }
}

extension Notification.Name {
    static let switchAccount = Notification.Name("switchAccount")
}

struct ContentView: View {
    @StateObject private var model = SpikeModel()

    var body: some View {
        HStack(spacing: 0) {
            VStack {
                Button("Account 1") { model.activeSlot = 1 }
                Button("Account 2") { model.activeSlot = 2 }

                Divider()

                Button("Gmail") { model.load(.gmail) }
                Button("Calendar") { model.load(.calendar) }
                Button("Drive") { model.load(.drive) }
                Button("Meet") { model.load(.meet) }

                Divider()

                Button("Reload Active") { model.reloadActive() }
                Button("Print Cookies") { model.printCookies() }
                Button("Storage Probe") { model.runStorageProbe() }
                Button("Clear Active Data") { model.clearActiveData() }
            }
            .frame(width: 180)
            .padding()

            WebViewContainer(webView: model.activeWebView)
        }
        .onReceive(NotificationCenter.default.publisher(for: .switchAccount)) { note in
            if let slot = note.object as? Int {
                model.activeSlot = slot
            }
        }
    }
}

enum GoogleService {
    case gmail
    case calendar
    case drive
    case meet

    var url: URL {
        switch self {
        case .gmail:
            return URL(string: "https://mail.google.com/")!
        case .calendar:
            return URL(string: "https://calendar.google.com/")!
        case .drive:
            return URL(string: "https://drive.google.com/")!
        case .meet:
            return URL(string: "https://meet.google.com/")!
        }
    }
}

struct WebViewContainer: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> WKWebView {
        webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
```

The skeleton references `SpikeModel`, which the developer should implement.

`SpikeModel` should own:

- The account slots
- The active slot number
- The `WKWebView` instances
- The current service loader
- Debug actions

---

## 12. Suggested `SpikeModel` responsibilities

`SpikeModel` should do the following:

- Create Account 1 and Account 2 at app launch.
- Create one `WKWebView` per account.
- Keep web views alive when inactive.
- Return the active web view to the UI.
- Load Gmail, Calendar, Drive, or Meet into the active web view.
- Reload the active web view.
- Print cookies for the active web view.
- Run the storage probe for the active web view.
- Clear website data for the active web view.
- Append debug messages to the on-screen debug log.

Avoid complex abstractions.

The spike should be easy to read and easy to delete later.

---

## 13. Guidance for the junior developer

Prefer clear evidence over clever code.

The report matters as much as the prototype.

Do not use private APIs.

Do not spoof the user agent.

Do not print cookie values, auth tokens, email contents, or personal data in logs.

Keep the app simple.

Add only the controls needed to answer the spike questions.

When something fails, capture:

- Exact error message
- Current URL
- Account slot
- Storage mode
- Screenshot
- Steps to reproduce

Ask for help only after you have a reproducible result or a specific blocker.

---

## 14. Final decision guide

### Proceed

Choose this if:

- All must-have checks pass.
- Persistence after restart works.
- Per-account reset works.
- No policy or platform blocker is found.

Meaning:

The core architecture looks viable.

Next action:

Start building the MVP shell.

### Proceed with Caveats

Choose this if:

- Sign-in works.
- Isolation mostly works.
- One or more important limitations remain.

Examples:

- Persistence is limited.
- Meet has issues.
- App Sandbox needs special configuration.
- Per-account reset needs a different implementation.

Meaning:

The product may still be viable, but architecture decisions need adjustment.

Next action:

Review caveats before building the MVP.

### Stop / Pivot

Choose this if:

- Google sign-in is blocked in `WKWebView`.
- Accounts cannot be isolated.
- Accounts share cookies or login state.
- Per-account reset is impossible.
- A compliant implementation path cannot be found.

Meaning:

The core approach does not support the product requirements.

Next action:

Do not build product chrome, badges, notifications, or compose safety until the architecture is changed.

---

## 15. Reference links

Apple `WKWebViewConfiguration.websiteDataStore`:

https://developer.apple.com/documentation/webkit/wkwebviewconfiguration/websitedatastore

Apple `WKWebsiteDataStore`:

https://developer.apple.com/documentation/webkit/wkwebsitedatastore

Apple `WKWebsiteDataStore.nonPersistent()`:

https://developer.apple.com/documentation/webkit/wkwebsitedatastore/nonpersistent()

Apple WebKit media capture permission handling:

https://developer.apple.com/documentation/webkit/wkuidelegate

Google OAuth 2.0 policy and embedded user-agent guidance:

https://developers.google.com/identity/protocols/oauth2/policies

Google OAuth 2.0 for iOS and desktop apps:

https://developers.google.com/identity/protocols/oauth2/native-app

---

## 16. Final notes

This spike should stay small.

The developer should not try to solve every product problem.

The only job is to answer whether isolated Google web sessions in a native macOS `WKWebView` app can support the core Multitude concept.

If the answer is unclear, the developer should provide evidence, screenshots, and exact reproduction steps rather than guessing.
