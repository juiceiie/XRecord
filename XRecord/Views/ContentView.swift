import SwiftUI

// 包装器：解决 @MainActor singleton + @StateObject 的初始化兼容问题
@MainActor
class UpdateServiceWrapper: ObservableObject {
    let service = UpdateService.shared
}

struct ContentView: View {
    @EnvironmentObject var dataService: DataService
    @StateObject private var updateServiceWrapper: UpdateServiceWrapper
    @StateObject private var cardEditWindowPresenter: CardEditWindowPresenter

    init() {
        // 使用包装器避免 @MainActor + @StateObject 的初始化问题
        _updateServiceWrapper = StateObject(wrappedValue: UpdateServiceWrapper())
        _cardEditWindowPresenter = StateObject(wrappedValue: CardEditWindowPresenter())
    }

    private var updateService: UpdateService { updateServiceWrapper.service }
    @State private var selectedGroupId: String? = nil
    @State private var showAddGroup = false
    @State private var editingGroup: Group? = nil
    @State private var searchText = ""
    @State private var showBindFile = false
    @State private var showSettings = false
    @State private var showMigrationPrompt = false

    var body: some View {
        ZStack {
            // 文件无法解密时显示解锁界面
            if dataService.isLocked {
                LockedView()
                    .frame(minWidth: 700, minHeight: 450)
            } else if !dataService.hasBoundFile {
                WelcomeView(showBindFile: $showBindFile)
                    .frame(minWidth: 700, minHeight: 450)
            } else {
                HStack(spacing: 0) {
                // 左侧分组导航
                    GroupListView(
                        selectedGroupId: $selectedGroupId,
                        showAddGroup: $showAddGroup,
                        editingGroup: $editingGroup,
                        showBindFile: $showBindFile,
                        showSettings: $showSettings
                    )
                    .frame(width: 220)

                    Divider()

                    // 右侧内容区
                    CardListView(
                        selectedGroupId: $selectedGroupId,
                        searchText: $searchText,
                        onPrepareAddCard: { groupId in
                            cardEditWindowPresenter.present(
                                dataService: dataService,
                                editingCard: nil,
                                groupId: groupId
                            )
                        },
                        onEditCard: { card in
                            cardEditWindowPresenter.present(
                                dataService: dataService,
                                editingCard: card,
                                groupId: card.groupId
                            )
                        }
                    )
                }
                .frame(minWidth: 700, minHeight: 450)
                .onReceive(NotificationCenter.default.publisher(for: .openAddGroup)) { _ in
                    showAddGroup = true
                }
                .onReceive(NotificationCenter.default.publisher(for: .openAddCard)) { notification in
                    let requestedGroupId = notification.object as? String
                    let targetGroupId = requestedGroupId ?? selectedGroupId
                    guard let targetGroup = dataService.data.groups.first(where: { $0.id == targetGroupId }) else { return }
                    selectedGroupId = targetGroup.id
                    cardEditWindowPresenter.present(
                        dataService: dataService,
                        editingCard: nil,
                        groupId: targetGroup.id
                    )
                }
                .onReceive(NotificationCenter.default.publisher(for: .selectGroup)) { notification in
                    guard let groupId = notification.object as? String,
                          dataService.data.groups.contains(where: { $0.id == groupId }) else { return }
                    selectedGroupId = groupId
                }
                .sheet(isPresented: $showAddGroup) {
                    GroupEditView(
                        isPresented: $showAddGroup,
                        editingGroup: $editingGroup,
                        onGroupCreated: { newGroupId in
                            // 新建分组后自动选中它
                            selectedGroupId = newGroupId
                        }
                    )
                }
                .onAppear {
                    selectedGroupId = nil
                    considerMigrationPrompt()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openSettings)) { _ in
            showSettings = true
        }
        .sheet(isPresented: $showBindFile) {
            BindFileView(isPresented: $showBindFile)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(isPresented: $showSettings)
                .environmentObject(updateService)
        }
        .sheet(isPresented: $showMigrationPrompt) {
            MigrationPassphraseView(
                isPresented: $showMigrationPrompt,
                hasExisting: false,
                onSave: { dataService.setMigrationPassphrase($0) },
                titleOverride: "建议设置迁移口令",
                introOverride: "主密钥保存在本机钥匙串，日常无需输入密码。设置迁移口令后，才能把数据文件复制到其他 Mac 解锁；否则数据升级后换设备将无法打开。",
                cancelButtonTitle: "以后再说"
            )
        }
    }

    /// 首次绑定或老版本升级后，提醒用户设置迁移口令（只提醒一次）
    private func considerMigrationPrompt() {
        guard dataService.hasBoundFile, !dataService.hasMigrationPassphrase else { return }
        let promptedKey = "xrecord_didPromptMigrationPassphrase"
        guard !UserDefaults.standard.bool(forKey: promptedKey) else { return }
        UserDefaults.standard.set(true, forKey: promptedKey)
        // 稍作延迟，避免与刚关闭的绑定文件弹窗冲突
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            guard dataService.hasBoundFile, !dataService.hasMigrationPassphrase else { return }
            showMigrationPrompt = true
        }
    }
}

