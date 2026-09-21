import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - 条目编辑弹窗

struct CardEditView: View {
    @EnvironmentObject var dataService: DataService
    @Binding var isPresented: Bool
    let editingCard: Card?
    var groupId: String?
    var showsHeader: Bool = true

    @State private var name: String = ""
    @State private var url: String = ""
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var note: String = ""
    @State private var showPassword: Bool = false
    @State private var currentEditingId: String? = nil
    @State private var showGroupError: Bool = false
    @State private var showsCredentialPanel: Bool = true
    @AppStorage(CredentialPanelPreferences.isEnabledKey)
    private var credentialPanelEnabled = true
    @AppStorage(PasswordInputPreferences.forcesRomanInputKey)
    private var forcesRomanPasswordInput = false

    var isEditing: Bool { editingCard != nil }
    
    // 获取当前绑定的分组名称
    private var groupName: String {
        if let gid = groupId, let group = dataService.data.groups.first(where: { $0.id == gid }) {
            return group.name
        }
        return "未分组"
    }

    var body: some View {
        VStack(spacing: 0) {
            if showsHeader {
                // Sheet 模式使用自定义标题栏；独立窗口使用 macOS 原生标题栏。
                HStack {
                    Text(isEditing ? "编辑条目" : "添加条目")
                        .font(.system(size: 16, weight: .semibold))
                    Spacer()
                    if !isEditing {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color(hex: dataService.data.groups.first(where: { $0.id == groupId })?.colorHex ?? "#888888"))
                                .frame(width: 8, height: 8)
                            Text(groupName)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(Capsule())
                    }
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
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // 名称
                    FormFieldInput(label: "名称", placeholder: "例如：后台管理系统", text: $name, required: true)

                    // 网址或本机应用
                    LaunchTargetInput(text: $url)

                    // 账号密码
                    HStack(spacing: 14) {
                        FormFieldInput(label: "账号", placeholder: "username", text: $username)
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("密码")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.secondary)
                            }
                            HStack {
                                LastCharacterSecureField(
                                    text: $password,
                                    revealsText: showPassword,
                                    forcesRomanInput: forcesRomanPasswordInput
                                )
                                .frame(height: 22)

                                Button(action: { showPassword.toggle() }) {
                                    Image(systemName: showPassword ? "eye.slash" : "eye")
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }

                    if credentialPanelEnabled {
                        HStack(spacing: 12) {
                            Image(systemName: "rectangle.on.rectangle")
                                .font(.system(size: 18))
                                .foregroundColor(.blue)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("打开后显示凭据浮窗")
                                    .font(.system(size: 12, weight: .medium))
                                Text("需同时开启设置中的全局开关")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Toggle("", isOn: $showsCredentialPanel)
                                .labelsHidden()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color.secondary.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                    }

                    // 备注
                    VStack(alignment: .leading, spacing: 6) {
                        Text("备注")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                        TextEditor(text: $note)
                            .font(.system(size: 14))
                            .frame(minHeight: 70)
                            .padding(6)
                            .background(Color(nsColor: .textBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                            )
                    }
                }
                .padding(20)
            }

            Divider()

            // 底部按钮
            HStack(spacing: 10) {
                Button("取消") { isPresented = false }
                    .buttonStyle(.bordered)
                Spacer()
                Button(isEditing ? "保存" : "添加") {
                    save()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .frame(width: 500, height: showsHeader ? 480 : 430)
        .alert("请先选择一个分组", isPresented: $showGroupError) {
            Button("确定") { isPresented = false }
        } message: {
            Text("添加条目前请先在左侧选择一个分组，或者点击「全部」后使用第一个分组。")
        }
        .onAppear {
            if let c = editingCard {
                currentEditingId = c.id
                name = c.name
                url = c.url
                username = c.username
                password = c.password
                note = c.note
                showsCredentialPanel = c.isCredentialPanelEnabled
            } else {
                currentEditingId = nil
                name = ""
                url = ""
                username = ""
                password = ""
                note = ""
                showsCredentialPanel = true
            }
        }
        .onDisappear { currentEditingId = nil }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }
        guard let gid = groupId else {
            // 如果没有分组，提示用户先选择分组
            showGroupError = true
            return
        }

        if let editId = currentEditingId,
           let existing = dataService.data.cards.first(where: { $0.id == editId }) {
            var c = existing
            c.name = trimmedName
            c.url = url.trimmingCharacters(in: .whitespaces)
            c.username = username.trimmingCharacters(in: .whitespaces)
            c.password = password
            c.note = note.trimmingCharacters(in: .whitespaces)
            c.showsCredentialPanel = showsCredentialPanel
            dataService.updateCard(c)
        } else {
            let newCard = Card(
                groupId: gid,
                name: trimmedName,
                url: url.trimmingCharacters(in: .whitespaces),
                username: username.trimmingCharacters(in: .whitespaces),
                password: password,
                note: note.trimmingCharacters(in: .whitespaces),
                showsCredentialPanel: showsCredentialPanel
            )
            dataService.addCard(newCard)
        }
        isPresented = false
    }
}

// MARK: - 可自由移动的条目编辑窗口

@MainActor
final class CardEditWindowPresenter: NSObject, ObservableObject, NSWindowDelegate {
    private var editorWindow: NSWindow?

    func present(dataService: DataService, editingCard: Card?, groupId: String) {
        editorWindow?.close()

        let groupName = dataService.data.groups.first(where: { $0.id == groupId })?.name ?? "未分组"
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 430),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = editingCard == nil ? "添加条目 · \(groupName)" : "编辑条目 · \(groupName)"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentMinSize = NSSize(width: 500, height: 430)
        window.contentMaxSize = NSSize(width: 500, height: 430)

        let isPresented = Binding<Bool>(
            get: { [weak window] in window?.isVisible == true },
            set: { [weak window] newValue in
                if !newValue {
                    window?.close()
                }
            }
        )
        let contentView = CardEditView(
            isPresented: isPresented,
            editingCard: editingCard,
            groupId: groupId,
            showsHeader: false
        )
        .environmentObject(dataService)

        window.contentView = NSHostingView(rootView: contentView)
        position(window, relativeTo: NSApp.keyWindow)
        editorWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        guard let closingWindow = notification.object as? NSWindow,
              closingWindow === editorWindow else { return }
        editorWindow = nil
    }

    private func position(_ window: NSWindow, relativeTo parentWindow: NSWindow?) {
        guard let parentWindow else {
            window.center()
            return
        }
        let origin = NSPoint(
            x: parentWindow.frame.midX - window.frame.width / 2,
            y: parentWindow.frame.midY - window.frame.height / 2
        )
        window.setFrameOrigin(origin)
    }
}

// MARK: - 延时遮蔽密码输入

private struct LastCharacterSecureField: NSViewRepresentable {
    @Binding var text: String
    let revealsText: Bool
    let forcesRomanInput: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(
            text: $text,
            revealsText: revealsText
        )
    }

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        let secureField = NSSecureTextField()
        let maskLabel = PasswordMaskLabel(labelWithString: "")
        let font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)

