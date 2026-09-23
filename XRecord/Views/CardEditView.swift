import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - 条目编辑弹窗

struct CardEditView: View {
    @EnvironmentObject var dataService: DataService
    @Binding var isPresented: Bool
    let editingCard: Card?
    var groupId: String?
    /// 新建时的条目类型（编辑时以原条目类型为准）
    var initialKind: CardKind = .standard
    var showsHeader: Bool = true
    /// 嵌入三段式第三段时使用，去掉固定尺寸以填满分栏
    var embedded: Bool = false
    /// 保存成功后回调（用于三段式切换到查看模式）
    var onSaved: ((Card) -> Void)? = nil

    @State private var kind: CardKind = .standard
    @State private var customFields: [CustomField] = []
    @State private var revealedCustomFieldIDs: Set<String> = []
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
                    Text(isEditing
                         ? (kind == .custom ? "编辑自定义条目" : "编辑条目")
                         : (kind == .custom ? "添加自定义条目" : "添加条目"))
                        .scaledFont(size: 16, weight: .semibold)
                    Spacer()
                    if !isEditing {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color(hex: dataService.data.groups.first(where: { $0.id == groupId })?.colorHex ?? "#888888"))
                                .frame(width: 8, height: 8)
                            Text(groupName)
                                .scaledFont(size: 11)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(Capsule())
                    }
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
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // 名称
                    FormFieldInput(label: "名称", placeholder: "例如：后台管理系统", text: $name, required: true)

                    // 网址或本机应用
                    LaunchTargetInput(text: $url)

                    if kind == .custom {
                        customFieldsEditor
                    } else {
                        // 账号密码
                        HStack(spacing: 14) {
                            FormFieldInput(label: "账号", placeholder: "username", text: $username)
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("密码")
                                        .scaledFont(size: 12, weight: .medium)
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
                    }

                    if credentialPanelEnabled {
                        HStack(spacing: 12) {
                            Image(systemName: "rectangle.on.rectangle")
                                .scaledFont(size: 18)
                                .foregroundColor(.blue)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("打开后显示凭据浮窗")
                                    .scaledFont(size: 12, weight: .medium)
                                Text("需同时开启设置中的全局开关")
                                    .scaledFont(size: 10)
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
                            .scaledFont(size: 12, weight: .medium)
                            .foregroundColor(.secondary)
                        TextEditor(text: $note)
                            .scaledFont(size: 14)
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
        .frame(width: embedded ? nil : 500, height: embedded ? nil : (showsHeader ? 480 : 430))
        .frame(maxWidth: embedded ? .infinity : nil, maxHeight: embedded ? .infinity : nil)
        .alert("请先选择一个分组", isPresented: $showGroupError) {
            Button("确定") { isPresented = false }
        } message: {
            Text("添加条目前请先在左侧选择一个分组，或者点击「全部」后使用第一个分组。")
        }
        .onAppear {
            if let c = editingCard {
                currentEditingId = c.id
                kind = c.cardKind
                customFields = c.customFields ?? []
                name = c.name
                url = c.url
                username = c.username
                password = c.password
                note = c.note
                showsCredentialPanel = c.isCredentialPanelEnabled
            } else {
                currentEditingId = nil
                kind = initialKind
                customFields = initialKind == .custom ? [CustomField(label: "", value: "")] : []
                name = ""
                url = ""
                username = ""
                password = ""
                note = ""
                showsCredentialPanel = true
            }
        }
        .onDisappear { currentEditingId = nil }
        .appFontSizeScaled()
    }

    private var customFieldsEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("自定义小项")
                    .scaledFont(size: 12, weight: .medium)
                    .foregroundColor(.secondary)
                Spacer()
                Button(action: { customFields.append(CustomField(label: "", value: "")) }) {
                    Label("添加小项", systemImage: "plus")
                        .scaledFont(size: 12)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if customFields.isEmpty {
                Text("还没有小项，点击「添加小项」自定义，例如「帐套：12344」")
                    .scaledFont(size: 11)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 4)
            } else {
                ForEach($customFields) { $field in
                    HStack(spacing: 8) {
                        TextField("名称", text: $field.label)
                            .textFieldStyle(.roundedBorder)
                            .scaledFont(size: 13)
                            .frame(width: 100)

                        Text(":")
                            .foregroundColor(.secondary)

                        if field.isSecretField {
                            HStack(spacing: 6) {
                                LastCharacterSecureField(
                                    text: $field.value,
                                    revealsText: revealedCustomFieldIDs.contains(field.id),
                                    forcesRomanInput: false
                                )
                                .frame(height: 22)

                                Button(action: { toggleCustomFieldReveal(field.id) }) {
                                    Image(systemName: revealedCustomFieldIDs.contains(field.id) ? "eye.slash" : "eye")
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                                .help(revealedCustomFieldIDs.contains(field.id) ? "隐藏内容" : "显示内容")
                            }
                        } else {
                            TextField("内容", text: $field.value)
                                .textFieldStyle(.roundedBorder)
                                .scaledFont(size: 13)
                        }

                        Toggle("密文显示", isOn: Binding(
                            get: { field.isSecretField },
                            set: { newValue in
                                field.isSecret = newValue
                                if !newValue {
                                    revealedCustomFieldIDs.remove(field.id)
                                }
                            }
                        ))
                        .toggleStyle(.checkbox)
                        .scaledFont(size: 11)
                        .fixedSize()

                        Button(action: { removeCustomField(field.id) }) {
                            Image(systemName: "minus.circle")
                                .scaledFont(size: 13)
                                .foregroundColor(.red.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                        .help("删除小项")
                    }
                }
            }
        }
    }

    private var cleanedCustomFields: [CustomField] {
        customFields.compactMap { field in
            let label = field.label.trimmingCharacters(in: .whitespaces)
            let value = field.value.trimmingCharacters(in: .whitespaces)
            guard !label.isEmpty || !value.isEmpty else { return nil }
            var cleaned = field
            cleaned.label = label
            cleaned.value = value
            return cleaned
        }
    }

    private func removeCustomField(_ id: String) {
        customFields.removeAll { $0.id == id }
        revealedCustomFieldIDs.remove(id)
    }

    private func toggleCustomFieldReveal(_ id: String) {
        if revealedCustomFieldIDs.contains(id) {
            revealedCustomFieldIDs.remove(id)
        } else {
            revealedCustomFieldIDs.insert(id)
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }
        guard let gid = groupId else {
            // 如果没有分组，提示用户先选择分组
            showGroupError = true
            return
        }

        let trimmedURL = url.trimmingCharacters(in: .whitespaces)
        let trimmedNote = note.trimmingCharacters(in: .whitespaces)

        if let editId = currentEditingId,
           let existing = dataService.data.cards.first(where: { $0.id == editId }) {
            var c = existing
            c.name = trimmedName
            c.url = trimmedURL
            c.note = trimmedNote
            c.showsCredentialPanel = showsCredentialPanel
            c.kind = kind
            if kind == .custom {
                c.customFields = cleanedCustomFields
                c.username = ""
                c.password = ""
            } else {
                c.customFields = nil
                c.username = username.trimmingCharacters(in: .whitespaces)
                c.password = password
            }
            dataService.updateCard(c)
            isPresented = false
            onSaved?(c)
        } else {
            let newCard = Card(
                groupId: gid,
                name: trimmedName,
                url: trimmedURL,
                username: kind == .custom ? "" : username.trimmingCharacters(in: .whitespaces),
                password: kind == .custom ? "" : password,
                note: trimmedNote,
                showsCredentialPanel: showsCredentialPanel,
                kind: kind,
                customFields: kind == .custom ? cleanedCustomFields : nil
            )
            dataService.addCard(newCard)
            isPresented = false
            onSaved?(newCard)
        }
    }
}

// MARK: - 可自由移动的条目编辑窗口

@MainActor
final class CardEditWindowPresenter: NSObject, ObservableObject, NSWindowDelegate {
    private var editorWindow: NSWindow?

    func present(dataService: DataService, editingCard: Card?, groupId: String, kind: CardKind = .standard) {
        editorWindow?.close()

        let groupName = dataService.data.groups.first(where: { $0.id == groupId })?.name ?? "未分组"
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 430),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        if editingCard == nil {
            window.title = (kind == .custom ? "添加自定义条目" : "添加条目") + " · \(groupName)"
        } else {
            window.title = "编辑条目 · \(groupName)"
        }
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
            initialKind: kind,
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
    @Environment(\.appFontScale) private var fontScale
    @Binding var text: String
    let revealsText: Bool
    let forcesRomanInput: Bool

    private var fieldFont: NSFont {
        NSFont.monospacedSystemFont(ofSize: 14 * fontScale, weight: .regular)
    }

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
        let font = fieldFont

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
        if let secureField = context.coordinator.secureField, secureField.font != fieldFont {
            secureField.font = fieldFont
        }
        if let maskLabel = context.coordinator.maskLabel, maskLabel.font != fieldFont {
            maskLabel.font = fieldFont
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
                .scaledFont(size: 12, weight: .medium)
                .foregroundColor(.secondary)

            HStack(spacing: 8) {
                TextField("https://example.com 或选择一个应用", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .scaledFont(size: 14)

                Button(action: selectApplication) {
                    Image(systemName: "app.badge")
                        .scaledFont(size: 13)
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
                    .scaledFont(size: 12, weight: .medium)
                    .foregroundColor(.secondary)
                if required {
                    Text("*")
                        .foregroundColor(.red)
                }
            }
            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
                .scaledFont(size: 14)
        }
    }
}
