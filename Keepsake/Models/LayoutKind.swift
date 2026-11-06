import Foundation

/// How the two recordings are placed in the finished keepsake.
enum LayoutKind: String, Codable, CaseIterable, Identifiable {
    case sideBySide
    case stacked

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sideBySide:
            return "Side by side"
        case .stacked:
            return "Stacked"
        }
    }
}

/// Which recorded microphones are mixed into the keepsake.
enum Soundtrack: String, Codable, CaseIterable, Identifiable {
    case both
    case thisPhone
    case otherPhone

    var id: String { rawValue }

    var title: String {
        switch self {
        case .both:
            return "Both"
        case .thisPhone:
            return "This phone"
        case .otherPhone:
            return "Other phone"
        }
    }
}
