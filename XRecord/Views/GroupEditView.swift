import SwiftUI
import AppKit

// MARK: - 分组编辑弹窗

struct GroupEditView: View {
    @EnvironmentObject var dataService: DataService
    @Binding var isPresented: Bool
    @Binding var editingGroup: Group?
    
    // 新增：新建分组后自动选中的回调
    var onGroupCreated: ((String) -> Void)? = nil

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

            VStack(alignment: .leading, spacing: 16) {
                // 分组名称
                VStack(alignment: .leading, spacing: 6) {
                    Text("分组名称")
                        .scaledFont(size: 12, weight: .medium)
                        .foregroundColor(.secondary)
                    TextField("例如：生产环境", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .scaledFont(size: 14)
                }

                // 颜色选择
                VStack(alignment: .leading, spacing: 6) {
                    Text("颜色")
                        .scaledFont(size: 12, weight: .medium)
                        .foregroundColor(.secondary)
                    HStack(spacing: 10) {
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
                                        .scaledFont(size: 9, weight: .bold)
                                        .foregroundColor(.white)
                                        .opacity(selectedColor == color ? 1 : 0)
                                )
                                .onTapGesture { selectedColor = color }
                        }

                        Spacer(minLength: 0)

                        Button(action: chooseRandomColor) {
                            Image(systemName: "dice.fill")
                                .scaledFont(size: 11, weight: .semibold)
                                .foregroundColor(.secondary)
                                .frame(width: 22, height: 22)
                                .background(Color.secondary.opacity(0.1))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .help("随机选择未使用的颜色")

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
                                        .scaledFont(size: 11, weight: .bold)
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
            } else {
                currentEditingId = nil
                name = ""
                selectedColor = Group.defaultColors[0]
            }
        }
        .appFontSizeScaled()
    }

    private func chooseRandomColor() {
        var occupiedColors = Set(
            dataService.data.groups
                .filter { $0.id != currentEditingId }
                .map { $0.colorHex.uppercased() }
        )
        // 连续点击随机按钮时也应产生新颜色。
        occupiedColors.insert(selectedColor.uppercased())

        let availablePresetColors = Group.defaultColors.filter {
            !occupiedColors.contains($0.uppercased())
        }
        if let color = availablePresetColors.randomElement() {
            selectedColor = color
            return
        }

        // 预设色全部占用后，继续生成适合标签展示的高饱和颜色。
        for _ in 0..<256 {
            let generatedColor = NSColor(
                calibratedHue: CGFloat.random(in: 0..<1),
                saturation: CGFloat.random(in: 0.58...0.78),
                brightness: CGFloat.random(in: 0.72...0.9),
                alpha: 1
            )
            let candidate = Color(nsColor: generatedColor).toHex()

            if !occupiedColors.contains(candidate.uppercased()) {
                selectedColor = candidate
                return
            }
        }

        // 理论上的随机碰撞兜底，确保绝不返回已使用颜色。
        for rawValue in 0...0xFFFFFF {
            let candidate = String(format: "#%06X", rawValue)
            if !occupiedColors.contains(candidate) {
                selectedColor = candidate
                return
            }
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        // 判断是编辑已有分组还是新建分组
        let editId = currentEditingId

        // 提前清理 editingGroup，避免 onDisappear 在 onGroupCreated 之后触发导致 selectedGroupId 被清掉
        editingGroup = nil
        currentEditingId = nil

        if let id = editId,
           let existing = dataService.data.groups.first(where: { $0.id == id }) {
            var g = existing
            g.name = trimmed
            g.colorHex = selectedColor
            dataService.updateGroup(g)
            isPresented = false
        } else {
            let newGroup = Group(name: trimmed, colorHex: selectedColor)
            dataService.addGroup(newGroup)
            // 新建分组后，通过回调通知 ContentView 自动选中这个分组
            onGroupCreated?(newGroup.id)
            isPresented = false
        }
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
                    .scaledFont(size: 15, weight: .semibold)
                Spacer()
                Button(action: { isPresented = false }) {
                    Image(systemName: "xmark")
                        .scaledFont(size: 13, weight: .medium)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider()

            CenteredColorWell(color: $pickedColor)
                .frame(width: 90, height: 44)
                .padding(30)
                .frame(maxWidth: .infinity, minHeight: 120)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.secondary.opacity(0.06))
                        .padding(8)
                )

            Divider()

            HStack(spacing: 10) {
                Button("取消") { dismissColorPicker() }
                    .buttonStyle(.bordered)
                Spacer()
                Button("确认") {
                    selectedHex = pickedColor.toHex()
                    dismissColorPicker()
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
        .onDisappear {
            NSColorPanel.shared.orderOut(nil)
        }
    }

    private func dismissColorPicker() {
        NSColorPanel.shared.orderOut(nil)
        isPresented = false
    }
}

private struct CenteredColorWell: NSViewRepresentable {
    @Binding var color: Color

    func makeCoordinator() -> Coordinator {
        Coordinator(color: $color)
    }

    func makeNSView(context: Context) -> NSColorWell {
        let colorWell = NSColorWell()
        colorWell.color = NSColor(color)
        colorWell.target = context.coordinator
        colorWell.action = #selector(Coordinator.colorChanged(_:))

        DispatchQueue.main.async {
            colorWell.activate(true)
            context.coordinator.centerColorPanel()
        }
        return colorWell
    }

    func updateNSView(_ nsView: NSColorWell, context: Context) {
        context.coordinator.binding = $color
        let newColor = NSColor(color)
        if nsView.color != newColor {
            nsView.color = newColor
        }
    }

    final class Coordinator: NSObject {
        var binding: Binding<Color>

        init(color: Binding<Color>) {
            binding = color
        }

        @objc func colorChanged(_ sender: NSColorWell) {
            binding.wrappedValue = Color(nsColor: sender.color)
        }

        func centerColorPanel() {
            let panel = NSColorPanel.shared
            guard let screen = panel.screen ?? NSScreen.main else { return }
            let visibleFrame = screen.visibleFrame
            let origin = NSPoint(
                x: visibleFrame.midX - panel.frame.width / 2,
                y: visibleFrame.midY - panel.frame.height / 2
            )
            panel.setFrameOrigin(origin)
            panel.orderFront(nil)
        }
    }
}
