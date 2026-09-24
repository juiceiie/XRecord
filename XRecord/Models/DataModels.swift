import Foundation

// MARK: - 数据模型

private func datesMatchAtPersistedPrecision(_ lhs: Date, _ rhs: Date) -> Bool {
    Int64(lhs.timeIntervalSince1970) == Int64(rhs.timeIntervalSince1970)
}

private func optionalDatesMatchAtPersistedPrecision(_ lhs: Date?, _ rhs: Date?) -> Bool {
    switch (lhs, rhs) {
    case (.none, .none):
        return true
    case let (.some(lhs), .some(rhs)):
        return datesMatchAtPersistedPrecision(lhs, rhs)
    default:
        return false
    }
}

struct AppData: Codable, Equatable {
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
        "#ea580c", "#0284c7", "#c026d3", "#475569"
    ]

    static func == (lhs: Group, rhs: Group) -> Bool {
        lhs.id == rhs.id
            && lhs.name == rhs.name
            && lhs.colorHex == rhs.colorHex
            && datesMatchAtPersistedPrecision(lhs.createdAt, rhs.createdAt)
    }
}

// MARK: - 条目类型

/// 标准条目固定填写账号与密码；自定义条目由用户自行添加若干「名称: 内容」小项。
enum CardKind: String, Codable {
    case standard
    case custom
}

/// 自定义条目中的一个小项，例如「帐套：12344」
struct CustomField: Codable, Identifiable, Equatable {
    var id: String = UUID().uuidString
    var label: String
    var value: String
    /// 是否以密文方式显示（类似密码）
    var isSecret: Bool? = nil

    var isSecretField: Bool {
        isSecret ?? false
    }

    static func == (lhs: CustomField, rhs: CustomField) -> Bool {
        lhs.id == rhs.id && lhs.label == rhs.label && lhs.value == rhs.value && lhs.isSecretField == rhs.isSecretField
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
    var showsCredentialPanel: Bool? = nil
    var isFavorite: Bool? = nil
    var deletedAt: Date? = nil
    var kind: CardKind? = nil
    var customFields: [CustomField]? = nil
    var createdAt: Date = Date()
    /// 旧版本文件没有该字段，因此保持可选并回退到创建时间。
    var updatedAt: Date? = nil

    var isCredentialPanelEnabled: Bool {
        showsCredentialPanel ?? true
    }

    var isFavorited: Bool {
        isFavorite ?? false
    }

    var isTrashed: Bool {
        deletedAt != nil
    }

    var cardKind: CardKind {
        kind ?? .standard
    }

    var isCustom: Bool {
        cardKind == .custom
    }

    var latestUpdatedAt: Date {
        updatedAt ?? createdAt
    }

    /// 只比较用户可编辑的条目内容，不包含收藏、回收站状态和时间元数据。
    func hasContentChanges(comparedTo other: Card) -> Bool {
        groupId != other.groupId
            || name != other.name
            || url != other.url
            || username != other.username
            || password != other.password
            || note != other.note
            || showsCredentialPanel != other.showsCredentialPanel
            || cardKind != other.cardKind
            || customFields != other.customFields
    }

    /// 自定义条目中有效（内容非空）的小项
    var effectiveCustomFields: [CustomField] {
        (customFields ?? []).filter {
            !$0.label.trimmingCharacters(in: .whitespaces).isEmpty
                || !$0.value.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    func sharingText(
        groupName: String?,
        targetLabel: String = "地址",
        targetValue: String? = nil
    ) -> String {
        var lines = [
            "【XRecord笔记本】",
            "分类：\(groupName ?? "未分类")",
            "名称：\(name)"
        ]

        let resolvedTarget = targetValue ?? url
        if !resolvedTarget.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("\(targetLabel)：\(resolvedTarget)")
        }

        if isCustom {
            for field in effectiveCustomFields
            where !field.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let label = field.label.trimmingCharacters(in: .whitespacesAndNewlines)
                lines.append("\(label.isEmpty ? "小项" : label)：\(field.value)")
            }
        } else {
            if !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                lines.append("账号：\(username)")
            }
            if !password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                lines.append("密码：\(password)")
            }
        }

        if !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("备注：\(note)")
        }
        return lines.joined(separator: "\n")
    }

    static func == (lhs: Card, rhs: Card) -> Bool {
        lhs.id == rhs.id
            && lhs.groupId == rhs.groupId
            && lhs.name == rhs.name
            && lhs.url == rhs.url
            && lhs.username == rhs.username
            && lhs.password == rhs.password
            && lhs.note == rhs.note
            && lhs.showsCredentialPanel == rhs.showsCredentialPanel
            && lhs.isFavorite == rhs.isFavorite
            && optionalDatesMatchAtPersistedPrecision(lhs.deletedAt, rhs.deletedAt)
            && lhs.kind == rhs.kind
            && lhs.customFields == rhs.customFields
            && datesMatchAtPersistedPrecision(lhs.createdAt, rhs.createdAt)
            && optionalDatesMatchAtPersistedPrecision(lhs.updatedAt, rhs.updatedAt)
    }
}
