import AppKit
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    // 使用 strong reference 确保 window 不会被释放
    private var mainWindow: NSWindow?
    // 状态栏对象必须保持强引用，否则图标会被系统移除
    private var statusItem: NSStatusItem?
    private var quickViewMenu: NSMenu?
    private var quickSearchController: QuickSearchWindowController?
    private var credentialPanelController: CredentialPanelController?

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // 点击 Dock 图标时，如果窗口不可见则显示
        if !flag || mainWindow == nil || !mainWindow!.isVisible {
            showMainWindow()
        }
        return true
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        guard let path = filenames.first else {
            sender.reply(toOpenOrPrint: .failure)
            return
        }

        let url = URL(fileURLWithPath: path)
        let supportedExtensions = ["xrecord", "txt"]
        guard supportedExtensions.contains(url.pathExtension.lowercased()) else {
            sender.reply(toOpenOrPrint: .failure)
            return
        }

        if DataService.shared.bind(to: url) {
            showMainWindow()
            DataService.shared.offerLegacyExtensionMigrationIfNeeded()
            sender.reply(toOpenOrPrint: .success)
        } else {
            sender.reply(toOpenOrPrint: .failure)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("[XRecord] 🚀 applicationDidFinishLaunching 开始")
        
        // 创建主窗口（保持强引用）
        setupMainWindow()
        
        // 设置主菜单
        setupMainMenu()

        // 设置常驻菜单栏图标
        setupStatusItem()

        // 注册全局快速检索快捷键
        quickSearchController = QuickSearchWindowController(dataService: DataService.shared)
        GlobalHotKeyService.shared.onHotKey = { [weak self] in
            self?.quickSearchController?.toggle()
        }
        GlobalHotKeyService.shared.start()

        credentialPanelController = CredentialPanelController()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(showCredentialPanel(_:)),
            name: .didOpenLaunchTarget,
            object: nil
        )

        DispatchQueue.main.async {
            DataService.shared.offerLegacyExtensionMigrationIfNeeded()
        }
        
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        NotificationCenter.default.removeObserver(self)
        credentialPanelController?.hide()
        quickSearchController?.hide()
        GlobalHotKeyService.shared.onHotKey = nil
        GlobalHotKeyService.shared.suspend()
    }

    private func setupMainWindow() {
        let contentView = ContentView()
            .environmentObject(DataService.shared)

        mainWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        mainWindow?.minSize = NSSize(width: 700, height: 450)
        mainWindow?.center()
        mainWindow?.title = "XRecord"
        mainWindow?.contentView = NSHostingView(rootView: contentView)
        mainWindow?.makeKeyAndOrderFront(nil)
        mainWindow?.delegate = self
        // 关键：防止窗口关闭后被释放，避免 EXC_BAD_ACCESS
        mainWindow?.isReleasedWhenClosed = false
    }

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        // 应用菜单
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "关于 XRecord", action: #selector(showAbout), keyEquivalent: ""))
        appMenu.addItem(NSMenuItem(title: "检查更新…", action: #selector(checkForUpdates), keyEquivalent: ""))
        appMenu.addItem(NSMenuItem.separator())
        let settingsItem = NSMenuItem(title: "设置…", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        appMenu.addItem(settingsItem)
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(NSMenuItem(title: "隐藏 XRecord", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"))
        appMenu.addItem(NSMenuItem(title: "隐藏其他应用", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: ""))
        appMenu.addItem(NSMenuItem(title: "显示所有应用", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: ""))
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(NSMenuItem(title: "退出 XRecord", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // 文件菜单
        let fileMenuItem = NSMenuItem()
        let fileMenu = NSMenu(title: "文件")
        let quickSearchItem = NSMenuItem(title: "快速检索…", action: #selector(showQuickSearch), keyEquivalent: "")
        quickSearchItem.target = self
        fileMenu.addItem(quickSearchItem)
        fileMenu.addItem(NSMenuItem.separator())
        fileMenu.addItem(NSMenuItem(title: "新建分组", action: #selector(addGroupAction), keyEquivalent: "n"))
        fileMenu.addItem(NSMenuItem(title: "添加条目", action: #selector(addCardAction), keyEquivalent: "N"))
        fileMenu.addItem(NSMenuItem.separator())
        fileMenu.addItem(NSMenuItem(title: "重置所有数据", action: #selector(resetAll), keyEquivalent: ""))
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        // 编辑菜单
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(NSMenuItem(title: "撤销", action: Selector(("undo:")), keyEquivalent: "z"))
        editMenu.addItem(NSMenuItem(title: "重做", action: Selector(("redo:")), keyEquivalent: "Z"))
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(NSMenuItem(title: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        // 窗口菜单
        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: "窗口")
        windowMenu.addItem(NSMenuItem(title: "最小化", action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m"))
        windowMenu.addItem(NSMenuItem(title: "缩放", action: #selector(NSWindow.zoom(_:)), keyEquivalent: ""))
        windowMenu.addItem(NSMenuItem.separator())
        windowMenu.addItem(NSMenuItem(title: "显示主窗口", action: #selector(toggleMainWindow), keyEquivalent: "1"))
        windowMenu.addItem(NSMenuItem(title: "置顶", action: #selector(toggleFloating), keyEquivalent: "t"))
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)

        NSApp.mainMenu = mainMenu
        
        // 设置窗口菜单为 macOS 的标准窗口菜单
        NSApp.windowsMenu = windowMenu
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            let image = NSImage(named: "MenuBarIcon")
            image?.isTemplate = true
            image?.size = NSSize(width: 18, height: 18)
            button.image = image
            button.toolTip = "XRecord"
        }

        let menu = NSMenu()

        let showItem = NSMenuItem(
            title: "显示主面板",
            action: #selector(showMainWindow),
            keyEquivalent: ""
        )
        showItem.target = self
        menu.addItem(showItem)

        let settingsItem = NSMenuItem(
            title: "设置…",
            action: #selector(showSettings),
            keyEquivalent: ""
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        let quickSearchItem = NSMenuItem(
            title: "快速检索…",
            action: #selector(showQuickSearch),
            keyEquivalent: ""
        )
        quickSearchItem.target = self
        menu.addItem(quickSearchItem)

        let quickViewItem = NSMenuItem(title: "快速查看", action: nil, keyEquivalent: "")
        let quickMenu = NSMenu(title: "快速查看")
        quickMenu.delegate = self
        quickViewItem.submenu = quickMenu
        menu.addItem(quickViewItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(
            title: "退出 XRecord",
            action: #selector(quitApplication),
            keyEquivalent: ""
        )
        quitItem.target = self
        menu.addItem(quitItem)

        item.menu = menu
        quickViewMenu = quickMenu
        statusItem = item
    }

    // MARK: - 窗口控制

    @MainActor @objc private func checkForUpdates() {
        UpdateService.shared.checkForUpdates()
    }

    @objc func toggleMainWindow() {
        guard let window = mainWindow else { return }

        if window.isVisible {
            window.orderOut(nil)
            enterAccessoryMode()
        } else {
            enterRegularMode()
            window.deminiaturize(nil)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    @objc func showMainWindow() {
        guard let window = mainWindow else { return }
        
        enterRegularMode()
        window.deminiaturize(nil)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func hideMainWindow() {
        mainWindow?.orderOut(nil)
        enterAccessoryMode()
    }

    /// 显示主窗口时恢复 Dock 图标与顶部菜单栏
    private func enterRegularMode() {
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
        }
    }

    /// 关闭主窗口后仅保留菜单栏图标，隐藏 Dock 图标
    private func enterAccessoryMode() {
        if NSApp.activationPolicy() != .accessory {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    @objc func toggleFloating() {
        guard let window = mainWindow else { return }
        
        if window.level == .floating {
            window.level = .normal
        } else {
            window.level = .floating
        }
    }

    @objc func showAbout() {
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    @objc private func quitApplication() {
        NSApp.terminate(nil)
    }

    @objc private func showQuickSearch() {
        quickSearchController?.show()
    }

    @objc private func showSettings() {
        showMainWindow()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NotificationCenter.default.post(name: .openSettings, object: nil)
        }
    }

    @objc private func showCredentialPanel(_ notification: Notification) {
        guard CredentialPanelPreferences.isEnabled,
              let cardID = notification.object as? String,
              let card = DataService.shared.data.cards.first(where: { $0.id == cardID }),
              card.isCredentialPanelEnabled else {
            return
        }
        let group = DataService.shared.data.groups.first(where: { $0.id == card.groupId })
        credentialPanelController?.show(
            card: card,
            groupName: group?.name ?? "未分类",
            groupColorHex: group?.colorHex ?? "#4f6ef7"
        )
    }

    // MARK: - 数据操作

    @objc func addGroupAction() {
        showMainWindow()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NotificationCenter.default.post(name: .openAddGroup, object: nil)
        }
    }

    @objc func addCardAction() {
        showMainWindow()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NotificationCenter.default.post(name: .openAddCard, object: nil)
        }
    }

    @objc private func quickView(_ sender: NSMenuItem) {
        guard let groupId = sender.representedObject as? String,
              DataService.shared.data.groups.contains(where: { $0.id == groupId }) else {
            return
        }

        showMainWindow()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NotificationCenter.default.post(name: .selectGroup, object: groupId)
        }
    }

    @objc func resetAll() {
        let alert = NSAlert()
        alert.messageText = "⚠️ 确定要清除所有数据吗？"
        alert.informativeText = "此操作不可恢复，将删除所有分组和条目数据。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "确定重置")
        alert.addButton(withTitle: "取消")

        if alert.runModal() == .alertFirstButtonReturn {
            DataService.shared.resetAll()
        }
    }
}

// MARK: - NSWindowDelegate

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        // 关闭主窗口后隐藏 Dock 图标，仅保留菜单栏常驻图标
        // 点击菜单栏图标会通过 showMainWindow 恢复显示
        enterAccessoryMode()
    }
}

// MARK: - NSMenuDelegate

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === quickViewMenu else { return }

        menu.removeAllItems()

        guard DataService.shared.hasBoundFile else {
            let item = NSMenuItem(title: "请先绑定数据文件", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
            return
        }

        let groups = DataService.shared.data.groups
        guard !groups.isEmpty else {
            let item = NSMenuItem(title: "暂无分类", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
            return
        }

        for group in groups {
            let item = NSMenuItem(
                title: group.name,
                action: #selector(quickView(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = group.id
            menu.addItem(item)
        }
    }
}

extension Notification.Name {
    static let openAddGroup = Notification.Name("openAddGroup")
    static let openAddCard = Notification.Name("openAddCard")
    static let selectGroup = Notification.Name("selectGroup")
    static let openSettings = Notification.Name("openSettings")
    static let didOpenLaunchTarget = Notification.Name("didOpenLaunchTarget")
}
