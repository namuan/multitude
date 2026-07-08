# Future feature ideas

This document lists potential features for Multitude. It is a planning aid, not a committed roadmap.

Multitude currently focuses on isolated Google account rooms, service tabs, Gmail unread badges, native notifications, navigation controls and a debug panel. The ideas below build on that core without weakening account isolation.

## Near-term improvements

These features look small enough to add without changing the core architecture.

### Custom services

Let users add their own service pills with a title, URL and SF Symbol.

This would support internal tools, Google Admin, Google Cloud, Google Analytics and non-Google web apps. Each custom service should still open inside the active room's isolated `WKWebsiteDataStore`.

Possible scope:

- add, edit, reorder and delete custom services
- validate URLs before saving
- store custom services in Application Support
- let users choose whether a service appears for all rooms or only selected rooms

Todo list:

- [ ] define a `ServiceDefinition` model that can represent built-in Google services and user-created services
- [ ] decide how custom service IDs should work so saved data survives title or URL changes
- [ ] add persistence for custom services in Application Support
- [ ] add migration logic so existing `enabled_services.json` still loads correctly
- [ ] update the service toolbar to render built-in and custom services from one list
- [ ] add a custom service editor sheet with title, URL and SF Symbol fields
- [ ] validate that URLs use `http` or `https` before saving
- [ ] show clear validation errors in the editor sheet
- [ ] add controls to edit and delete existing custom services
- [ ] add a reorder control for custom services if service reordering is not done first
- [ ] decide whether custom services are global or can be limited to selected rooms
- [ ] if room-limited services are supported, add room selection to the editor sheet
- [ ] make sure custom services load inside the active room's existing `WKWebView`
- [ ] make sure custom services do not create shared cookies or shared website data
- [ ] add logging for custom service creation, updates, deletion and navigation
- [ ] update the README with custom service setup instructions
- [ ] test adding, editing, deleting and reopening the app
- [ ] test invalid URLs, duplicate titles and empty fields
- [ ] test custom services across at least 2 rooms
- [ ] test that built-in Google services still work after migration

### Reorder service pills

Let users drag service pills into their preferred order.

The app already stores enabled services. This feature would add a simple ordering control instead of relying on the order in which users enable services.

Todo list:

- [ ] decide whether users reorder pills directly in the toolbar or inside the service configuration sheet
- [ ] update the enabled services persistence format to preserve explicit order
- [ ] add migration logic for existing users who only have enabled service names saved
- [ ] add reorder controls to `ServiceConfigView`
- [ ] update `setService(_:enabled:)` so new services are added in a predictable place
- [ ] prevent users from creating duplicate service entries during reorder
- [ ] keep the rule that at least one service must remain enabled
- [ ] make sure each room's `lastService` still resolves after reordering
- [ ] make sure the active service highlight follows the service, not its old index
- [ ] add keyboard and VoiceOver-friendly reorder support if the UI uses drag and drop
- [ ] log service order changes for debugging
- [ ] test reorder, quit and relaunch
- [ ] test disabling a reordered active service
- [ ] test re-enabling a service after it was disabled
- [ ] test reorder with the default 4 services and with all built-in services enabled
- [ ] update the README if the service configuration flow changes

### Edit room details

Add a room settings sheet for display name, email label, colour and avatar initials.

The current context menu supports renaming only. A full settings sheet would make rooms easier to identify when users manage several accounts.

Todo list:

- [ ] extend `MultitudeAccount` with optional colour and avatar initials fields
- [ ] decide whether avatar initials are generated, user-editable or both
- [ ] add migration-safe defaults for existing room records
- [ ] replace the rename sheet with a room settings sheet
- [ ] add fields for display name, email label, room colour and avatar initials
- [ ] validate that display name is not empty before saving
- [ ] validate avatar initials length if initials are user-editable
- [ ] update `RoomRowView` to use the selected colour
- [ ] update `RoomRowView` to use custom initials when present
- [ ] keep the existing context menu entry, but rename it to `Room settings…`
- [ ] decide whether the add room sheet should also include colour and initials
- [ ] save room detail changes through the existing account persistence flow
- [ ] log room detail changes without exposing unnecessary personal data
- [ ] test editing each field and relaunching the app
- [ ] test rooms with no email label
- [ ] test long display names and long email labels in the sidebar
- [ ] test colour contrast in light and dark mode
- [ ] update the README room management section

### Better unread badge controls

Give users control over how unread badges work.

Possible settings:

- choose the unread polling interval
- turn native notifications on or off per room
- turn Dock badges on or off
- mute a room during focus time
- show unread badges only for selected rooms

Todo list:

- [ ] define an `UnreadBadgeSettings` model for global and per-room settings
- [ ] decide which settings are global and which settings belong to a room
- [ ] add persistence for unread badge settings in Application Support
- [ ] add migration-safe defaults that match the current behaviour
- [ ] add a settings UI for polling interval, Dock badge and notification controls
- [ ] add per-room notification controls to the room settings sheet if room settings are built first
- [ ] validate polling intervals so users cannot set a harmful value
- [ ] update `startBadgeTimer()` so it uses the saved polling interval
- [ ] update timer handling so changing the interval restarts the timer safely
- [ ] update `checkAllUnreadCounts()` so muted or disabled rooms are skipped where appropriate
- [ ] update Dock badge logic so it respects the Dock badge setting
- [ ] update notification logic so it respects global and per-room notification settings
- [ ] decide how focus-time mute should work, such as fixed schedules or a simple pause duration
- [ ] add a visible muted state in the room list if room mute is supported
- [ ] log settings changes and skipped badge checks for debugging
- [ ] test first launch defaults
- [ ] test turning notifications off and on again
- [ ] test turning Dock badges off and on again
- [ ] test polling interval changes without creating multiple timers
- [ ] test muted rooms with existing unread counts
- [ ] test that Gmail unread badges still update for enabled rooms
- [ ] update the README permissions and usage sections

