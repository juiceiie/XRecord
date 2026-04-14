import AppKit
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow?
    var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 创建主窗口
        let contentView = ContentView()
            .environmentObject(DataService.shared)

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window?.minSize = NSSize(width: 700, height: 450)
        window?.center()
        window?.title = "XRecord"
        window?.contentView = NSHostingView(rootView: contentView)
        window?.makeKeyAndOrderFront(nil)

        // 设置 Menu Bar 状态栏图标
        setupStatusBar()

        // 设置主菜单
        setupMainMenu()

        // 显示 Dock 图标（设为 false 则在 Dock 中隐藏）
        NSApp.setActivationPolicy(.accessory)
    }

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "doc.text", accessibilityDescription: "XRecord")
            button.image?.isTemplate = true
        }

        let menu = NSMenu()

        menu.addItem(NSMenuItem(title: "显示主窗口", action: #selector(showWindow), keyEquivalent: "o"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "新建分组", action: #selector(addGroup), keyEquivalent: "n"))
        menu.addItem(NSMenuItem(title: "添加条目", action: #selector(addCard), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "重置所有数据", action: #selector(resetAll), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem?.menu = menu
    }

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        // 应用菜单
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "关于 XRecord", action: #selector(showAbout), keyEquivalent: ""))
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(NSMenuItem(title: "隐藏窗口", action: #selector(hideWindow), keyEquivalent: "h"))
        appMenu.addItem(NSMenuItem(title: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // 文件菜单
        let fileMenuItem = NSMenuItem()
        let fileMenu = NSMenu(title: "文件")
        fileMenu.addItem(NSMenuItem(title: "新建分组", action: #selector(addGroup), keyEquivalent: "n"))
        fileMenu.addItem(NSMenuItem(title: "添加条目", action: #selector(addCard), keyEquivalent: "N"))
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
        windowMenu.addItem(NSMenuItem(title: "显示主窗口", action: #selector(showWindow), keyEquivalent: "1"))
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)

        NSApp.mainMenu = mainMenu
    }

    @objc func showWindow() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func hideWindow() {
        window?.orderOut(nil)
    }

    @objc func showAbout() {
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    @objc func addGroup() {
        showWindow()
        NotificationCenter.default.post(name: .openAddGroup, object: nil)
    }

    @objc func addCard() {
        showWindow()
        NotificationCenter.default.post(name: .openAddCard, object: nil)
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

extension Notification.Name {
    static let openAddGroup = Notification.Name("openAddGroup")
    static let openAddCard = Notification.Name("openAddCard")
}
