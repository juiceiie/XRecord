import SwiftUI

struct ContentView: View {
    @EnvironmentObject var dataService: DataService
    @State private var selectedGroupId: String? = nil
    @State private var showAddGroup = false
    @State private var showAddCard = false
    @State private var editingGroup: Group? = nil
    @State private var editingCard: Card? = nil
    @State private var searchText = ""
    @State private var showBindFile = false

    var body: some View {
        HStack(spacing: 0) {
            // 左侧分组导航
            GroupListView(
                selectedGroupId: $selectedGroupId,
                showAddGroup: $showAddGroup,
                editingGroup: $editingGroup,
                showBindFile: $showBindFile
            )
            .frame(width: 220)

            Divider()

            // 右侧内容区
            CardListView(
                selectedGroupId: $selectedGroupId,
                showAddCard: $showAddCard,
                editingCard: $editingCard,
                searchText: $searchText
            )
        }
        .frame(minWidth: 700, minHeight: 450)
        .onReceive(NotificationCenter.default.publisher(for: .openAddGroup)) { _ in
            showAddGroup = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .openAddCard)) { _ in
            if selectedGroupId != nil {
                showAddCard = true
            }
        }
        .sheet(isPresented: $showAddGroup) {
            GroupEditView(
                isPresented: $showAddGroup,
                editingGroup: $editingGroup
            )
        }
        .sheet(isPresented: $showAddCard) {
            CardEditView(
                isPresented: $showAddCard,
                editingCard: $editingCard,
                groupId: selectedGroupId ?? (dataService.data.groups.first?.id)
            )
        }
        .sheet(isPresented: $showBindFile) {
            BindFileView(isPresented: $showBindFile)
        }
        .onAppear {
            // 默认选中"全部"
            selectedGroupId = nil
        }
    }
}

// MARK: - 绑定数据文件弹窗

