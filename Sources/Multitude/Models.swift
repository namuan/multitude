import Foundation

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

    var title: String {
        switch self {
        case .gmail: return "Gmail"
        case .calendar: return "Calendar"
        case .drive: return "Drive"
        case .meet: return "Meet"
        }
    }

    var symbol: String {
        switch self {
        case .gmail: return "envelope.fill"
        case .calendar: return "calendar"
        case .drive: return "folder.fill"
        case .meet: return "video.fill"
        }
    }

    var url: URL {
        switch self {
        case .gmail: return URL(string: "https://mail.google.com/")!
        case .calendar: return URL(string: "https://calendar.google.com/")!
        case .drive: return URL(string: "https://drive.google.com/")!
        case .meet: return URL(string: "https://meet.google.com/")!
        }
    }
}
