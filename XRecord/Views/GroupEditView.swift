import SwiftUI

// MARK: - 分组编辑弹窗

struct GroupEditView: View {
    @EnvironmentObject var dataService: DataService
    @Binding var isPresented: Bool
    @Binding var editingGroup: Group?

    @State private var name: String = ""
    @State private var selectedColor: String = Group.defaultColors[0]
    @State private var currentEditingId: String? = nil
    @State private var showColorPicker: Bool = false

    var isEditing: Bool { editingGroup != nil }

    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            HStack {
                Text(isEditing ? "编辑分组" : "新建分组")
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

            VStack(alignment: .leading, spacing: 16) {
                // 分组名称
                VStack(alignment: .leading, spacing: 6) {
                    Text("分组名称")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                    TextField("例如：生产环境", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 14))
                }

                // 颜色选择
                VStack(alignment: .leading, spacing: 6) {
                    Text("颜色")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                    HStack(spacing: 12) {
                        // 当前颜色预览
                        Circle()
                            .fill(Color(hex: selectedColor))
                            .frame(width: 30, height: 30)
                            .overlay(
                                Circle()
                                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                            )

                        // 预设颜色
                        ForEach(Group.defaultColors.prefix(8), id: \.self) { color in
                            Circle()
                                .fill(Color(hex: color))
                                .frame(width: 22, height: 22)
                                .overlay(
                                    Circle()
                                        .stroke(Color.primary.opacity(0.3), lineWidth: selectedColor == color ? 2 : 0)
                                )
                                .overlay(
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundColor(.white)
                                        .opacity(selectedColor == color ? 1 : 0)
                                )
                                .onTapGesture { selectedColor = color }
                        }

                        Spacer()

                        // 自定义颜色按钮（打开系统颜色选择器）
                        Button(action: { showColorPicker = true }) {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [.red, .orange, .yellow, .green, .blue, .purple],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 22, height: 22)
                                .overlay(
                                    Image(systemName: "plus")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(.white)
                                )
                                .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .sheet(isPresented: $showColorPicker) {
                    ColorPickerSheet(selectedHex: $selectedColor, isPresented: $showColorPicker)
                }
            }
            .padding(20)

            Divider()

            // 底部按钮
            HStack(spacing: 10) {
                Button("取消") { isPresented = false }
                    .buttonStyle(.bordered)
                Spacer()
                Button(isEditing ? "保存" : "创建") {
                    save()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .frame(width: 420)
        .onAppear {
            if let g = editingGroup {
                currentEditingId = g.id
                name = g.name
                selectedColor = g.colorHex
            }
        }
        .onDisappear {
            editingGroup = nil
            currentEditingId = nil
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        if let editId = currentEditingId,
           let existing = dataService.data.groups.first(where: { $0.id == editId }) {
            var g = existing
            g.name = trimmed
            g.colorHex = selectedColor
            dataService.updateGroup(g)
        } else {
            let newGroup = Group(name: trimmed, colorHex: selectedColor)
            dataService.addGroup(newGroup)
        }
        isPresented = false
    }
}

// MARK: - 系统颜色选择器弹窗

struct ColorPickerSheet: View {
    @Binding var selectedHex: String
    @Binding var isPresented: Bool

    @State private var pickedColor: Color = .blue

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("选择颜色")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Button(action: { isPresented = false }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider()

            ColorPicker("分组颜色", selection: $pickedColor, supportsOpacity: false)
                .labelsHidden()
                .scaleEffect(1.3)
                .padding(30)
                .frame(maxWidth: .infinity, minHeight: 120)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.secondary.opacity(0.06))
                        .padding(8)
                )

            Divider()

            HStack(spacing: 10) {
                Button("取消") { isPresented = false }
                    .buttonStyle(.bordered)
                Spacer()
                Button("确认") {
                    selectedHex = pickedColor.toHex()
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
        }
        .frame(width: 300, height: 280)
        .onAppear {
            pickedColor = Color(hex: selectedHex)
        }
    }
}
