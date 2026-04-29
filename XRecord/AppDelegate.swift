import AppKit
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    // 使用 strong reference 确保 window 不会被释放
    private var mainWindow: NSWindow?
    // 使用自定义标志追踪窗口可见性（避免调用 isVisible）
    private var isWindowShown = true

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // 点击 Dock 图标时，如果窗口不可见则显示
        if !flag || mainWindow == nil || !mainWindow!.isVisible {
            showMainWindow()
        }
        return true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("[XRecord] 🚀 applicationDidFinishLaunching 开始")
        
        // 创建主窗口（保持强引用）
        setupMainWindow()
        
        // 设置主菜单
        setupMainMenu()
        
        // 启动后延迟 3 秒检查更新
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            Task { @MainActor in
                UpdateService.shared.checkForUpdates()
            }
        }
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

    // MARK: - 窗口控制

    @objc func toggleMainWindow() {
        guard let window = mainWindow else { return }

        if window.isVisible {
            window.orderOut(nil)
        } else {
            window.deminiaturize(nil)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    @objc func showMainWindow() {
        guard let window = mainWindow else { return }
        
        window.deminiaturize(nil)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func hideMainWindow() {
        mainWindow?.orderOut(nil)
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
        // 用户点击关闭按钮时，不需要额外处理
        // 点击 Dock 图标会通过 applicationShouldHandleReopen 重新打开
    }
}

extension Notification.Name {
    static let openAddGroup = Notification.Name("openAddGroup")
    static let openAddCard = Notification.Name("openAddCard")
}