// MARK: - 欢迎/首次使用界面

struct WelcomeView: View {
    @Binding var showBindFile: Bool

    var body: some View {
        VStack(spacing: 30) {
            Spacer()

            // Logo
            Image(systemName: "lock.shield")
                .font(.system(size: 80))
                .foregroundColor(.blue)

            VStack(spacing: 12) {
                Text("欢迎使用 XRecord")
                    .font(.system(size: 28, weight: .bold))

                Text("简洁优雅的账号密码管理工具")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
            }

            VStack(spacing: 16) {
                Text("开始使用前，请先绑定一个数据文件")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)

                Button(action: { showBindFile = true }) {
                    HStack(spacing: 8) {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 16))
                        Text("选择或创建数据文件")
                            .font(.system(size: 15, weight: .medium))
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }

            Spacer()

            VStack(spacing: 8) {
                Text("💡 数据将安全存储在本地文件中")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Text("你可以随时更换数据文件的存储位置")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .padding(.bottom, 30)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 数据文件加锁界面

struct LockedView: View {
    @EnvironmentObject var dataService: DataService

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "lock.fill")
                .font(.system(size: 70))
                .foregroundColor(.orange)

            VStack(spacing: 10) {
                Text("数据文件已锁定")
                    .font(.system(size: 24, weight: .bold))
                Text("无法解密当前数据文件。为保护数据，编辑已暂时禁用，不会写回覆盖。")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
                Text(dataService.filePathDisplay)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.top, 4)
            }

            HStack(spacing: 12) {
                Button("输入口令解锁") {
                    dataService.retryUnlock()
                }
                .buttonStyle(.borderedProminent)

                Button("重新绑定数据文件") {
                    dataService.unbindForReselect()
                }
                .buttonStyle(.bordered)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                Text("选择或创建一个 XRecord 密码本来存储你的数据")
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
                                Text("支持 .xrecord 密码本和已有的 .txt 数据文件")
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
                                Text("在指定位置创建新的 .xrecord 密码本")
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
    @Binding var showSettings: Bool

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
                Button(action: {
                    editingGroup = nil  // 确保是新建模式
                    showAddGroup = true
                }) {
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
                        .draggable(group.id)
                        .dropDestination(for: String.self) { items, _ in
                            guard let draggedId = items.first else { return false }
                            return dataService.moveGroup(id: draggedId, onto: group.id)
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
            }

            Divider()

            // 底部操作区
            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    Button(action: { showBindFile = true }) {
                        HStack(spacing: 6) {
                            Image(systemName: "doc.text")
                                .font(.system(size: 11))
                                .foregroundColor(.blue)
                            Text("绑定文件")
                                .font(.system(size: 11))
                                .foregroundColor(.blue)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.blue.opacity(0.1))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Button(action: { showSettings = true }) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("设置")
                }

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
    @State private var showDeleteConfirm = false

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

                Button(action: { showDeleteConfirm = true }) {
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
        .alert("删除分组", isPresented: $showDeleteConfirm) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) { onDelete() }
        } message: {
            Text("确定要删除分组「\(group.name)」吗？该分组下的所有条目也会一并删除，此操作不可恢复。")
        }
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
        .contentShape(RoundedRectangle(cornerRadius: 6))
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
    @Binding var searchText: String
    var onPrepareAddCard: ((String) -> Void)? = nil
    let onEditCard: (Card) -> Void

    var selectedGroup: Group? {
        dataService.data.groups.first { $0.id == selectedGroupId }
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

                if let selectedGroup {
                    Button(action: {
                        onPrepareAddCard?(selectedGroup.id)
                    }) {
                        Label("添加条目", systemImage: "plus")
                            .font(.system(size: 13))
                    }
                    .buttonStyle(.borderedProminent)
                }
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
                        onEditCard(card)
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
                                        onEditCard(card)
                                    },
                                    onDelete: {
                                        dataService.deleteCard(id: card.id)
                                    },
                                    showGroupName: true
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
                        .id(card.id)
                        .draggable(card.id)
                        .dropDestination(for: String.self) { items, _ in
                            guard let draggedId = items.first else { return false }
                            return moveCard(draggedId: draggedId, before: card.id)
                        }
                    }
                }
                .padding(20)
            }
        }
    }

    @discardableResult
    private func moveCard(draggedId: String, before targetId: String) -> Bool {
        guard draggedId != targetId else { return false }
        var ordered = groupCards.wrappedValue
        guard let fromIndex = ordered.firstIndex(where: { $0.id == draggedId }) else { return false }

        let moved = ordered.remove(at: fromIndex)
        guard let targetIndex = ordered.firstIndex(where: { $0.id == targetId }) else {
            ordered.insert(moved, at: fromIndex)
            return false
        }

        ordered.insert(moved, at: targetIndex)
        groupCards.wrappedValue = ordered
        DataService.shared.save()
        return true
    }

}