struct BindFileView: View {
    @EnvironmentObject var dataService: DataService
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            HStack {
                Text("绑定数据文件")
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                Button(action: { isPresented = false }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 14)
            Divider()

            VStack(spacing: 16) {
                Text("选择或创建一个 record.txt 文件来存储你的数据")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)

                // 当前文件路径
                VStack(alignment: .leading, spacing: 4) {
                    Text("当前文件")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                    HStack {
                        Text(dataService.filePathDisplay)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                    }
                    .padding(10)
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                Divider()

                // 选项
                VStack(spacing: 10) {
                    Button(action: {
                        dataService.pickFile()
                        isPresented = false
                    }) {
                        HStack {
                            Image(systemName: "folder")
                                .font(.system(size: 22))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("📂 选择已有文件")
                                    .font(.system(size: 14, weight: .medium))
                                Text("从任意位置选择已有的 record.txt 文件")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                        .padding(14)
                        .background(Color.blue.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)

                    Button(action: {
                        dataService.createNewFile()
                        isPresented = false
                    }) {
                        HStack {
                            Image(systemName: "doc.badge.plus")
                                .font(.system(size: 22))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("📄 创建新文件")
                                    .font(.system(size: 14, weight: .medium))
                                Text("在指定位置创建新的 record.txt 数据文件")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                        .padding(14)
                        .background(Color.green.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(20)

            Divider()

            HStack {
                Button("取消") { isPresented = false }
                    .buttonStyle(.bordered)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .frame(width: 460, height: 400)
    }
}

// MARK: - 左侧分组列表

struct GroupListView: View {
    @EnvironmentObject var dataService: DataService
    @Binding var selectedGroupId: String?
    @Binding var showAddGroup: Bool
    @Binding var editingGroup: Group?
    @Binding var showBindFile: Bool

    var body: some View {
        VStack(spacing: 0) {
            // 顶部标题区
            HStack {
                TextField("记事本", text: $dataService.data.appTitle)
                    .font(.system(size: 16, weight: .bold))
                    .textFieldStyle(.plain)
                    .onChange(of: dataService.data.appTitle) { _ in
                        dataService.save()
                    }
                Spacer()
                Button(action: { showAddGroup = true }) {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
                .help("新建分组")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            Divider()

            // 分组列表
            ScrollView {
                LazyVStack(spacing: 2) {
                    // 全部选项
                    AllGroupsRowView(
                        isSelected: selectedGroupId == nil,
                        totalCount: dataService.data.cards.count,
                        onSelect: { selectedGroupId = nil }
                    )

                    Divider()
                        .padding(.vertical, 4)

                    ForEach(dataService.data.groups) { group in
                        GroupRowView(
                            group: group,
                            isSelected: selectedGroupId == group.id,
                            count: dataService.groupCount(for: group.id),
                            onSelect: { selectedGroupId = group.id },
                            onEdit: {
                                editingGroup = group
                                showAddGroup = true
                            },
                            onDelete: {
                                dataService.deleteGroup(id: group.id)
                                if selectedGroupId == group.id {
                                    selectedGroupId = nil
                                }
                            }
                        )
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
            }

            Divider()

            // 底部文件绑定入口
            VStack(spacing: 6) {
                Button(action: { showBindFile = true }) {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 11))
                            .foregroundColor(.blue)
                        Text("绑定数据文件")
                            .font(.system(size: 11))
                            .foregroundColor(.blue)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.blue.opacity(0.1))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                Text(dataService.filePathDisplay)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct GroupRowView: View {
    let group: Group
    let isSelected: Bool
    let count: Int
    let onSelect: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color(hex: group.colorHex))
                .frame(width: 10, height: 10)

            Text(group.name)
                .font(.system(size: 13))
                .lineLimit(1)

            Spacer()

            Text("\(count)")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.1))
                .clipShape(Capsule())

            if isHovered {
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 10))
                        .foregroundColor(.red.opacity(0.7))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.15) : (isHovered ? Color.secondary.opacity(0.06) : Color.clear))
        )
        .contentShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isSelected ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
        )
        .onTapGesture { onSelect() }
        .onHover { hovering in isHovered = hovering }
    }
}

// MARK: - 全部记录行

struct AllGroupsRowView: View {
    let isSelected: Bool
    let totalCount: Int
    let onSelect: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "tray.full")
                .font(.system(size: 11))
                .foregroundColor(.blue)

            Text("全部")
                .font(.system(size: 13))
                .lineLimit(1)

            Spacer()

            Text("\(totalCount)")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.1))
                .clipShape(Capsule())
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.blue.opacity(0.12) : (isHovered ? Color.secondary.opacity(0.06) : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isSelected ? Color.blue.opacity(0.3) : Color.clear, lineWidth: 1)
        )
        .onTapGesture { onSelect() }
        .onHover { hovering in isHovered = hovering }
    }
}

// MARK: - 右侧卡片列表

struct CardListView: View {
    @EnvironmentObject var dataService: DataService
    @Binding var selectedGroupId: String?
    @Binding var showAddCard: Bool
    @Binding var editingCard: Card?
    @Binding var searchText: String

    var selectedGroup: Group? {
        dataService.data.groups.first { $0.id == selectedGroupId }
    }

    var filteredCards: [Card] {
        let groupCards: [Card]
        if let gid = selectedGroupId {
            groupCards = dataService.cards(for: gid)
        } else {
            groupCards = dataService.data.cards
        }

        if searchText.isEmpty { return groupCards }

        let q = searchText.lowercased()
        return groupCards.filter {
            $0.name.lowercased().contains(q) ||
            $0.url.lowercased().contains(q) ||
            $0.username.lowercased().contains(q) ||
            $0.note.lowercased().contains(q)
        }
    }

