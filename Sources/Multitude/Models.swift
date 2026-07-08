import Foundation

// MARK: - External Link Rule

/// A rule that sends matching links to the default browser instead of loading
/// them inside the room's web view.
///
/// Domain matching is a suffix check: a rule for `zoom.us` matches
/// `zoom.us`, `www.zoom.us` and `app.zoom.us`.
struct ExternalLinkRule: Identifiable, Codable, Equatable {
    let id: UUID
    /// Domain to match against the URL host (case-insensitive).
    var domain: String
    /// Whether to open silently or ask for confirmation.
    var action: LinkAction
    /// Bundle identifier of the preferred browser for this domain.
    /// `nil` means use the global preference or system default.
    var browserBundleID: String?

    init(id: UUID = UUID(), domain: String, action: LinkAction = .alwaysOpen, browserBundleID: String? = nil) {
        self.id = id
        self.domain = domain
        self.action = action
        self.browserBundleID = browserBundleID
    }
}

/// A browser installed on the system that can open web links.
struct InstalledBrowser: Identifiable, Equatable {
    /// Bundle identifier (e.g. "com.google.Chrome").
    let id: String
    /// User-visible name (e.g. "Chrome").
    let displayName: String
    /// URL to the .app bundle on disk.
    let appURL: URL
}

/// Result from the external link confirmation alert.
enum AskExternalLinkResult {
    case openOnce
    case alwaysOpen
    case cancel
}

enum LinkAction: String, Codable, CaseIterable {
    case alwaysOpen = "alwaysOpen"
    case ask = "ask"

    var label: String {
        switch self {
        case .alwaysOpen: return "Always open externally"
        case .ask: return "Ask before opening"
        }
    }
}

// MARK: - Account

/// A single account "room" in Multitude.
///
/// Each account owns a unique `storeIdentifier` UUID that backs a dedicated
/// persistent `WKWebsiteDataStore`. This is how Multitude guarantees that
/// cookies, localStorage, IndexedDB, and login state never bleed between rooms.
struct MultitudeAccount: Identifiable, Codable, Equatable {
    let id: UUID
    var displayName: String
    var email: String
    /// Identifies the persistent `WKWebsiteDataStore` on disk.
    /// Must stay stable across app launches so the session persists.
    let storeIdentifier: UUID
    var order: Int
    var lastService: GoogleService

    init(
        id: UUID = UUID(),
        displayName: String,
        email: String = "",
        storeIdentifier: UUID = UUID(),
        order: Int,
        lastService: GoogleService = .gmail
    ) {
        self.id = id
        self.displayName = displayName
        self.email = email
        self.storeIdentifier = storeIdentifier
        self.order = order
        self.lastService = lastService
    }
}

// MARK: - Google Service

enum GoogleService: String, CaseIterable, Codable {
    case gmail
    case calendar
    case drive
    case meet
    case docs
    case sheets
    case slides
    case keep
    case photos
    case maps
    case youtube
    case news
    case gemini
    case chat

    static let defaultEnabled: [GoogleService] = [.gmail, .calendar, .drive, .meet]

    static let allAvailable: [GoogleService] = [
        .gmail,
        .calendar,
        .drive,
        .meet,
        .docs,
        .sheets,
        .slides,
        .keep,
        .photos,
        .maps,
        .youtube,
        .news,
        .gemini,
        .chat
    ]

    var title: String {
        switch self {
        case .gmail: return "Gmail"
        case .calendar: return "Calendar"
        case .drive: return "Drive"
        case .meet: return "Meet"
        case .docs: return "Docs"
        case .sheets: return "Sheets"
        case .slides: return "Slides"
        case .keep: return "Keep"
        case .photos: return "Photos"
        case .maps: return "Maps"
        case .youtube: return "YouTube"
        case .news: return "News"
        case .gemini: return "Gemini"
        case .chat: return "Chat"
        }
    }

    var symbol: String {
        switch self {
        case .gmail: return "envelope.fill"
        case .calendar: return "calendar"
        case .drive: return "folder.fill"
        case .meet: return "video.fill"
        case .docs: return "doc.text.fill"
        case .sheets: return "tablecells.fill"
        case .slides: return "rectangle.on.rectangle.angled"
        case .keep: return "note.text"
        case .photos: return "photo.fill"
        case .maps: return "map.fill"
        case .youtube: return "play.rectangle.fill"
        case .news: return "newspaper.fill"
        case .gemini: return "sparkles"
        case .chat: return "message.fill"
        }
    }

    var url: URL {
        switch self {
        case .gmail: return URL(string: "https://mail.google.com/")!
        case .calendar: return URL(string: "https://calendar.google.com/")!
        case .drive: return URL(string: "https://drive.google.com/")!
        case .meet: return URL(string: "https://meet.google.com/")!
        case .docs: return URL(string: "https://docs.google.com/document/")!
        case .sheets: return URL(string: "https://docs.google.com/spreadsheets/")!
        case .slides: return URL(string: "https://docs.google.com/presentation/")!
        case .keep: return URL(string: "https://keep.google.com/")!
        case .photos: return URL(string: "https://photos.google.com/")!
        case .maps: return URL(string: "https://maps.google.com/")!
        case .youtube: return URL(string: "https://www.youtube.com/")!
        case .news: return URL(string: "https://news.google.com/")!
        case .gemini: return URL(string: "https://gemini.google.com/")!
        case .chat: return URL(string: "https://chat.google.com/")!
        }
    }
}