// MARK: - 单个卡片

struct CardItemView: View {
    let card: Card
    let dataService: DataService
    let onEdit: () -> Void
    let onDelete: () -> Void
    var showGroupName: Bool = false

    @State private var showPassword = false
    @State private var isHovered = false
    @State private var showDeleteConfirm = false
    @State private var shareCopied = false

    private var groupColor: Color {
        if let group = dataService.data.groups.first(where: { $0.id == card.groupId }) {
            return Color(hex: group.colorHex)
        }
        return .gray
    }

    private var cardGroupName: String? {
        dataService.data.groups.first { $0.id == card.groupId }?.name
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 卡片头部
            HStack {
                Text(card.name)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                Spacer()
                if showGroupName, let groupName = cardGroupName {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(groupColor)
                            .frame(width: 6, height: 6)
                        Text(groupName)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(Capsule())
                }
                if isHovered {
                    if isShareableTarget {
                        Button(action: copySharingText) {
                            Image(systemName: shareCopied ? "checkmark" : "square.and.arrow.up")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(shareCopied ? .green : .secondary)
                                .frame(width: 18, height: 18)
                        }
                        .buttonStyle(.plain)
                        .help(shareCopied ? "已复制到剪贴板" : "复制条目信息以供分享")
                    }
                    Button(action: onEdit) {
                        Image(systemName: "pencil")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("编辑")
                    Button(action: { showDeleteConfirm = true }) {
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
                    label: LaunchTarget.isApplication(card.url) ? "应用" : "地址",
                    value: card.url,
                    shortValue: LaunchTarget.displayName(for: card.url, dataService: dataService),
                    isLaunchTarget: true,
                    launchCardID: card.id
                )
            }

            // 账号
            if !card.username.isEmpty {
                CardFieldRow(
                    label: "账号",
                    value: card.username,
                    shortValue: card.username,
                    isSecret: false
                )
            }

            // 密码
            if !card.password.isEmpty {
                CardFieldRow(
                    label: "密码",
                    value: card.password,
                    shortValue: showPassword ? card.password : String(repeating: "•", count: min(card.password.count, 12)),
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
        .alert("删除条目", isPresented: $showDeleteConfirm) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) { onDelete() }
        } message: {
            Text("确定要删除「\(card.name)」吗？此操作不可恢复。")
        }
    }

    private func copySharingText() {
        let isApplication = LaunchTarget.isApplication(card.url)
        let sharingText = card.sharingText(
            groupName: cardGroupName,
            targetLabel: isApplication ? "APP" : "地址",
            targetValue: isApplication
                ? LaunchTarget.displayName(for: card.url, dataService: dataService)
                : card.url
        )
        Clipboard.copy(sharingText)
        shareCopied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            shareCopied = false
        }
    }

    private var isShareableTarget: Bool {
        LaunchTarget.isWebAddress(card.url) || LaunchTarget.isApplication(card.url)
    }
}

struct CardFieldRow: View {
    let label: String
    let value: String
    let shortValue: String
    var isLaunchTarget: Bool = false
    var launchCardID: String? = nil
    var isSecret: Bool = false
    var showSecret: Binding<Bool>? = nil

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .frame(width: 34, alignment: .leading)

