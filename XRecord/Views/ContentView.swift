import SwiftUI

// 包装器：解决 @MainActor singleton + @StateObject 的初始化兼容问题
@MainActor
class UpdateServiceWrapper: ObservableObject {
    let service = UpdateService.shared
}

// MARK: - 第三段内容状态

private enum CardPaneMode {
    case empty
    case view(Card)
    case add(groupId: String, kind: CardKind)
    case edit(Card)
}

enum SidebarDestination: Equatable {
    case all
    case favorites
    case trash
    case group(String)
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
    @State private var showsFavorites = false
    @State private var showsTrash = false
    @State private var showAddGroup = false
    @State private var editingGroup: Group? = nil
    @State private var searchText = ""
    @State private var showBindFile = false
    @State private var showSettings = false
    @State private var showMigrationPrompt = false
    @State private var viewingCard: Card?
    @AppStorage(PresentationPreferences.modeKey)
    private var presentationModeRaw = CardPresentationMode.popup.rawValue
    @AppStorage(PresentationPreferences.threeColumnWidthKey)
    private var thirdColumnWidth: Double = 320
    @State private var thirdColumnDragStart: Double?
    @State private var paneMode: CardPaneMode = .empty
    @State private var embeddedEditorIsDirty = false
    @State private var embeddedSaveRequestID: UUID?
    @State private var pendingSidebarDestination: SidebarDestination?
    @State private var showUnsavedChangesAlert = false

    private var presentationMode: CardPresentationMode {
        CardPresentationMode(rawValue: presentationModeRaw) ?? .popup
    }

    private var isThreeColumn: Bool { presentationMode == .threeColumn }

    private var currentSectionTitle: String {
        if showsTrash { return "回收站" }
        if showsFavorites { return "收藏夹" }
        if let group = dataService.data.groups.first(where: { $0.id == selectedGroupId }) {
            return group.name
        }
        return "全部记录"
    }

    private var minimumCardListWidth: CGFloat {
        let font = NSFont.systemFont(
            ofSize: 15 * AppearancePreferences.fontScale,
            weight: .semibold
        )
        let titleWidth = (currentSectionTitle as NSString).size(withAttributes: [.font: font]).width
        // 标题色点/图标、搜索框、新增按钮、间距及工具栏两侧留白。
        return ceil(titleWidth + 226)
    }

