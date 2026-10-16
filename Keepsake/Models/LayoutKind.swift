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
