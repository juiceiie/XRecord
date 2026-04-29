import SwiftUI

// 包装器：解决 @MainActor singleton + @StateObject 的初始化兼容问题
@MainActor
class UpdateServiceWrapper: ObservableObject {
    let service = UpdateService.shared
}

struct ContentView: View {
    @EnvironmentObject var dataService: DataService
    @StateObject private var updateServiceWrapper: UpdateServiceWrapper

    init() {
        // 使用包装器避免 @MainActor + @StateObject 的初始化问题
        _updateServiceWrapper = StateObject(wrappedValue: UpdateServiceWrapper())
    }

    private var updateService: UpdateService { updateServiceWrapper.service }
    @State private var selectedGroupId: String? = nil
    @State private var showAddGroup = false
    @State private var showAddCard = false
    @State private var editingGroup: Group? = nil
    @State private var editingCard: Card? = nil
    // 固定分组ID：用于添加卡片时保持触发时的分组选择
    @State private var fixedGroupIdForAddCard: String? = nil
    @State private var searchText = ""
    @State private var showBindFile = false
    @State private var showUpdateAlert = false
    @State private var showSettings = false
    @State private var pendingRelease: AppRelease? = nil

    var body: some View {
        // 未绑定文件时显示欢迎界面
        if !dataService.hasBoundFile {
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
                    showAddCard: $showAddCard,
                    editingCard: $editingCard,
                    searchText: $searchText,
                    onPrepareAddCard: { groupId in
                        // 先锁定分组，再打开 sheet，保证 groupId 在 sheet 出现前已设好
                        fixedGroupIdForAddCard = groupId
                        showAddCard = true
                    }
                )
            }
            .frame(minWidth: 700, minHeight: 450)
            .onReceive(NotificationCenter.default.publisher(for: .openAddGroup)) { _ in
                showAddGroup = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .openAddCard)) { _ in
                if selectedGroupId != nil {
                    // 立即固定分组ID，避免延迟导致分组变化
                    fixedGroupIdForAddCard = selectedGroupId
                    showAddCard = true
                } else if let firstGroupId = dataService.data.groups.first?.id {
                    // 如果没有选中分组，使用第一个分组
                    fixedGroupIdForAddCard = firstGroupId
                    showAddCard = true
                }
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
            .sheet(isPresented: $showAddCard) {
                // groupId 优先取编辑中的卡片分组，否则取按下"添加"时锁定的分组
                let resolvedGroupId = editingCard?.groupId ?? fixedGroupIdForAddCard
                CardEditView(
                    isPresented: $showAddCard,
                    editingCard: $editingCard,
                    groupId: resolvedGroupId
                )
            }
            .sheet(isPresented: $showBindFile) {
                BindFileView(isPresented: $showBindFile)
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(isPresented: $showSettings)
                    .environmentObject(updateService)
            }
            // 有新版本时弹出更新提示（自定义弹窗，支持忽略按钮）
            .sheet(isPresented: $showUpdateAlert) {
                if let release = updateService.latestRelease {
                    UpdateAlertView(
                        release: release,
                        currentVersion: updateService.currentVersion,
                        onDownload: {
                            updateService.openDownloadPage()
                            showUpdateAlert = false
                        },
                        onIgnoreOnce: {
                            showUpdateAlert = false
                        },
                        onIgnoreForever: {
                            updateService.ignoreVersion(release.version)
                            updateService.recheckAfterIgnore()
                            showUpdateAlert = false
                        }
                    )
                }
            }
            .onAppear {
                selectedGroupId = nil
            }
            .onChange(of: updateService.hasUpdate) { hasUpdate in
                if hasUpdate { showUpdateAlert = true }
            }
        }
    }
}

// MARK: - 更新提示弹窗