    // 全部视图的卡片（按创建时间降序）
    var allCardsSorted: [Card] {
        let cards = dataService.data.cards
        if searchText.isEmpty { return cards.sorted { $0.createdAt > $1.createdAt } }

        let q = searchText.lowercased()
        return cards.filter {
            $0.name.lowercased().contains(q) ||
            $0.url.lowercased().contains(q) ||
            $0.username.lowercased().contains(q) ||
            $0.note.lowercased().contains(q)
        }.sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        VStack(spacing: 0) {
            // 顶部工具栏
            HStack(spacing: 12) {
                if let group = selectedGroup {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color(hex: group.colorHex))
                            .frame(width: 10, height: 10)
                        Text(group.name)
                            .font(.system(size: 15, weight: .semibold))
                    }
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "tray.full")
                            .font(.system(size: 11))
                            .foregroundColor(.blue)
                        Text("全部记录")
                            .font(.system(size: 15, weight: .semibold))
                    }
                }

                Spacer()

                // 搜索框
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    TextField("搜索...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .frame(width: 160)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                Button(action: { showAddCard = true }) {
                    Label("添加条目", systemImage: "plus")
                        .font(.system(size: 13))
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedGroupId == nil && dataService.data.groups.isEmpty)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()

            // 卡片内容
            if let gid = selectedGroupId {
                // 单个分组 - 支持拖拽排序的 List
                GroupCardList(
                    groupId: gid,
                    cards: $dataService.data.cards,
                    searchText: searchText,
                    onEdit: { card in
                        editingCard = card
                        showAddCard = true
                    },
                    onDelete: { card in
                        dataService.deleteCard(id: card.id)
                    }
                )
            } else {
                // 全部视图 - 按创建时间降序的网格
                if allCardsSorted.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "tray")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary.opacity(0.4))
                        Text("暂无条目，点击左侧新建分组和卡片")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVGrid(columns: [
                            GridItem(.adaptive(minimum: 280, maximum: 400), spacing: 14)
                        ], spacing: 14) {
                            ForEach(allCardsSorted) { card in
                                CardItemView(
                                    card: card,
                                    dataService: dataService,
                                    onEdit: {
                                        editingCard = card
                                        showAddCard = true
                                    },
                                    onDelete: {
                                        dataService.deleteCard(id: card.id)
                                    }
                                )
                            }
                        }
                        .padding(20)
                    }
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

// MARK: - 分组卡片列表（支持拖拽排序）

struct GroupCardList: View {
    let groupId: String
    @Binding var cards: [Card]
    let searchText: String
    let onEdit: (Card) -> Void
    let onDelete: (Card) -> Void

    private var groupCards: Binding<[Card]> {
        Binding(
            get: {
                cards.filter { $0.groupId == groupId }
            },
            set: { newCards in
                // 保持其他分组的卡片不变，只更新当前分组的顺序
                let otherCards = cards.filter { $0.groupId != groupId }
                cards = otherCards + newCards
            }
        )
    }

    private var filteredGroupCards: [Card] {
        let filtered = groupCards.wrappedValue
        if searchText.isEmpty { return filtered }

        let q = searchText.lowercased()
        return filtered.filter {
            $0.name.lowercased().contains(q) ||
            $0.url.lowercased().contains(q) ||
            $0.username.lowercased().contains(q) ||
            $0.note.lowercased().contains(q)
        }
    }