        secureField.translatesAutoresizingMaskIntoConstraints = false
        secureField.placeholderString = "password"
        secureField.font = font
        secureField.textColor = .clear
        secureField.delegate = context.coordinator
        secureField.stringValue = text
        (secureField.cell as? NSTextFieldCell)?.allowedInputSourceLocales = allowedInputSourceLocales

        maskLabel.translatesAutoresizingMaskIntoConstraints = false
        maskLabel.font = font
        maskLabel.textColor = .labelColor
        maskLabel.lineBreakMode = .byClipping
        maskLabel.maximumNumberOfLines = 1

        container.addSubview(secureField)
        container.addSubview(maskLabel)
        NSLayoutConstraint.activate([
            secureField.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            secureField.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            secureField.topAnchor.constraint(equalTo: container.topAnchor),
            secureField.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            maskLabel.leadingAnchor.constraint(equalTo: secureField.leadingAnchor, constant: 7),
            maskLabel.trailingAnchor.constraint(lessThanOrEqualTo: secureField.trailingAnchor, constant: -7),
            maskLabel.centerYAnchor.constraint(equalTo: secureField.centerYAnchor)
        ])

        context.coordinator.attach(secureField: secureField, maskLabel: maskLabel)
        context.coordinator.refresh(value: text, revealLast: false)
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.binding = $text
        let needsRefresh = context.coordinator.revealsText != revealsText
            || context.coordinator.secureField?.stringValue != text
        context.coordinator.revealsText = revealsText
        if let cell = context.coordinator.secureField?.cell as? NSTextFieldCell {
            cell.allowedInputSourceLocales = allowedInputSourceLocales
        }
        if needsRefresh {
            context.coordinator.refresh(value: text, revealLast: false)
        }
    }

    private var allowedInputSourceLocales: [String]? {
        forcesRomanInput ? [NSAllRomanInputSourcesLocaleIdentifier] : nil
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var binding: Binding<String>
        weak var secureField: NSSecureTextField?
        weak var maskLabel: NSTextField?
        var revealsText: Bool
        private var previousValue: String
        private var hideWorkItem: DispatchWorkItem?

        init(text: Binding<String>, revealsText: Bool) {
            binding = text
            self.revealsText = revealsText
            previousValue = text.wrappedValue
        }

        deinit {
            hideWorkItem?.cancel()
        }

        func attach(secureField: NSSecureTextField, maskLabel: NSTextField) {
            self.secureField = secureField
            self.maskLabel = maskLabel
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSSecureTextField else { return }
            let newValue = field.stringValue
            let appendedCharacter = newValue.count > previousValue.count && newValue.hasPrefix(previousValue)

            previousValue = newValue
            binding.wrappedValue = newValue
            refresh(value: newValue, revealLast: appendedCharacter)

            hideWorkItem?.cancel()
            guard appendedCharacter, !newValue.isEmpty else { return }

            let expectedValue = newValue
            let workItem = DispatchWorkItem { [weak self] in
                guard let self, self.secureField?.stringValue == expectedValue else { return }
                self.refresh(value: expectedValue, revealLast: false)
            }
            hideWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: workItem)
        }

        func refresh(value: String, revealLast: Bool) {
            if secureField?.stringValue != value {
                secureField?.stringValue = value
            }
            previousValue = value

            let characters = Array(value)
            if revealsText {
                maskLabel?.stringValue = value
                return
            }
            maskLabel?.stringValue = String(characters.enumerated().map { index, character in
                revealLast && index == characters.count - 1 ? character : "•"
            })
        }
    }
}

private final class PasswordMaskLabel: NSTextField {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

// MARK: - 网址或应用选择

struct LaunchTargetInput: View {
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("网址或应用")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)

            HStack(spacing: 8) {
                TextField("https://example.com 或选择一个应用", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 14))

                Button(action: selectApplication) {
                    Image(systemName: "app.badge")
                        .font(.system(size: 13))
                }
                .buttonStyle(.bordered)
                .help("选择 macOS 应用")
            }
        }
    }

    private func selectApplication() {
        let panel = NSOpenPanel()
        panel.title = "选择要打开的应用"
        panel.prompt = "选择"
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.treatsFilePackagesAsDirectories = false

        if panel.runModal() == .OK, let selectedURL = panel.url {
            text = selectedURL.path
        }
    }
}

// MARK: - 表单字段组件（避免与 ContentView.FieldInput 重名）

struct FormFieldInput: View {
    let label: String
    var placeholder: String = ""
    @Binding var text: String
    var required: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 3) {
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                if required {
                    Text("*")
                        .foregroundColor(.red)
                }
            }
            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 14))
        }
    }
}
