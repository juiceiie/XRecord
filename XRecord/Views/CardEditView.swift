import SwiftUI

// MARK: - 条目编辑弹窗

struct CardEditView: View {
    @EnvironmentObject var dataService: DataService
    @Binding var isPresented: Bool
    @Binding var editingCard: Card?
    var groupId: String?

    @State private var name: String = ""
    @State private var url: String = ""
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var note: String = ""
    @State private var showPassword: Bool = false
    @State private var currentEditingId: String? = nil
    @State private var showGroupError: Bool = false

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
            // 标题栏
            HStack {
                Text(isEditing ? "编辑条目" : "添加条目")
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                // 显示当前分组
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

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // 名称
                    FormFieldInput(label: "名称", placeholder: "例如：后台管理系统", text: $name, required: true)

                    // 地址
                    FormFieldInput(label: "地址 URL", placeholder: "https://example.com", text: $url)

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
                                if showPassword {
                                    TextField("password", text: $password)
                                        .textFieldStyle(.roundedBorder)
                                        .font(.system(size: 14))
                                } else {
                                    SecureField("password", text: $password)
                                        .textFieldStyle(.roundedBorder)
                                        .font(.system(size: 14))
                                }

                                Button(action: { showPassword.toggle() }) {
                                    Image(systemName: showPassword ? "eye.slash" : "eye")
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .frame(maxWidth: .infinity)
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
        .frame(width: 500, height: 480)
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
            }
        }
        .onDisappear {
            editingCard = nil
            currentEditingId = nil
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

        if let editId = currentEditingId,
           let existing = dataService.data.cards.first(where: { $0.id == editId }) {
            var c = existing
            c.name = trimmedName
            c.url = url.trimmingCharacters(in: .whitespaces)
            c.username = username.trimmingCharacters(in: .whitespaces)
            c.password = password
            c.note = note.trimmingCharacters(in: .whitespaces)
            dataService.updateCard(c)
        } else {
            let newCard = Card(
                groupId: gid,
                name: trimmedName,
                url: url.trimmingCharacters(in: .whitespaces),
                username: username.trimmingCharacters(in: .whitespaces),
                password: password,
                note: note.trimmingCharacters(in: .whitespaces)
            )
            dataService.addCard(newCard)
        }
        isPresented = false
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