    var body: some View {
        if filteredGroupCards.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "doc.text")
                    .font(.system(size: 40))
                    .foregroundColor(.secondary.opacity(0.4))
                Text("暂无条目，点击上方「添加条目」开始")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVGrid(columns: [
                    GridItem(.adaptive(minimum: 280, maximum: 400), spacing: 14)
                ], spacing: 14) {
                    ForEach(filteredGroupCards) { card in
                        CardItemView(
                            card: card,
                            dataService: DataService.shared,
                            onEdit: { onEdit(card) },
                            onDelete: { onDelete(card) }
                        )
                        .draggable(card.id)
                    }
                }
                .padding(20)
            }
            .dropDestination(for: String.self) { items, _ in
                guard let draggedId = items.first,
                      let draggedIndex = groupCards.wrappedValue.firstIndex(where: { $0.id == draggedId }),
                      let targetIndex = filteredGroupCards.firstIndex(where: { $0.id == draggedId }) else {
                    return false
                }

                // 重新排序
                var mutableCards = groupCards.wrappedValue
                let movedCard = mutableCards.remove(at: draggedIndex)

                // 找到目标位置（在目标卡片之后插入）
                if targetIndex < mutableCards.count {
                    mutableCards.insert(movedCard, at: min(targetIndex + 1, mutableCards.count))
                } else {
                    mutableCards.append(movedCard)
                }

                groupCards.wrappedValue = mutableCards
                DataService.shared.save()
                return true
            }
        }
    }
}

// MARK: - 单个卡片

struct CardItemView: View {
    let card: Card
    let dataService: DataService
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var showPassword = false
    @State private var isHovered = false

    private var groupColor: Color {
        if let group = dataService.data.groups.first(where: { $0.id == card.groupId }) {
            return Color(hex: group.colorHex)
        }
        return .gray
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 卡片头部
            HStack {
                Text(card.name)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                Spacer()
                if isHovered {
                    Button(action: onEdit) {
                        Image(systemName: "pencil")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("编辑")
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                            .foregroundColor(.red.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                    .help("删除")
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider()

            // 地址
            if !card.url.isEmpty {
                CardFieldRow(
                    label: "地址",
                    value: card.url,
                    shortValue: dataService.shortDomain(of: card.url),
                    isURL: true
                )
            }

            // 账号
            if !card.username.isEmpty {
                CardFieldRow(
                    label: "账号",
                    value: card.username,
                    shortValue: card.username,
                    isURL: false,
                    isSecret: false
                )
            }

            // 密码
            if !card.password.isEmpty {
                CardFieldRow(
                    label: "密码",
                    value: card.password,
                    shortValue: showPassword ? card.password : String(repeating: "•", count: min(card.password.count, 12)),
                    isURL: false,
                    isSecret: true,
                    showSecret: $showPassword
                )
            }

            // 备注
            if !card.note.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text("备注")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Text(card.note)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
            }

            Spacer(minLength: 8)
        }
        .frame(maxWidth: .infinity, minHeight: 140)
        .background(
            ZStack(alignment: .leading) {
                // 白色背景
                Color(nsColor: .textBackgroundColor)
                // 左侧彩色边条
                RoundedRectangle(cornerRadius: 10)
                    .fill(groupColor.opacity(0.15))
                    .frame(width: 4)
                    .padding(.vertical, 10)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.05), radius: 3, x: 0, y: 2)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(groupColor.opacity(0.2), lineWidth: 1)
        )
        .onHover { hovering in isHovered = hovering }
    }
}

struct CardFieldRow: View {
    let label: String
    let value: String
    let shortValue: String
    var isURL: Bool = false
    var isSecret: Bool = false
    var showSecret: Binding<Bool>? = nil
    var dataService: DataService? = nil

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .frame(width: 34, alignment: .leading)

            if isURL, let url = URL(string: value) {
                Button(action: { NSWorkspace.shared.open(url) }) {
                    Text(shortValue)
                        .font(.system(size: 12))
                        .foregroundColor(.blue)
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
                .help(value)
            } else {
                Text(isSecret == true && (showSecret?.wrappedValue == false) ? shortValue : value)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.primary)
                    .lineLimit(1)
            }

            Spacer()

            // 复制按钮
            Button(action: { copyToClipboard(value) }) {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("复制 \(label)")

            // 显示/隐藏密码按钮
            if isSecret, let showBinding = showSecret {
                Button(action: { showBinding.wrappedValue.toggle() }) {
                    Image(systemName: showBinding.wrappedValue ? "eye.slash" : "eye")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help(showBinding.wrappedValue ? "隐藏密码" : "显示密码")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }

    private func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