struct UpdateAlertView: View {
    let release: AppRelease
    let currentVersion: String
    let onDownload: () -> Void
    let onIgnoreOnce: () -> Void
    let onIgnoreForever: () -> Void

    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            HStack {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 16))
                    .foregroundColor(.orange)
                Text("发现新版本 🎉")
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                // 版本信息
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text("当前版本")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("v\(currentVersion)")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    HStack(spacing: 8) {
                        Text("最新版本")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("v\(release.version)")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundColor(.orange)
                    }
                    .padding(10)
                    .background(Color.orange.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                // Release notes
                if !release.releaseNotes.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("更新内容")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                        Text(release.releaseNotes)
                            .font(.system(size: 12))
                            .foregroundColor(.primary)
                            .lineLimit(5)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(10)
                    .background(Color.secondary.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)

            Divider()

            // 按钮组
            HStack(spacing: 10) {
                Button(action: onIgnoreOnce) {
                    Text("本次忽略")
                        .font(.system(size: 13))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)

                Button(action: onIgnoreForever) {
                    Text("永久忽略")
                        .font(.system(size: 13))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)

                Button(action: onDownload) {
                    HStack(spacing: 4) {
                        Text("前往下载")
                            .font(.system(size: 13, weight: .medium))
                        Image(systemName: "arrow.down")
                            .font(.system(size: 11))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 18)
        }
        .frame(width: 400)
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
        .sheet(isPresented: $showBindFile) {
            BindFileView(isPresented: $showBindFile)
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
    @Binding var showAddCard: Bool
    @Binding var editingCard: Card?
    @Binding var searchText: String
    var onPrepareAddCard: ((String?) -> Void)? = nil

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

                Button(action: {
                    let targetGroupId = selectedGroupId ?? dataService.data.groups.first?.id
                    onPrepareAddCard?(targetGroupId)
                }) {
                    Label("添加条目", systemImage: "plus")
                        .font(.system(size: 13))
                }
                .buttonStyle(.borderedProminent)
                .disabled(dataService.data.groups.isEmpty)
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

// MARK: - 设置页

struct SettingsView: View {
    @EnvironmentObject var updateService: UpdateService
    @Binding var isPresented: Bool

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

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {

                    // ── 关于 ──
                    SectionHeader(title: "关于")

                    HStack(spacing: 14) {
                        Image(nsImage: NSApp.applicationIconImage)
                            .resizable()
                            .frame(width: 48, height: 48)
                            .clipShape(RoundedRectangle(cornerRadius: 10))

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

                    // ── 更新 ──
                    SectionHeader(title: "更新")

                    VStack(alignment: .leading, spacing: 10) {
                        // 版本状态行
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                if updateService.isChecking {
                                    HStack(spacing: 6) {
                                        ProgressView().scaleEffect(0.7)
                                        Text("正在检查更新…")
                                            .font(.system(size: 13))
                                            .foregroundColor(.secondary)
                                    }
                                } else if updateService.hasUpdate, let release = updateService.latestRelease {
                                    HStack(spacing: 6) {
                                        Circle().fill(Color.orange).frame(width: 8, height: 8)
                                        Text("发现新版本 v\(release.version)")
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundColor(.orange)
                                    }
                                } else if updateService.latestRelease != nil {
                                    HStack(spacing: 6) {
                                        Circle().fill(Color.green).frame(width: 8, height: 8)
                                        Text("已是最新版本")
                                            .font(.system(size: 13))
                                            .foregroundColor(.secondary)
                                    }
                                } else {
                                    Text("当前版本 v\(updateService.currentVersion)")
                                        .font(.system(size: 13))
                                        .foregroundColor(.secondary)
                                }

                                if let errMsg = updateService.lastCheckError {
                                    Text("检查失败：\(errMsg)")
                                        .font(.system(size: 11))
                                        .foregroundColor(.red)
                                }
                            }
                            Spacer()

                            // 按钮组
                            HStack(spacing: 8) {
                                Button(action: { updateService.checkForUpdates() }) {
                                    Label(updateService.isChecking ? "检查中…" : "检查更新",
                                          systemImage: "arrow.clockwise")
                                        .font(.system(size: 12))
                                }
                                .buttonStyle(.bordered)
                                .disabled(updateService.isChecking)

                                if updateService.hasUpdate {
                                    Button(action: {
                                        updateService.openDownloadPage()
                                        isPresented = false
                                    }) {
                                        Label("前往下载", systemImage: "arrow.down.circle")
                                            .font(.system(size: 12))
                                    }
                                    .buttonStyle(.borderedProminent)
                                }
                            }
                        }

                        // 新版本 release notes
                        if updateService.hasUpdate,
                           let notes = updateService.latestRelease?.releaseNotes,
                           !notes.isEmpty {
                            Text(notes)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .padding(10)
                                .background(Color.secondary.opacity(0.06))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .lineLimit(6)
                        }
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

            Divider()

            HStack {
                Spacer()
                Button("关闭") { isPresented = false }
                    .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .frame(width: 480, height: 420)
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