            if isLaunchTarget {
                Button(action: { LaunchTarget.open(value, cardID: launchCardID) }) {
                    HStack(spacing: 5) {
                        Image(systemName: LaunchTarget.isApplication(value) ? "app" : "safari")
                            .font(.system(size: 10))
                        Text(shortValue)
                            .font(.system(size: 12))
                            .lineLimit(1)
                    }
                    .foregroundColor(.blue)
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
        Clipboard.copy(text)
    }
}

// MARK: - 设置页

private enum SettingsPage: String, CaseIterable, Identifiable {
    case general = "通用"
    case shortcuts = "快捷键"

    var id: String { rawValue }
}

struct SettingsView: View {
    @EnvironmentObject var updateService: UpdateService
    @EnvironmentObject var dataService: DataService
    @Binding var isPresented: Bool
    @State private var selectedPage: SettingsPage = .general
    @State private var preferredBrowserPath = PreferredBrowserStore.applicationPath
    @State private var showMigrationSheet = false
    @StateObject private var launchAtLoginService = LaunchAtLoginService()
    @AppStorage(CredentialPanelPreferences.isEnabledKey)
    private var credentialPanelEnabled = true
    @AppStorage(PasswordInputPreferences.forcesRomanInputKey)
    private var forcesRomanPasswordInput = false
    @State private var autoDismissSecondsText = String(CredentialPanelPreferences.autoDismissSeconds)

    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            HStack {
                Text("设置")
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

            Picker("设置页面", selection: $selectedPage) {
                ForEach(SettingsPage.allCases) { page in
                    Text(page.rawValue).tag(page)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            Divider()

            VStack(spacing: 0) {
                switch selectedPage {
                case .general:
                    generalSettings
                case .shortcuts:
                    ShortcutSettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            HStack {
                Spacer()
                Button("关闭") { isPresented = false }
                    .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .frame(width: 500, height: 480)
        .sheet(isPresented: $showMigrationSheet) {
            MigrationPassphraseView(
                isPresented: $showMigrationSheet,
                hasExisting: dataService.hasMigrationPassphrase,
                onSave: { dataService.setMigrationPassphrase($0) }
            )
        }
        .alert(
            "无法更改开机启动设置",
            isPresented: Binding(
                get: { launchAtLoginService.errorMessage != nil },
                set: { if !$0 { launchAtLoginService.clearError() } }
            )
        ) {
            Button("确定") { launchAtLoginService.clearError() }
        } message: {
            Text(launchAtLoginService.errorMessage ?? "请稍后重试。")
        }
        .onAppear { launchAtLoginService.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            launchAtLoginService.refresh()
        }
    }

    private var generalSettings: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {

                // ── 关于 ──
                SectionHeader(title: "关于")

                HStack(spacing: 14) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    VStack(alignment: .leading, spacing: 3) {
                        Text("XRecord")
                            .font(.system(size: 15, weight: .semibold))
                        Text("版本 \(updateService.currentVersion)")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        Text("简洁优雅的密码管理工具")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)

                Divider().padding(.horizontal, 20)

                // ── 启动 ──
                SectionHeader(title: "启动")

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 14) {
                        Image(systemName: "power")
                            .font(.system(size: 25))
                            .foregroundColor(.blue)
                            .frame(width: 34)

                        VStack(alignment: .leading, spacing: 3) {
                            Text("开机自动启动 XRecord")
                                .font(.system(size: 13, weight: .medium))
                            Text("登录 Mac 后自动运行 XRecord")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Toggle(
                            "",
                            isOn: Binding(
                                get: { launchAtLoginService.isEnabled },
                                set: { launchAtLoginService.setEnabled($0) }
                            )
                        )
                        .labelsHidden()
                    }

                    if launchAtLoginService.requiresApproval {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text("需要在系统设置的登录项中允许 XRecord")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            Spacer()
                            Button("打开系统设置") {
                                launchAtLoginService.openSystemSettings()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        .padding(.leading, 48)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)

                Divider().padding(.horizontal, 20)

                // ── 凭据浮窗 ──
                SectionHeader(title: "凭据浮窗")

                HStack(spacing: 14) {
                    Image(systemName: "rectangle.on.rectangle")
                        .font(.system(size: 25))
                        .foregroundColor(.blue)
                        .frame(width: 34)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("打开目标后显示凭据浮窗")
                            .font(.system(size: 13, weight: .medium))
                        Text("作为总开关；还会遵循每个条目的独立设置")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Toggle("", isOn: $credentialPanelEnabled)
                        .labelsHidden()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)

                HStack(spacing: 8) {
                    Text("浮窗未使用")
                        .font(.system(size: 13))
                    TextField("", text: $autoDismissSecondsText)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 13))
                        .multilineTextAlignment(.center)
                        .frame(width: 56)
                        .onChange(of: autoDismissSecondsText) { newValue in
                            let trimmed = newValue.trimmingCharacters(in: .whitespaces)
                            guard !trimmed.isEmpty, let seconds = Int(trimmed) else { return }
                            CredentialPanelPreferences.setAutoDismissSeconds(seconds)
                        }
                    Text("秒后自动消失")
                        .font(.system(size: 13))
                    Text("（-1 表示不消失）")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 14)

                Divider().padding(.horizontal, 20)

                // ── 密码输入 ──
                SectionHeader(title: "密码输入")

                HStack(spacing: 14) {
                    Image(systemName: "character.cursor.ibeam")
                        .font(.system(size: 25))
                        .foregroundColor(.blue)
                        .frame(width: 34)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("密码框始终使用英文输入")
                            .font(.system(size: 13, weight: .medium))
                        Text("开启后，输入密码时自动使用英文键盘，仍可输入数字和符号")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Toggle("", isOn: $forcesRomanPasswordInput)
                        .labelsHidden()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)

                Divider().padding(.horizontal, 20)

                // ── 链接打开方式 ──
                SectionHeader(title: "链接打开方式")

                HStack(spacing: 12) {
                    Image(nsImage: preferredBrowserIcon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 34, height: 34)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(preferredBrowserName)
                            .font(.system(size: 13, weight: .medium))
                        Text(preferredBrowserDescription)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    Spacer(minLength: 12)

                    if preferredBrowserPath != nil {
                        Button(action: useSystemDefaultBrowser) {
                            Image(systemName: "arrow.uturn.backward")
                        }
                        .buttonStyle(.bordered)
                        .help("恢复系统默认浏览器")
                    }

                    Button(action: selectBrowser) {
                        Label("选择", systemImage: "folder")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)

                Divider().padding(.horizontal, 20)

                // ── 更新 ──
                SectionHeader(title: "更新")

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("当前版本 v\(updateService.currentVersion)")
                                .font(.system(size: 13))
                            Text("由 Sparkle 安全下载、安装并重新启动")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        Spacer()

                        Button(action: { updateService.checkForUpdates() }) {
                            Label("检查更新", systemImage: "arrow.clockwise")
                                .font(.system(size: 12))
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!updateService.canCheckForUpdates)
                    }

                    Toggle(
                        "自动检查更新",
                        isOn: Binding(
                            get: { updateService.automaticallyChecksForUpdates },
                            set: { updateService.setAutomaticallyChecksForUpdates($0) }
                        )
                    )
                    .font(.system(size: 12))
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)

                Divider().padding(.horizontal, 20)

                // ── 数据安全 ──
                SectionHeader(title: "数据安全")

                HStack(spacing: 14) {
                    Image(systemName: "key.horizontal.fill")
                        .font(.system(size: 25))
                        .foregroundColor(.blue)
                        .frame(width: 34)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("迁移口令")
                            .font(.system(size: 13, weight: .medium))
                        Text(dataService.hasMigrationPassphrase
                             ? "已设置，可将数据文件复制到其他 Mac 并用口令解锁"
                             : "未设置，数据文件只能在本机解锁")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    if dataService.hasMigrationPassphrase {
                        Button("清除") {
                            dataService.clearMigrationPassphrase()
                        }
                        .buttonStyle(.bordered)
                    }

                    Button(dataService.hasMigrationPassphrase ? "修改" : "设置") {
                        showMigrationSheet = true
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)

                Divider().padding(.horizontal, 20)

                // ── 数据 ──
                SectionHeader(title: "数据")

                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("GitHub 仓库")
                            .font(.system(size: 13))
                        Text("查看源码和提交反馈")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button(action: {
                        NSWorkspace.shared.open(URL(string: "https://github.com/juiceiie/XRecord")!)
                    }) {
                        Label("打开", systemImage: "arrow.up.right.square")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
        }
    }

    private var preferredBrowserName: String {
        guard let path = preferredBrowserPath else { return "系统默认浏览器" }
        return URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
    }

    private var preferredBrowserDescription: String {
        guard let path = preferredBrowserPath else { return "网址将使用 macOS 默认浏览器打开" }
        if FileManager.default.fileExists(atPath: path) {
            return path
        }
        return "浏览器不可用，将自动使用系统默认浏览器"
    }

    private var preferredBrowserIcon: NSImage {
        guard let path = preferredBrowserPath,
              FileManager.default.fileExists(atPath: path) else {
            return NSImage(systemSymbolName: "safari", accessibilityDescription: "浏览器")
                ?? NSImage()
        }
        return NSWorkspace.shared.icon(forFile: path)
    }

    private func selectBrowser() {
        let panel = NSOpenPanel()
        panel.title = "选择浏览器"
        panel.message = "选择用于打开网址的 macOS 浏览器应用"
        panel.prompt = "选择"
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.allowedContentTypes = [.applicationBundle]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let applicationURL = panel.url else { return }
        PreferredBrowserStore.select(applicationURL: applicationURL)
        preferredBrowserPath = applicationURL.path
    }

    private func useSystemDefaultBrowser() {
        PreferredBrowserStore.useSystemDefault()
        preferredBrowserPath = nil
    }
}

private struct MigrationPassphraseView: View {
    @Binding var isPresented: Bool
    let hasExisting: Bool
    let onSave: (String) -> Bool
    var titleOverride: String? = nil
    var introOverride: String? = nil
    var cancelButtonTitle: String = "取消"

    @State private var passphrase = ""
    @State private var confirm = ""
    @State private var errorMessage: String?

    private var title: String {
        titleOverride ?? (hasExisting ? "修改迁移口令" : "设置迁移口令")
    }

    private var intro: String {
        introOverride ?? "设置后，将数据文件复制到其他 Mac 时，输入此口令即可解锁。口令不会被保存，请务必牢记；遗失后新设备将无法恢复数据。"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
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

            VStack(alignment: .leading, spacing: 12) {
                Text(intro)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                SecureField("迁移口令（至少 6 位）", text: $passphrase)
                    .textFieldStyle(.roundedBorder)
                SecureField("确认迁移口令", text: $confirm)
                    .textFieldStyle(.roundedBorder)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 11))
                        .foregroundColor(.red)
                }
            }
            .padding(20)

            Divider()

            HStack {
                Button(cancelButtonTitle) { isPresented = false }
                    .buttonStyle(.bordered)
                Spacer()
                Button("保存") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(passphrase.isEmpty)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .frame(width: 440)
    }

    private func save() {
        guard passphrase.count >= 6 else {
            errorMessage = "口令至少 6 位"
            return
        }
        guard passphrase == confirm else {
            errorMessage = "两次输入不一致"
            return
        }
        if onSave(passphrase) {
            isPresented = false
        } else {
            errorMessage = "设置失败，请重试"
        }
    }
}

private struct ShortcutSettingsView: View {
    @ObservedObject private var hotKeyService = GlobalHotKeyService.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SectionHeader(title: "全局快捷键")

                HStack(spacing: 16) {
                    Image(systemName: "magnifyingglass.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(.blue, .blue.opacity(0.18))

                    VStack(alignment: .leading, spacing: 4) {
                        Text("快速检索")
                            .font(.system(size: 14, weight: .semibold))
                        Text("在任意应用中唤起 XRecord 搜索窗口")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    ShortcutRecorderView(service: hotKeyService)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)

                Divider().padding(.horizontal, 20)

                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("恢复默认")
                            .font(.system(size: 13))
                        Text("默认快捷键为 ⌥X")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button("恢复") {
                        _ = hotKeyService.restoreDefault()
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)

            }
        }
    }
}

private struct ShortcutRecorderView: View {
    @ObservedObject var service: GlobalHotKeyService
    @State private var isRecording = false
    @State private var eventMonitor: Any?
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .trailing, spacing: 5) {
            Button(action: toggleRecording) {
                Text(isRecording ? "请按快捷键…" : service.shortcut.displayText)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .frame(minWidth: 86)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 10))
                    .foregroundColor(.red)
            } else if isRecording {
                Text("按 Esc 取消")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
        .onDisappear {
            if isRecording {
                stopRecording(restoreShortcut: true)
            }
        }
    }

    private func toggleRecording() {
        if isRecording {
            stopRecording(restoreShortcut: true)
            return
        }

        errorMessage = nil
        isRecording = true
        service.suspend()
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 {
                stopRecording(restoreShortcut: true)
                return nil
            }

            let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
            guard !modifiers.isEmpty else {
                errorMessage = "请至少包含一个修饰键"
                return nil
            }

            if service.updateShortcut(from: event) {
                stopRecording(restoreShortcut: false)
            } else {
                errorMessage = "快捷键已被占用，请重试"
                service.suspend()
            }
            return nil
        }
    }

    private func stopRecording(restoreShortcut: Bool) {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
        isRecording = false
        if restoreShortcut {
            service.resume()
        }
    }
}

// 设置页分区标题
struct SectionHeader: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.secondary)
            .textCase(.uppercase)
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 6)
    }
}