### Open links outside Multitude

Every link click prompts the user to open the link in the default browser. The user can choose to open once, always open for that domain (adds a rule), or cancel. Domains with an 'always open' rule skip the prompt entirely.

Users may want Zoom, Slack, GitHub or non-Google links to open outside the current room. Rules could match domains and offer a confirmation prompt the first time.

Todo list:

- [x] define an external link rule model with domain pattern, action and optional notes
- [x] decide the default behaviour for non-Google links
- [x] decide whether rules apply globally or per room
- [x] add persistence for external link rules in Application Support
- [x] add a settings UI to add, edit, enable, disable and delete rules
- [x] add default rule suggestions for common apps such as Zoom, Slack and GitHub
- [x] update `decidePolicyFor navigationAction` to detect matching external links
- [x] open matched links with `NSWorkspace.shared.open(_:)`
- [x] cancel WebKit navigation after handing a link to the default browser
- [x] add a first-time confirmation prompt before opening a matched domain externally
- [x] add a way to remember the user's choice from the confirmation prompt
- [x] make sure normal Google navigation still opens inside the active room
- [x] make sure authentication redirects are not accidentally sent to the default browser
- [x] add logging for matched rules, opened links and cancelled navigations
- [x] intercept all link clicks, not just ones matching existing rules
- [x] prompt for every new domain with options to open once, always open, or cancel
- [ ] test regular links, target blank links and JavaScript popup links
- [ ] test Google sign-in flows to avoid breaking authentication
- [ ] test Meet, Calendar, Gmail attachment links and Drive links
- [ ] test with no matching rules, rules with ask action, and upgrade to always open
- [ ] test adding, editing, and deleting rules through the settings UI
- [ ] test that toolbar button and menu item both open the settings sheet
- [ ] test persistence across app restarts
- [ ] update the README with examples and privacy notes

## Medium-term features

These features are valuable, but need more design and testing.

### Per-room home pages

Let each room open to a chosen service or URL when the app starts.

The app already remembers the last service per room. A home page setting would give users more predictable startup behaviour.

### Safer reset flow

Make room reset harder to trigger by accident.

The current reset action clears isolated website data. A confirmation sheet should explain that the user will need to sign in again for that room.

## Advanced features

These features may need deeper WebKit integration, new permissions or larger architecture changes.

### Multi-window support

Let users open a room or service in a separate Multitude window.

This would help with side-by-side workflows such as Gmail next to Calendar. Each window must keep the same room isolation guarantees.

### Split view inside a room

Let users view 2 services from the same room at once.

For example, a user could keep Gmail and Calendar side by side for the same Google account. This would need careful state handling so navigation and unread checks stay correct.

### Download management

Add a native downloads panel.

The panel could show download progress, open downloaded files and reveal files in Finder. It could also let users choose default download folders per room.

### File upload improvements

Improve native file picker behaviour for Google services.

This could include recent folders, drag-and-drop upload support and clearer error handling when a service blocks a file type.

### Web app permissions dashboard

Show camera, microphone, notification and popup permission state per room.

Users should be able to review what each room can access and reset those choices. This would make privacy behaviour easier to understand.

### Account health checks

Detect common room problems and suggest fixes.

Examples include Google unsupported-browser redirects, repeated navigation failures, expired sessions and blocked media permission. The app could offer to reload, reset the room or open logs.

## Reliability and diagnostics

These features improve supportability and reduce user confusion.

### Export debug bundle

Add a menu item that exports useful diagnostic files.

The bundle could include app version, macOS version, enabled services, room metadata without cookies, recent logs and WebKit user agent details. It should remove email addresses unless the user chooses to include them.

### Crash and termination recovery

Improve recovery when a web content process terminates.

The app currently logs process termination. It could show a lightweight error view with reload and reset options.

### Log viewer improvements

Make the debug panel easier to use.

Possible improvements:

- filter by room
- filter by event type
- copy selected log lines
- pause auto-scroll
- clear logs for the current session only

## Privacy and security

These features should protect the app's main promise: isolated rooms.

### Isolation audit screen

Add a screen that explains how each room is isolated.

This could show the stable store identifier, storage location summary and what data is kept separate. It should avoid exposing sensitive file paths unless the user asks for details.

### App lock

Add optional Touch ID or password protection when opening Multitude.

This would protect visible mail and calendar data if someone else uses the Mac. It should lock the app UI, not change Google sessions.

### Private room mode

Let users create a temporary room that does not persist after closing.

This would be useful for one-off sign-ins, testing, demos or support sessions.

## Product polish

These features make the app feel more complete.

### Onboarding

Add a first-run flow that explains rooms, isolation and service pills.

The flow could help users create their first room and choose default services.

### Menu bar companion

Add an optional menu bar item with unread totals and quick room switching.

This would let users check mail state without opening the main window.

### Appearance settings

Add controls for sidebar size, compact mode and theme behaviour.

The app should follow the system appearance by default, with optional overrides.

### Update mechanism

Add in-app update checks for release builds.

This could use a signed release feed if the app is distributed outside the Mac App Store.
