import Foundation

// MARK: - 数据模型

struct AppData: Codable {
    var groups: [Group]
    var cards: [Card]
    var appTitle: String

    init(groups: [Group] = [], cards: [Card] = [], appTitle: String = "记事本") {
        self.groups = groups
        self.cards = cards
        self.appTitle = appTitle
    }
}

struct Group: Codable, Identifiable, Equatable {
    var id: String = UUID().uuidString
    var name: String
    var colorHex: String
    var createdAt: Date = Date()

    static let defaultColors: [String] = [
        "#4f6ef7", "#16a34a", "#d97706", "#dc2626",
        "#7c3aed", "#0891b2", "#db2777", "#65a30d",
        "#ea580c", "#0284c7", "#c026d3", "#65a30d"
    ]

    static func == (lhs: Group, rhs: Group) -> Bool {
        lhs.id == rhs.id
    }
}

struct Card: Codable, Identifiable, Equatable {
    var id: String = UUID().uuidString
    var groupId: String
    var name: String
    var url: String
    var username: String
    var password: String
    var note: String
    var createdAt: Date = Date()

    static func == (lhs: Card, rhs: Card) -> Bool {
        lhs.id == rhs.id
    }
}