    var body: some View {
        ZStack {
            if dataService.hasBoundFile && dataService.fileAvailability.blocksAccess {
                FileUnavailableView()
                    .frame(minWidth: 700, minHeight: 450)
            // 文件无法解密时显示解锁界面
            } else if dataService.isLocked {
                LockedView()
                    .frame(minWidth: 700, minHeight: 450)
            } else if !dataService.hasBoundFile {
                WelcomeView(showBindFile: $showBindFile)
                    .frame(minWidth: 700, minHeight: 450)
            } else {
                GeometryReader { geometry in
                    HStack(spacing: 0) {
                // 左侧分组导航
                        GroupListView(
                            selectedGroupId: $selectedGroupId,
                            showsFavorites: $showsFavorites,
                            showsTrash: $showsTrash,
                            showAddGroup: $showAddGroup,
                            editingGroup: $editingGroup,
                            showSettings: $showSettings,
                            onNavigate: requestSidebarNavigation,
                            background: isThreeColumn ? Color.paneSidebarBackground : Color(nsColor: .windowBackgroundColor)
                        )
                        .frame(width: 220)

                        Divider()

                        // 右侧内容区
                        CardListView(
                            selectedGroupId: $selectedGroupId,
                            showsFavorites: $showsFavorites,
                            showsTrash: $showsTrash,
                            searchText: $searchText,
                            selectedCardId: paneSelectedCardId,
                            onViewCard: { handleViewCard($0) },
                            onPrepareAddCard: { groupId, kind in handleAddCard(groupId: groupId, kind: kind) },
                            background: isThreeColumn ? Color.paneListBackground : Color(nsColor: .controlBackgroundColor)
                        )
                        .frame(minWidth: 0, maxWidth: .infinity)
                        .layoutPriority(1)

                        // 第三段：详情栏（仅三段式模式，有内容时从右侧滑出）
                        if isThreeColumn && paneIsVisible {
                            paneResizeHandle
                                .transition(.move(edge: .trailing))
                            cardDetailPane
                                .frame(width: resolvedThirdColumnWidth(for: geometry.size.width))
                                .transition(.move(edge: .trailing))
                        }
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height, alignment: .leading)
                }
                .frame(minWidth: 700, minHeight: 450)
                .animation(.easeInOut(duration: 0.22), value: paneIsVisible)
                .onReceive(NotificationCenter.default.publisher(for: .openAddGroup)) { _ in
                    showAddGroup = true
                }
                .onReceive(NotificationCenter.default.publisher(for: .openAddCard)) { notification in
                    let requestedGroupId = notification.object as? String
                    let targetGroupId = requestedGroupId ?? selectedGroupId
                    guard let targetGroup = dataService.data.groups.first(where: { $0.id == targetGroupId }) else { return }
                    selectedGroupId = targetGroup.id
                    showsFavorites = false
                    showsTrash = false
                    handleAddCard(groupId: targetGroup.id, kind: .standard)
                }
                .onReceive(NotificationCenter.default.publisher(for: .selectGroup)) { notification in
                    guard let groupId = notification.object as? String,
                          dataService.data.groups.contains(where: { $0.id == groupId }) else { return }
                    requestSidebarNavigation(.group(groupId))
                }
                .onChange(of: dataService.data.cards) { cards in
                    clearPaneIfCardRemoved(cards)
                }
                .onChange(of: dataService.trashedCount) { _ in
                    clearPaneIfCardRemoved(dataService.data.cards)
                }
                .sheet(isPresented: $showAddGroup) {
                    GroupEditView(
                        isPresented: $showAddGroup,
                        editingGroup: $editingGroup,
                        onGroupCreated: { newGroupId in
                            paneMode = .empty
                            applySidebarDestination(.group(newGroupId))
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
        .background(
            WindowAccessor { window in
                // 三段式模式需要更宽的最小窗口，保证三栏都可用
                let contentMinimumWidth = 220 + minimumCardListWidth
                    + (isThreeColumn && paneIsVisible ? 270 : 0)
                let minWidth: CGFloat = max(isThreeColumn ? 1000 : 700, contentMinimumWidth)
                if window.minSize.width != minWidth {
                    window.minSize = NSSize(width: minWidth, height: 450)
                }
                if isThreeColumn, window.frame.width < minWidth {
                    var frame = window.frame
                    let previousMaxX = frame.maxX
                    frame.size.width = minWidth
                    frame.origin.x = previousMaxX - minWidth
                    if let visibleFrame = window.screen?.visibleFrame, frame.minX < visibleFrame.minX {
                        frame.origin.x = visibleFrame.minX
                    }
                    window.setFrame(frame, display: true, animate: true)
                }
            }
        )
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
                titleOverride: "建议设置同步与恢复口令",
                introOverride: "主密钥保存在本机钥匙串，日常无需输入密码。设置同步与恢复口令后，才能在其他 Mac 解锁通过 iCloud Drive 或手动复制的数据文件。",
                cancelButtonTitle: "以后再说"
            )
        }
        .sheet(item: $viewingCard) { card in
            CardDetailView(
                card: card,
                dataService: dataService,
                onClose: { viewingCard = nil },
                onEdit: {
                    viewingCard = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        cardEditWindowPresenter.present(
                            dataService: dataService,
                            editingCard: card,
                            groupId: card.groupId
                        )
                    }
                },
                onDelete: {
                    viewingCard = nil
                    dataService.moveCardToTrash(id: card.id)
                }
            )
        }
        .alert("编辑内容尚未保存", isPresented: $showUnsavedChangesAlert) {
            Button("取消", role: .cancel) { pendingSidebarDestination = nil }
            Button("不保存", role: .destructive) { discardEditorAndNavigate() }
            Button("保存") { embeddedSaveRequestID = UUID() }
        } message: {
            Text("切换分类前是否保存当前条目的修改？")
        }
        .appFontSizeScaled()
    }

    /// 首次绑定或老版本升级后，提醒用户设置同步与恢复口令（只提醒一次）
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

    // MARK: - 条目操作入口（按模式分流）

    private func handleViewCard(_ card: Card) {
        if isThreeColumn {
            paneMode = .view(card)
        } else {
            viewingCard = card
        }
    }

    private func handleEditCard(_ card: Card) {
        if isThreeColumn {
            paneMode = .edit(card)
        } else {
            cardEditWindowPresenter.present(
                dataService: dataService,
                editingCard: card,
                groupId: card.groupId
            )
        }
    }

    private func handleAddCard(groupId: String, kind: CardKind) {
        if isThreeColumn {
            paneMode = .add(groupId: groupId, kind: kind)
        } else {
            cardEditWindowPresenter.present(
                dataService: dataService,
                editingCard: nil,
                groupId: groupId,
                kind: kind
            )
        }
    }

    private func handleTrashCard(_ card: Card) {
        dataService.moveCardToTrash(id: card.id)
        // 若该条目正显示在第三段，则一并清空
        if paneSelectedCardId == card.id {
            paneMode = .empty
        }
    }

    private func requestSidebarNavigation(_ destination: SidebarDestination) {
        guard isThreeColumn else {
            applySidebarDestination(destination)
            return
        }

        switch paneMode {
        case .view:
            paneMode = .empty
            applySidebarDestination(destination)
        case .edit, .add:
            if embeddedEditorIsDirty {
                pendingSidebarDestination = destination
                showUnsavedChangesAlert = true
            } else {
                paneMode = .empty
                applySidebarDestination(destination)
            }
        case .empty:
            applySidebarDestination(destination)
        }
    }

    private func applySidebarDestination(_ destination: SidebarDestination) {
        switch destination {
        case .all:
            selectedGroupId = nil
            showsFavorites = false
            showsTrash = false
        case .favorites:
            selectedGroupId = nil
            showsFavorites = true
            showsTrash = false
        case .trash:
            selectedGroupId = nil
            showsFavorites = false
            showsTrash = true
        case .group(let groupID):
            selectedGroupId = groupID
            showsFavorites = false
            showsTrash = false
        }
    }

    private func discardEditorAndNavigate() {
        paneMode = .empty
        embeddedEditorIsDirty = false
        completePendingNavigation()
    }

    private func completePendingNavigation() {
        guard let destination = pendingSidebarDestination else { return }
        pendingSidebarDestination = nil
        applySidebarDestination(destination)
    }

    // MARK: - 第三段（详情栏）

    private var paneSelectedCardId: String? {
        switch paneMode {
        case .view(let card), .edit(let card):
            return card.id
        default:
            return nil
        }
    }

    private var paneIsVisible: Bool {
        if case .empty = paneMode { return false }
        return true
    }

    private func resolvedThirdColumnWidth(for availableWidth: CGFloat) -> CGFloat {
        let sidebarWidth: CGFloat = 220
        let dividersAndHandle: CGFloat = 10
        let maximumWidth = max(
            260,
            availableWidth - sidebarWidth - minimumCardListWidth - dividersAndHandle
        )
        return min(CGFloat(thirdColumnWidth), maximumWidth)
    }

    private var paneDismissBinding: Binding<Bool> {
        Binding(
            get: {
                if case .empty = paneMode { return false }
                return true
            },
            set: { newValue in
                guard !newValue else { return }
                // 保存后 onSaved 会切到查看模式，此时不重置
                if case .view = paneMode { return }
                paneMode = .empty
            }
        )
    }

    private func clearPaneIfCardRemoved(_ cards: [Card]) {
        switch paneMode {
        case .view(let card), .edit(let card):
            if !cards.contains(where: { $0.id == card.id && !$0.isTrashed }) {
                paneMode = .empty
            }
        default:
            break
        }
    }

    /// 第三段左边缘的拖拽分隔条
    private var paneResizeHandle: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(width: 1)
            .frame(width: 8)
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        if thirdColumnDragStart == nil {
                            thirdColumnDragStart = thirdColumnWidth
                        }
                        let base = thirdColumnDragStart ?? thirdColumnWidth
                        let proposed = base - Double(value.translation.width)
                        thirdColumnWidth = min(max(proposed, 260), 420)
                    }
                    .onEnded { _ in
                        thirdColumnDragStart = nil
                    }
            )
    }

    @ViewBuilder
    private var cardDetailPane: some View {
        SwiftUI.Group {
            switch paneMode {
            case .empty:
                VStack(spacing: 12) {
                    Image(systemName: "sidebar.right")
                        .scaledFont(size: 36)
                        .foregroundColor(.secondary.opacity(0.4))
                    Text("选择条目查看详情")
                        .scaledFont(size: 13)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            case .view(let card):
                CardDetailView(
                    card: card,
                    dataService: dataService,
                    embedded: true,
                    onClose: { paneMode = .empty },
                    onEdit: { paneMode = .edit(card) },
                    onDelete: { handleTrashCard(card) }
                )

            case .add(let groupId, let kind):
                CardEditView(
                    isPresented: paneDismissBinding,
                    editingCard: nil,
                    groupId: groupId,
                    initialKind: kind,
                    embedded: true,
                    onSaved: {
                        embeddedEditorIsDirty = false
                        if pendingSidebarDestination != nil {
                            paneMode = .empty
                            completePendingNavigation()
                        } else {
                            paneMode = .view($0)
                        }
                    },
                    onDirtyChange: { embeddedEditorIsDirty = $0 },
                    saveRequestID: embeddedSaveRequestID
                )
                .id("add-\(groupId)-\(kind.rawValue)")

            case .edit(let card):
                CardEditView(
                    isPresented: paneDismissBinding,
                    editingCard: card,
                    groupId: card.groupId,
                    embedded: true,
                    onSaved: {
                        embeddedEditorIsDirty = false
                        if pendingSidebarDestination != nil {
                            paneMode = .empty
                            completePendingNavigation()
                        } else {
                            paneMode = .view($0)
                        }
                    },
                    onDirtyChange: { embeddedEditorIsDirty = $0 },
                    saveRequestID: embeddedSaveRequestID
                )
                .id("edit-\(card.id)")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.paneDetailBackground)
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
                .scaledFont(size: 80)
                .foregroundColor(.blue)

            VStack(spacing: 12) {
                Text("欢迎使用 XRecord")
                    .scaledFont(size: 28, weight: .bold)

                Text("简洁优雅的账号密码管理工具")
                    .scaledFont(size: 16)
                    .foregroundColor(.secondary)
            }

            VStack(spacing: 16) {
                Text("开始使用前，请先绑定一个数据文件")
                    .scaledFont(size: 14)
                    .foregroundColor(.secondary)

                Button(action: { showBindFile = true }) {
                    HStack(spacing: 8) {
                        Image(systemName: "folder.badge.plus")
                            .scaledFont(size: 16)
                        Text("选择或创建数据文件")
                            .scaledFont(size: 15, weight: .medium)
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
                    .scaledFont(size: 12)
                    .foregroundColor(.secondary)
                Text("你可以随时更换数据文件的存储位置")
                    .scaledFont(size: 12)
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
                .scaledFont(size: 70)
                .foregroundColor(.orange)

            VStack(spacing: 10) {
                Text("数据文件已锁定")
                    .scaledFont(size: 24, weight: .bold)
                Text("无法解密当前数据文件。为保护数据，编辑已暂时禁用，不会写回覆盖。")
                    .scaledFont(size: 14)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
                Text(dataService.filePathDisplay)
                    .scaledFont(size: 11, design: .monospaced)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.top, 4)
            }

            HStack(spacing: 12) {
                Button("输入恢复口令解锁") {
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

// MARK: - 数据文件暂不可用界面

struct FileUnavailableView: View {
    @EnvironmentObject var dataService: DataService

    var body: some View {
        VStack(spacing: 18) {
            Spacer()

            if dataService.fileAvailability == .downloading {
                ProgressView()
                    .controlSize(.large)
                Text("正在准备密码本")
                    .scaledFont(size: 22, weight: .bold)
            } else {
                Image(systemName: "exclamationmark.icloud.fill")
                    .scaledFont(size: 60)
                    .foregroundColor(.orange)
                Text("数据文件暂不可用")
                    .scaledFont(size: 22, weight: .bold)
            }

            Text(dataService.fileAvailability.description)
                .scaledFont(size: 14)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)

            Text(dataService.filePathDisplay)
                .scaledFont(size: 11, design: .monospaced)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 480)

            HStack(spacing: 12) {
                Button("重试") { dataService.retryFileAccess() }
                    .buttonStyle(.borderedProminent)
                Button("重新绑定数据文件") { dataService.unbindForReselect() }
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
                    .scaledFont(size: 16, weight: .semibold)
                    Spacer()
                Button(action: { isPresented = false }) {
                    Image(systemName: "xmark")
                        .scaledFont(size: 13, weight: .medium)
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
                    .scaledFont(size: 13)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)

                // 当前文件路径
                VStack(alignment: .leading, spacing: 4) {
                    Text("当前文件")
                        .scaledFont(size: 12, weight: .medium)
                        .foregroundColor(.secondary)
                    HStack {
                        Text(dataService.filePathDisplay)
                            .scaledFont(size: 12, design: .monospaced)
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
                                .scaledFont(size: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("📂 选择已有文件")
                                    .scaledFont(size: 14, weight: .medium)
                                Text("支持 .xrecord 密码本和已有的 .txt 数据文件")
                                    .scaledFont(size: 11)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .scaledFont(size: 12)
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
                                .scaledFont(size: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("📄 创建新文件")
                                    .scaledFont(size: 14, weight: .medium)
                                Text("在指定位置创建新的 .xrecord 密码本")
                                    .scaledFont(size: 11)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .scaledFont(size: 12)
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
    @Binding var showsFavorites: Bool
    @Binding var showsTrash: Bool
    @Binding var showAddGroup: Bool
    @Binding var editingGroup: Group?
    @Binding var showSettings: Bool
    let onNavigate: (SidebarDestination) -> Void
    var background: Color = Color(nsColor: .windowBackgroundColor)

    var body: some View {
        VStack(spacing: 0) {
            // 顶部标题区
            HStack {
                TextField("记事本", text: $dataService.data.appTitle)
                    .scaledFont(size: 16, weight: .bold)
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
                        .scaledFont(size: 14, weight: .semibold)
                        .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
                .help("新建分组")
            }
            .padding(.horizontal, 16)
            .frame(height: 56)

            Divider()

            // 分组列表
            ScrollView {
                LazyVStack(spacing: 2) {
                    // 全部选项
                    AllGroupsRowView(
                        isSelected: selectedGroupId == nil && !showsFavorites && !showsTrash,
                        totalCount: dataService.activeCards.count,
                        onSelect: { onNavigate(.all) }
                    )

                    // 收藏夹
                    FavoritesRowView(
                        isSelected: showsFavorites,
                        count: dataService.favoriteCount,
                        onSelect: { onNavigate(.favorites) }
                    )

                    Divider()
                        .padding(.vertical, 4)

                    ForEach(dataService.data.groups) { group in
                        GroupRowView(
                            group: group,
                            isSelected: selectedGroupId == group.id,
                            count: dataService.groupCount(for: group.id),
                            onSelect: { onNavigate(.group(group.id)) },
                            onEdit: {
                                editingGroup = group
                                showAddGroup = true
                            },
                            onDelete: {
                                dataService.deleteGroup(id: group.id)
                                if selectedGroupId == group.id {
                                    onNavigate(.all)
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

            // 回收站
            TrashRowView(
                isSelected: showsTrash,
                count: dataService.trashedCount,
                onSelect: { onNavigate(.trash) }
            )
            .padding(.horizontal, 8)
            .padding(.vertical, 6)

            Divider()

            // 设置
            HStack(spacing: 8) {
                Spacer()

                Button(action: { showSettings = true }) {
                    Image(systemName: "gearshape")
                        .scaledFont(size: 13)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("设置")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(background)
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
                .scaledFont(size: 13)
                .lineLimit(1)

            Spacer()

            Text("\(count)")
                .scaledFont(size: 11)
                .foregroundColor(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.1))
                .clipShape(Capsule())

            if isHovered {
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .scaledFont(size: 10)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)

                Button(action: { showDeleteConfirm = true }) {
                    Image(systemName: "trash")
                        .scaledFont(size: 10)
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
                .scaledFont(size: 11)
                .foregroundColor(.blue)

            Text("全部")
                .scaledFont(size: 13)
                .lineLimit(1)

            Spacer()

            Text("\(totalCount)")
                .scaledFont(size: 11)
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

// MARK: - 收藏夹行

struct FavoritesRowView: View {
    let isSelected: Bool
    let count: Int
    let onSelect: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "star.fill")
                .scaledFont(size: 11)
                .foregroundColor(.yellow)

            Text("收藏夹")
                .scaledFont(size: 13)
                .lineLimit(1)

            Spacer()

            Text("\(count)")
                .scaledFont(size: 11)
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
                .fill(isSelected ? Color.yellow.opacity(0.14) : (isHovered ? Color.secondary.opacity(0.06) : Color.clear))
        )
        .contentShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isSelected ? Color.yellow.opacity(0.4) : Color.clear, lineWidth: 1)
        )
        .onTapGesture { onSelect() }
        .onHover { hovering in isHovered = hovering }
    }
}

// MARK: - 回收站行

struct TrashRowView: View {
    let isSelected: Bool
    let count: Int
    let onSelect: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "trash")
                .scaledFont(size: 11)
                .foregroundColor(.secondary)

            Text("回收站")
                .scaledFont(size: 13)
                .lineLimit(1)

            Spacer()

            Text("\(count)")
                .scaledFont(size: 11)
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
                .fill(isSelected ? Color.secondary.opacity(0.16) : (isHovered ? Color.secondary.opacity(0.06) : Color.clear))
        )
        .contentShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isSelected ? Color.secondary.opacity(0.35) : Color.clear, lineWidth: 1)
        )
        .onTapGesture { onSelect() }
        .onHover { hovering in isHovered = hovering }
    }
}

// MARK: - 右侧卡片列表

struct CardListView: View {
    @EnvironmentObject var dataService: DataService
    @State private var showEmptyTrashConfirm = false
    @Binding var selectedGroupId: String?
    @Binding var showsFavorites: Bool
    @Binding var showsTrash: Bool
    @Binding var searchText: String
    var selectedCardId: String? = nil
    var onViewCard: ((Card) -> Void)? = nil
    var onPrepareAddCard: ((String, CardKind) -> Void)? = nil
    var background: Color = Color(nsColor: .controlBackgroundColor)
    @AppStorage(AppearancePreferences.cardListStyleKey)
    private var cardListStyleRaw = CardListStyle.regular.rawValue

    private var cardListStyle: CardListStyle {
        CardListStyle(rawValue: cardListStyleRaw) ?? .regular
    }

    var selectedGroup: Group? {
        dataService.data.groups.first { $0.id == selectedGroupId }
    }

    // 全部视图的卡片（按创建时间降序）
    var allCardsSorted: [Card] {
        let cards = dataService.activeCards
        if searchText.isEmpty { return cards.sorted { $0.createdAt > $1.createdAt } }

        let q = searchText.lowercased()
        return cards.filter {
            $0.name.lowercased().contains(q) ||
            $0.url.lowercased().contains(q) ||
            $0.username.lowercased().contains(q) ||
            $0.note.lowercased().contains(q)
        }.sorted { $0.createdAt > $1.createdAt }
    }

    // 收藏夹视图的卡片（按创建时间降序）
    var favoriteCardsSorted: [Card] {
        let cards = dataService.activeCards.filter { $0.isFavorited }
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
                SwiftUI.Group {
                    if showsTrash {
                    HStack(spacing: 6) {
                        Image(systemName: "trash")
                            .scaledFont(size: 12)
                            .foregroundColor(.secondary)
                        Text("回收站")
                            .scaledFont(size: 15, weight: .semibold)
                            .lineLimit(1)
                    }
                    } else if showsFavorites {
                    HStack(spacing: 6) {
                        Image(systemName: "star.fill")
                            .scaledFont(size: 12)
                            .foregroundColor(.yellow)
                        Text("收藏夹")
                            .scaledFont(size: 15, weight: .semibold)
                            .lineLimit(1)
                    }
                    } else if let group = selectedGroup {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color(hex: group.colorHex))
                            .frame(width: 10, height: 10)
                        Text(group.name)
                            .scaledFont(size: 15, weight: .semibold)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    } else {
                    HStack(spacing: 6) {
                        Image(systemName: "tray.full")
                            .scaledFont(size: 11)
                            .foregroundColor(.blue)
                        Text("全部记录")
                            .scaledFont(size: 15, weight: .semibold)
                            .lineLimit(1)
                    }
                    }
                }
                .layoutPriority(1)

                Spacer()

                // 搜索框
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .scaledFont(size: 12)
                        .foregroundColor(.secondary)
                    TextField("搜索...", text: $searchText)
                        .textFieldStyle(.plain)
                        .scaledFont(size: 13)
                        .frame(minWidth: 72, maxWidth: 160)
                }
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(Color.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                if showsTrash {
                    if !dataService.trashedCards.isEmpty {
                        Button(action: { showEmptyTrashConfirm = true }) {
                            Label("清空回收站", systemImage: "trash.slash")
                                .scaledFont(size: 13)
                        }
                        .buttonStyle(.bordered)
                        .frame(height: 30)
                    }
                } else if let selectedGroup {
                    Menu {
                        Button {
                            onPrepareAddCard?(selectedGroup.id, .standard)
                        } label: {
                            Label("标准条目", systemImage: "person.text.rectangle")
                        }
                        Button {
                            onPrepareAddCard?(selectedGroup.id, .custom)
                        } label: {
                            Label("自定义条目", systemImage: "square.and.pencil")
                        }
                    } label: {
                        Image(systemName: "plus")
                            .scaledFont(size: 13, weight: .semibold)
                            .foregroundColor(.white)
                            .frame(width: 30, height: 30)
                            .background(Color(hex: selectedGroup.colorHex))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                    .menuIndicator(.hidden)
                }
            }
            .padding(.horizontal, 20)
            .frame(height: 56)

            Divider()

            // 卡片内容
            if showsTrash {
                TrashListView(searchText: searchText)
            } else if showsFavorites {
                // 收藏夹视图 - 跨分组的收藏条目
                if favoriteCardsSorted.isEmpty {
                    emptyState(icon: "star", text: "暂无收藏条目，点击条目右上角的星标即可收藏")
                } else {
                    cardsGrid(favoriteCardsSorted)
                }
            } else if let gid = selectedGroupId {
                // 单个分组 - 支持拖拽排序的 List
                GroupCardList(
                    groupId: gid,
                    cards: $dataService.data.cards,
                    searchText: searchText,
                    selectedCardId: selectedCardId,
                    onView: { card in
                        onViewCard?(card)
                    }
                )
            } else {
                // 全部视图 - 按创建时间降序的网格
                if allCardsSorted.isEmpty {
                    emptyState(icon: "tray", text: "暂无条目，点击左侧新建分组和卡片")
                } else {
                    cardsGrid(allCardsSorted)
                }
            }
        }
        .background(background)
        .alert("清空回收站", isPresented: $showEmptyTrashConfirm) {
            Button("取消", role: .cancel) {}
            Button("清空", role: .destructive) { dataService.emptyTrash() }
        } message: {
            Text("将永久删除回收站中的所有条目，此操作不可恢复。")
        }
    }

    @ViewBuilder
    private func cardsGrid(_ cards: [Card]) -> some View {
        ScrollView {
            if cardListStyle == .compact {
                LazyVStack(spacing: 8) {
                    ForEach(cards) { card in
                        MinimalCardItemView(
                            card: card,
                            dataService: dataService,
                            isSelected: card.id == selectedCardId,
                            onView: { onViewCard?(card) },
                            onToggleFavorite: { dataService.toggleFavorite(cardID: card.id) }
                        )
                    }
                }
                .padding(20)
            } else {
                LazyVGrid(columns: [
                    GridItem(.adaptive(minimum: 280, maximum: 400), spacing: 14)
                ], spacing: 14) {
                    ForEach(cards) { card in
                        CardItemView(
                            card: card,
                            dataService: dataService,
                            isSelected: card.id == selectedCardId,
                            onView: { onViewCard?(card) },
                            onToggleFavorite: { dataService.toggleFavorite(cardID: card.id) },
                            showGroupName: true
                        )
                    }
                }
                .padding(20)
            }
        }
    }

    private func emptyState(icon: String, text: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .scaledFont(size: 40)
                .foregroundColor(.secondary.opacity(0.4))
            Text(text)
                .scaledFont(size: 14)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 回收站列表

struct TrashListView: View {
    @EnvironmentObject var dataService: DataService
    let searchText: String

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()

    private var filteredCards: [Card] {
        let cards = dataService.trashedCards
        guard !searchText.isEmpty else { return cards }

        let q = searchText.lowercased()
        return cards.filter {
            $0.name.lowercased().contains(q) ||
            $0.url.lowercased().contains(q) ||
            $0.username.lowercased().contains(q) ||
            $0.note.lowercased().contains(q)
        }
    }

    var body: some View {
        let cards = filteredCards
        if cards.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: dataService.trashedCards.isEmpty ? "trash" : "magnifyingglass")
                    .scaledFont(size: 40)
                    .foregroundColor(.secondary.opacity(0.4))
                Text(dataService.trashedCards.isEmpty ? "回收站是空的" : "没有找到匹配的条目")
                    .scaledFont(size: 14)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(cards) { card in
                        row(for: card)
                    }
                }
                .padding(20)
            }
        }
    }

    private func row(for card: Card) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.text")
                .scaledFont(size: 18)
                .foregroundColor(.secondary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(card.name)
                    .scaledFont(size: 14, weight: .medium)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    if let group = dataService.data.groups.first(where: { $0.id == card.groupId }) {
                        Circle()
                            .fill(Color(hex: group.colorHex))
                            .frame(width: 6, height: 6)
                        Text(group.name)
                            .scaledFont(size: 11)
                            .foregroundColor(.secondary)
                    } else {
                        Text("未分类")
                            .scaledFont(size: 11)
                            .foregroundColor(.secondary)
                    }

                    if let deletedAt = card.deletedAt {
                        Text("· 删除于 \(Self.dateFormatter.string(from: deletedAt))")
                            .scaledFont(size: 11)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            Button(action: { dataService.restoreCard(id: card.id) }) {
                Label("恢复", systemImage: "arrow.uturn.backward")
                    .scaledFont(size: 12)
            }
            .buttonStyle(.bordered)

            Button(action: { dataService.permanentlyDeleteCard(id: card.id) }) {
                Image(systemName: "trash")
                    .scaledFont(size: 12)
                    .foregroundColor(.red.opacity(0.8))
            }
            .buttonStyle(.bordered)
            .help("彻底删除")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
        )
    }
}

// MARK: - 分组卡片列表（支持拖拽排序）

struct GroupCardList: View {
    let groupId: String
    @Binding var cards: [Card]
    let searchText: String
    let selectedCardId: String?
    let onView: (Card) -> Void
    @AppStorage(AppearancePreferences.cardListStyleKey)
    private var cardListStyleRaw = CardListStyle.regular.rawValue

    private var cardListStyle: CardListStyle {
        CardListStyle(rawValue: cardListStyleRaw) ?? .regular
    }

    private var groupCards: Binding<[Card]> {
        Binding(
            get: {
                cards.filter { $0.groupId == groupId && !$0.isTrashed }
            },
            set: { newCards in
                // 保持其他分组的卡片不变，只更新当前分组未删除卡片的顺序
                let otherCards = cards.filter { $0.groupId != groupId }
                let trashedCards = cards.filter { $0.groupId == groupId && $0.isTrashed }
                cards = otherCards + newCards + trashedCards
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
                    .scaledFont(size: 40)
                    .foregroundColor(.secondary.opacity(0.4))
                Text("暂无条目，点击上方「添加条目」开始")
                    .scaledFont(size: 14)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                if cardListStyle == .compact {
                    LazyVStack(spacing: 8) {
                        ForEach(filteredGroupCards) { card in
                            MinimalCardItemView(
                                card: card,
                                dataService: DataService.shared,
                                isSelected: card.id == selectedCardId,
                                onView: { onView(card) },
                                onToggleFavorite: { DataService.shared.toggleFavorite(cardID: card.id) }
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
                } else {
                    LazyVGrid(columns: [
                        GridItem(.adaptive(minimum: 280, maximum: 400), spacing: 14)
                    ], spacing: 14) {
                        ForEach(filteredGroupCards) { card in
                            CardItemView(
                                card: card,
                                dataService: DataService.shared,
                                isSelected: card.id == selectedCardId,
                                onView: { onView(card) },
                                onToggleFavorite: { DataService.shared.toggleFavorite(cardID: card.id) }
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

// MARK: - 极简卡片

struct MinimalCardItemView: View {
    let card: Card
    let dataService: DataService
    var isSelected = false
    let onView: () -> Void
    let onToggleFavorite: () -> Void
    @State private var isHovered = false
    @State private var shareCopied = false

    private var group: Group? {
        dataService.data.groups.first { $0.id == card.groupId }
    }

    private var groupColor: Color {
        group.map { Color(hex: $0.colorHex) } ?? .gray
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: card.isCustom ? "doc.text" : "person.crop.rectangle")
                .scaledFont(size: 17)
                .foregroundColor(.secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 1) {
                Text(card.name)
                    .scaledFont(size: 14, weight: .medium)
                    .lineLimit(1)

                if !card.isCustom, !card.username.isEmpty {
                    Text("账号：\(card.username)")
                        .scaledFont(size: 11)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                HStack(spacing: 5) {
                    Circle()
                        .fill(groupColor)
                        .frame(width: 6, height: 6)
                    Text(group?.name ?? "未分类")
                        .lineLimit(1)
                }
                .scaledFont(size: 11)
                .foregroundColor(.secondary)
            }

            Spacer()

            if isHovered, isShareableTarget {
                Button(action: copySharingText) {
                    Image(systemName: shareCopied ? "checkmark" : "square.and.arrow.up")
                        .scaledFont(size: 11, weight: .medium)
                        .foregroundColor(shareCopied ? .green : .secondary)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .help(shareCopied ? "已复制到剪贴板" : "复制条目信息以供分享")
            }

            Button(action: onToggleFavorite) {
                Image(systemName: card.isFavorited ? "star.fill" : "star")
                    .scaledFont(size: 12, weight: .medium)
                    .foregroundColor(card.isFavorited ? .yellow : .secondary)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .help(card.isFavorited ? "取消收藏" : "收藏")
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 64)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.15), lineWidth: isSelected ? 2 : 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture(perform: onView)
        .onHover { isHovered = $0 }
    }

    private var isShareableTarget: Bool {
        LaunchTarget.isWebAddress(card.url) || LaunchTarget.isApplication(card.url)
    }

    private func copySharingText() {
        let isApplication = LaunchTarget.isApplication(card.url)
        let sharingText = card.sharingText(
            groupName: group?.name,
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
}

// MARK: - 单个卡片

struct CardItemView: View {
    let card: Card
    let dataService: DataService
    var isSelected: Bool = false
    let onView: () -> Void
    let onToggleFavorite: () -> Void
    var showGroupName: Bool = false

    @State private var showPassword = false
    @State private var revealedCustomFieldIDs: Set<String> = []
    @State private var isHovered = false
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
                    .scaledFont(size: 14, weight: .semibold)
                    .lineLimit(1)
                Spacer()
                if showGroupName, let groupName = cardGroupName {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(groupColor)
                            .frame(width: 6, height: 6)
                        Text(groupName)
                            .scaledFont(size: 11)
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
                                .scaledFont(size: 11, weight: .medium)
                                .foregroundColor(shareCopied ? .green : .secondary)
                                .frame(width: 18, height: 18)
                        }
                        .buttonStyle(.plain)
                        .help(shareCopied ? "已复制到剪贴板" : "复制条目信息以供分享")
                    }
                }

                // 收藏星标（始终显示在右上角）
                Button(action: onToggleFavorite) {
                    Image(systemName: card.isFavorited ? "star.fill" : "star")
                        .scaledFont(size: 12, weight: .medium)
                        .foregroundColor(card.isFavorited ? .yellow : .secondary)
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .help(card.isFavorited ? "取消收藏" : "收藏")
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

            // 账号 / 密码（标准）或自定义小项
            if card.isCustom {
                ForEach(card.effectiveCustomFields) { customField in
                    if !customField.value.isEmpty {
                        CardFieldRow(
                            label: customField.label.isEmpty ? "小项" : customField.label,
                            value: customField.value,
                            shortValue: customField.isSecretField
                                ? String(repeating: "•", count: min(customField.value.count, 12))
                                : customField.value,
                            isSecret: customField.isSecretField,
                            showSecret: customField.isSecretField
                                ? revealedCustomFieldBinding(customField.id)
                                : nil
                        )
                    }
                }
            } else {
                if !card.username.isEmpty {
                    CardFieldRow(
                        label: "账号",
                        value: card.username,
                        shortValue: card.username,
                        isSecret: false
                    )
                }

                if !card.password.isEmpty {
                    CardFieldRow(
                        label: "密码",
                        value: card.password,
                        shortValue: showPassword ? card.password : String(repeating: "•", count: min(card.password.count, 12)),
                        isSecret: true,
                        showSecret: $showPassword
                    )
                }
            }

            // 备注
            if !card.note.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text("备注")
                        .scaledFont(size: 10)
                        .foregroundColor(.secondary)
                    Text(card.note)
                        .scaledFont(size: 12)
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
                .stroke(
                    isSelected ? Color.accentColor.opacity(0.9) : groupColor.opacity(0.2),
                    lineWidth: isSelected ? 2 : 1
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onTapGesture { onView() }
        .onHover { hovering in isHovered = hovering }
    }

    private func revealedCustomFieldBinding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { revealedCustomFieldIDs.contains(id) },
            set: { newValue in
                if newValue {
                    revealedCustomFieldIDs.insert(id)
                } else {
                    revealedCustomFieldIDs.remove(id)
                }
            }
        )
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
                .scaledFont(size: 10)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .frame(minWidth: 34, alignment: .leading)

            if isLaunchTarget {
                Button(action: { LaunchTarget.open(value, cardID: launchCardID) }) {
                    HStack(spacing: 5) {
                        Image(systemName: LaunchTarget.isApplication(value) ? "app" : "safari")
                            .scaledFont(size: 10)
                        Text(shortValue)
                            .scaledFont(size: 12)
                            .lineLimit(1)
                    }
                    .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
                .help(value)
            } else {
                Text(isSecret == true && (showSecret?.wrappedValue == false) ? shortValue : value)
                    .scaledFont(size: 12, design: .monospaced)
                    .foregroundColor(.primary)
                    .lineLimit(1)
            }

            Spacer()

            // 复制按钮
            Button(action: { copyToClipboard(value) }) {
                Image(systemName: "doc.on.doc")
                    .scaledFont(size: 10)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("复制 \(label)")

            // 显示/隐藏密码按钮
            if isSecret, let showBinding = showSecret {
                Button(action: { showBinding.wrappedValue.toggle() }) {
                    Image(systemName: showBinding.wrappedValue ? "eye.slash" : "eye")
                        .scaledFont(size: 10)
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

// MARK: - 条目查看（只读）

struct CardDetailView: View {
    let card: Card
    let dataService: DataService
    var embedded: Bool = false
    let onClose: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var showPassword = false
    @State private var revealedCustomFieldIDs: Set<String> = []
    @State private var showDeleteConfirm = false

    private var group: Group? {
        dataService.data.groups.first { $0.id == card.groupId }
    }

    private var groupColor: Color {
        group.map { Color(hex: $0.colorHex) } ?? .gray
    }

    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            HStack(spacing: 10) {
                if group != nil {
                    Circle()
                        .fill(groupColor)
                        .frame(width: 10, height: 10)
                }

                Text(card.name)
                    .scaledFont(size: 16, weight: .semibold)
                    .lineLimit(1)

                if card.isFavorited {
                    Image(systemName: "star.fill")
                        .scaledFont(size: 12)
                        .foregroundColor(.yellow)
                }

                Spacer()

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .scaledFont(size: 13, weight: .medium)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 14)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let group {
                        field(label: "分组", value: group.name, copyable: false)
                    }

                    if !card.url.isEmpty {
                        urlField
                    }

                    if card.isCustom {
                        ForEach(card.effectiveCustomFields) { customField in
                            if !customField.value.isEmpty {
                                if customField.isSecretField {
                                    secretField(
                                        label: customField.label.isEmpty ? "小项" : customField.label,
                                        value: customField.value,
                                        revealed: revealedCustomFieldIDs.contains(customField.id),
                                        toggle: { toggleCustomFieldReveal(customField.id) }
                                    )
                                } else {
                                    field(
                                        label: customField.label.isEmpty ? "小项" : customField.label,
                                        value: customField.value
                                    )
                                }
                            }
                        }
                    } else {
                        if !card.username.isEmpty {
                            field(label: "账号", value: card.username)
                        }

                        if !card.password.isEmpty {
                            passwordField
                        }
                    }

                    if !card.note.isEmpty {
                        noteField
                    }
                }
                .padding(20)
            }

            Divider()

            HStack(spacing: 10) {
                Button(role: .destructive, action: { showDeleteConfirm = true }) {
                    Label("删除", systemImage: "trash")
                        .scaledFont(size: 13)
                }
                .buttonStyle(.bordered)

                Button(action: onEdit) {
                    Label("编辑", systemImage: "pencil")
                        .scaledFont(size: 13)
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("关闭", action: onClose)
                    .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .frame(width: embedded ? nil : 460, height: embedded ? nil : 440)
        .frame(maxWidth: embedded ? .infinity : nil, maxHeight: embedded ? .infinity : nil)
        .alert("移入回收站", isPresented: $showDeleteConfirm) {
            Button("取消", role: .cancel) {}
            Button("移入回收站", role: .destructive) { onDelete() }
        } message: {
            Text("确定要将「\(card.name)」移入回收站吗？之后可从回收站恢复。")
        }
        .appFontSizeScaled()
    }

    private func field(label: String, value: String, copyable: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .scaledFont(size: 11, weight: .medium)
                .foregroundColor(.secondary)

            HStack(spacing: 8) {
                Text(value)
                    .scaledFont(size: 13)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if copyable {
                    Button(action: { Clipboard.copy(value) }) {
                        Image(systemName: "doc.on.doc")
                            .scaledFont(size: 11)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("复制\(label)")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.secondary.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 7))
        }
    }

    private var urlField: some View {
        let isApplication = LaunchTarget.isApplication(card.url)
        return VStack(alignment: .leading, spacing: 6) {
            Text(isApplication ? "应用" : "地址")
                .scaledFont(size: 11, weight: .medium)
                .foregroundColor(.secondary)

            HStack(spacing: 8) {
                Button(action: { LaunchTarget.open(card.url, cardID: card.id) }) {
                    HStack(spacing: 5) {
                        Image(systemName: isApplication ? "app" : "safari")
                            .scaledFont(size: 11)
                        Text(LaunchTarget.displayName(for: card.url, dataService: dataService))
                            .scaledFont(size: 13)
                            .lineLimit(1)
                    }
                    .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
                .help(card.url)

                Spacer()

                Button(action: { Clipboard.copy(card.url) }) {
                    Image(systemName: "doc.on.doc")
                        .scaledFont(size: 11)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("复制地址")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.secondary.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 7))
        }
    }

    private var passwordField: some View {
        secretField(
            label: "密码",
            value: card.password,
            revealed: showPassword,
            toggle: { showPassword.toggle() }
        )
    }

    private func toggleCustomFieldReveal(_ id: String) {
        if revealedCustomFieldIDs.contains(id) {
            revealedCustomFieldIDs.remove(id)
        } else {
            revealedCustomFieldIDs.insert(id)
        }
    }

    private func secretField(label: String, value: String, revealed: Bool, toggle: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .scaledFont(size: 11, weight: .medium)
                .foregroundColor(.secondary)

            HStack(spacing: 8) {
                Text(revealed ? value : String(repeating: "•", count: min(max(value.count, 6), 12)))
                    .scaledFont(size: 13, design: .monospaced)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button(action: toggle) {
                    Image(systemName: revealed ? "eye.slash" : "eye")
                        .scaledFont(size: 11)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help(revealed ? "隐藏内容" : "显示内容")

                Button(action: { Clipboard.copy(value) }) {
                    Image(systemName: "doc.on.doc")
                        .scaledFont(size: 11)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("复制\(label)")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.secondary.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 7))
        }
    }

    private var noteField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("备注")
                .scaledFont(size: 11, weight: .medium)
                .foregroundColor(.secondary)

            Text(card.note)
                .scaledFont(size: 13)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.secondary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 7))
        }
    }
}

// MARK: - 设置页

private enum SettingsPage: String, CaseIterable, Identifiable {
    case general = "通用"
    case appearance = "外观"
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
    @State private var showBindFile = false
    @StateObject private var launchAtLoginService = LaunchAtLoginService()
    @AppStorage(CredentialPanelPreferences.isEnabledKey)
    private var credentialPanelEnabled = true
    @AppStorage(PasswordInputPreferences.forcesRomanInputKey)
    private var forcesRomanPasswordInput = false
    @AppStorage(AppearancePreferences.fontSizeLevelKey)
    private var fontSizeLevelRaw = AppFontSizeLevel.standard.rawValue
    @AppStorage(AppearancePreferences.cardListStyleKey)
    private var cardListStyleRaw = CardListStyle.regular.rawValue
    @AppStorage(PresentationPreferences.modeKey)
    private var presentationModeRaw = CardPresentationMode.popup.rawValue
    @State private var autoDismissSecondsText = String(CredentialPanelPreferences.autoDismissSeconds)

    private var fontSizeLevel: Binding<AppFontSizeLevel> {
        Binding(
            get: { AppFontSizeLevel(rawValue: fontSizeLevelRaw) ?? .standard },
            set: { fontSizeLevelRaw = $0.rawValue }
        )
    }

    private var presentationMode: Binding<CardPresentationMode> {
        Binding(
            get: { CardPresentationMode(rawValue: presentationModeRaw) ?? .popup },
            set: { presentationModeRaw = $0.rawValue }
        )
    }

    private var cardListStyle: Binding<CardListStyle> {
        Binding(
            get: { CardListStyle(rawValue: cardListStyleRaw) ?? .regular },
            set: { cardListStyleRaw = $0.rawValue }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            HStack {
                Text("设置")
                    .scaledFont(size: 16, weight: .semibold)
                Spacer()
                Button(action: { isPresented = false }) {
                    Image(systemName: "xmark")
                        .scaledFont(size: 13, weight: .medium)
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
                case .appearance:
                    appearanceSettings
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
        .sheet(isPresented: $showBindFile) {
            BindFileView(isPresented: $showBindFile)
        }
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

    private var appearanceSettings: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {

                // ── 条目展示 ──
                SectionHeader(title: "条目展示")

                HStack(spacing: 14) {
                    Image(systemName: "rectangle.split.3x1")
                        .scaledFont(size: 25)
                        .foregroundColor(.blue)
                        .frame(width: 34)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("展示模式")
                            .scaledFont(size: 13, weight: .medium)
                        Text(presentationMode.wrappedValue.detailDescription)
                            .scaledFont(size: 11)
                            .foregroundColor(.secondary)
                    }

                    Spacer(minLength: 12)

                    Picker("", selection: presentationMode) {
                        ForEach(CardPresentationMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 180)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)

                Divider().padding(.horizontal, 20)

                HStack(spacing: 14) {
                    Image(systemName: "rectangle.grid.1x2")
                        .scaledFont(size: 25)
                        .foregroundColor(.blue)
                        .frame(width: 34)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("分类卡片样式")
                            .scaledFont(size: 13, weight: .medium)
                        Text(cardListStyle.wrappedValue == .compact ? "紧凑显示名称与账号等摘要" : "显示条目的完整卡片内容")
                            .scaledFont(size: 11)
                            .foregroundColor(.secondary)
                    }

                    Spacer(minLength: 12)

                    Picker("", selection: cardListStyle) {
                        ForEach(CardListStyle.allCases) { style in
                            Text(style.displayName).tag(style)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 180)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)

                Divider().padding(.horizontal, 20)

                // ── 字体大小 ──
                SectionHeader(title: "字体大小")

                HStack(spacing: 14) {
                    Image(systemName: "textformat.size")
                        .scaledFont(size: 25)
                        .foregroundColor(.blue)
                        .frame(width: 34)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("界面字体大小")
                            .scaledFont(size: 13, weight: .medium)
                        Text("调整整个应用的文字大小，即时生效")
                            .scaledFont(size: 11)
                            .foregroundColor(.secondary)
                    }

                    Spacer(minLength: 12)

                    Picker("", selection: fontSizeLevel) {
                        ForEach(AppFontSizeLevel.allCases) { level in
                            Text(level.displayName).tag(level)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 216)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)

                Divider().padding(.horizontal, 20)

                // ── 预览 ──
                SectionHeader(title: "预览")

                VStack(alignment: .leading, spacing: 8) {
                    Text("账号名称")
                        .scaledFont(size: 14, weight: .semibold)
                    Text("example@xrecord.app")
                        .scaledFont(size: 12)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(Color.secondary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
            }
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
                            .scaledFont(size: 15, weight: .semibold)
                        Text("版本 \(updateService.currentVersion)")
                            .scaledFont(size: 12)
                            .foregroundColor(.secondary)
                        Text("简洁优雅的密码管理工具")
                            .scaledFont(size: 11)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)

                Divider().padding(.horizontal, 20)

                // ── 数据文件 ──
                SectionHeader(title: "数据文件")

                HStack(spacing: 14) {
                    Image(systemName: "doc.text")
                        .scaledFont(size: 25)
                        .foregroundColor(.blue)
                        .frame(width: 34)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("当前数据文件")
                            .scaledFont(size: 13, weight: .medium)
                        Text(dataService.filePathDisplay)
                            .scaledFont(size: 11)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        HStack(spacing: 5) {
                            if dataService.fileAvailability == .downloading {
                                ProgressView()
                                    .controlSize(.mini)
                            } else {
                                Image(systemName: fileAvailabilityIcon)
                            }
                            Text(dataService.fileAvailability.description)
                        }
                        .scaledFont(size: 10)
                        .foregroundColor(fileAvailabilityColor)

                        if let conflictNotice = dataService.conflictNotice {
                            Label(conflictNotice, systemImage: "exclamationmark.triangle.fill")
                                .scaledFont(size: 10)
                                .foregroundColor(.orange)
                        }
                    }

                    Spacer(minLength: 12)

                    Button("绑定文件") { showBindFile = true }
                        .buttonStyle(.bordered)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)

                Divider().padding(.horizontal, 20)

                // ── 启动 ──
                SectionHeader(title: "启动")

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 14) {
                        Image(systemName: "power")
                            .scaledFont(size: 25)
                            .foregroundColor(.blue)
                            .frame(width: 34)

                        VStack(alignment: .leading, spacing: 3) {
                            Text("开机自动启动 XRecord")
                                .scaledFont(size: 13, weight: .medium)
                            Text("登录 Mac 后自动运行 XRecord")
                                .scaledFont(size: 11)
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
                                .scaledFont(size: 11)
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
                        .scaledFont(size: 25)
                        .foregroundColor(.blue)
                        .frame(width: 34)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("打开目标后显示凭据浮窗")
                            .scaledFont(size: 13, weight: .medium)
                        Text("作为总开关；还会遵循每个条目的独立设置")
                            .scaledFont(size: 11)
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
                        .scaledFont(size: 13)
                    TextField("", text: $autoDismissSecondsText)
                        .textFieldStyle(.roundedBorder)
                        .scaledFont(size: 13)
                        .multilineTextAlignment(.center)
                        .frame(width: 56)
                        .onChange(of: autoDismissSecondsText) { newValue in
                            let trimmed = newValue.trimmingCharacters(in: .whitespaces)
                            guard !trimmed.isEmpty, let seconds = Int(trimmed) else { return }
                            CredentialPanelPreferences.setAutoDismissSeconds(seconds)
                        }
                    Text("秒后自动消失")
                        .scaledFont(size: 13)
                    Text("（-1 表示不消失）")
                        .scaledFont(size: 11)
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
                        .scaledFont(size: 25)
                        .foregroundColor(.blue)
                        .frame(width: 34)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("密码框始终使用英文输入")
                            .scaledFont(size: 13, weight: .medium)
                        Text("开启后，输入密码时自动使用英文键盘，仍可输入数字和符号")
                            .scaledFont(size: 11)
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
                            .scaledFont(size: 13, weight: .medium)
                        Text(preferredBrowserDescription)
                            .scaledFont(size: 11)
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
                            .scaledFont(size: 12)
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
                                .scaledFont(size: 13)
                            Text("由 Sparkle 安全下载、安装并重新启动")
                                .scaledFont(size: 11)
                                .foregroundColor(.secondary)
                        }
                        Spacer()

                        Button(action: { updateService.checkForUpdates() }) {
                            Label("检查更新", systemImage: "arrow.clockwise")
                                .scaledFont(size: 12)
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
                    .scaledFont(size: 12)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)

                Divider().padding(.horizontal, 20)

                // ── 数据安全 ──
                SectionHeader(title: "数据安全")

                HStack(spacing: 14) {
                    Image(systemName: "key.horizontal.fill")
                        .scaledFont(size: 25)
                        .foregroundColor(.blue)
                        .frame(width: 34)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("同步与恢复口令")
                            .scaledFont(size: 13, weight: .medium)
                        Text(dataService.hasMigrationPassphrase
                             ? "已设置，可在其他 Mac 解锁同步或复制的数据文件"
                             : "未设置，其他 Mac 无法解锁此密码本")
                            .scaledFont(size: 11)
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
                            .scaledFont(size: 13)
                        Text("查看源码和提交反馈")
                            .scaledFont(size: 11)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button(action: {
                        NSWorkspace.shared.open(URL(string: "https://github.com/juiceiie/XRecord")!)
                    }) {
                        Label("打开", systemImage: "arrow.up.right.square")
                            .scaledFont(size: 12)
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

    private var fileAvailabilityIcon: String {
        switch dataService.fileAvailability {
        case .unbound: return "questionmark.circle"
        case .local: return "checkmark.circle.fill"
        case .iCloudAvailable: return "checkmark.icloud.fill"
        case .downloading: return "icloud.and.arrow.down"
        case .unavailable: return "exclamationmark.triangle.fill"
        }
    }

    private var fileAvailabilityColor: Color {
        switch dataService.fileAvailability {
        case .unavailable: return .orange
        case .downloading: return .blue
        case .unbound: return .secondary
        case .local, .iCloudAvailable: return .green
        }
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
        titleOverride ?? (hasExisting ? "修改同步与恢复口令" : "设置同步与恢复口令")
    }

    private var intro: String {
        introOverride ?? "设置后，通过 iCloud Drive 同步或复制到其他 Mac 的数据文件可用此口令解锁。口令不会被保存，请务必牢记。"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .scaledFont(size: 16, weight: .semibold)
                Spacer()
                Button(action: { isPresented = false }) {
                    Image(systemName: "xmark")
                        .scaledFont(size: 13, weight: .medium)
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
                    .scaledFont(size: 12)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                SecureField("同步与恢复口令（至少 6 位）", text: $passphrase)
                    .textFieldStyle(.roundedBorder)
                SecureField("确认同步与恢复口令", text: $confirm)
                    .textFieldStyle(.roundedBorder)

                if let errorMessage {
                    Text(errorMessage)
                        .scaledFont(size: 11)
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
                        .scaledFont(size: 30)
                        .foregroundStyle(.blue, .blue.opacity(0.18))

                    VStack(alignment: .leading, spacing: 4) {
                        Text("快速检索")
                            .scaledFont(size: 14, weight: .semibold)
                        Text("在任意应用中唤起 XRecord 搜索窗口")
                            .scaledFont(size: 11)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 8) {
                        Toggle(
                            "启用",
                            isOn: Binding(
                                get: { hotKeyService.isEnabled },
                                set: { hotKeyService.setEnabled($0) }
                            )
                        )
                        .toggleStyle(.switch)
                        .scaledFont(size: 11)

                        ShortcutRecorderView(service: hotKeyService)
                            .disabled(!hotKeyService.isEnabled)
                            .opacity(hotKeyService.isEnabled ? 1 : 0.5)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)

                Divider().padding(.horizontal, 20)

                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("恢复默认")
                            .scaledFont(size: 13)
                        Text("默认快捷键为 ⌥X")
                            .scaledFont(size: 11)
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
                    .scaledFont(size: 13, weight: .medium, design: .rounded)
                    .frame(minWidth: 86)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            if let errorMessage {
                Text(errorMessage)
                    .scaledFont(size: 10)
                    .foregroundColor(.red)
            } else if isRecording {
                Text("按 Esc 取消")
                    .scaledFont(size: 10)
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
            .scaledFont(size: 11, weight: .semibold)
            .foregroundColor(.secondary)
            .textCase(.uppercase)
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 6)
    }
}
