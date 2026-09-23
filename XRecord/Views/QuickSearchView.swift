import AppKit
import SwiftUI

private let quickSearchCornerRadius: CGFloat = 26

private struct QuickSearchResult: Identifiable {
    let card: Card
    let group: Group
    let score: Int

    var id: String { card.id }
}

private enum QuickSearchMatcher {
    static func results(for query: String, data: AppData) -> [QuickSearchResult] {
        let groupByID = Dictionary(uniqueKeysWithValues: data.groups.map { ($0.id, $0) })
        let normalizedQuery = normalize(query)

        if normalizedQuery.isEmpty {
            return RecentLaunchStore.cards(in: data, limit: 5).enumerated().map { index, card in
                QuickSearchResult(card: card, group: group(for: card, in: groupByID), score: index)
            }
        }

        return data.cards.filter { !$0.isTrashed }.compactMap { card in
            let group = group(for: card, in: groupByID)
            let variants = searchableVariants(group: group.name, card: card.name)
            let score = matchScore(query: normalizedQuery, variants: variants)
            guard normalizedQuery.isEmpty || score != nil else { return nil }
            return QuickSearchResult(card: card, group: group, score: score ?? 3)
        }
        .sorted {
            if $0.score != $1.score { return $0.score < $1.score }
            if $0.group.createdAt != $1.group.createdAt { return $0.group.createdAt < $1.group.createdAt }
            return $0.card.createdAt > $1.card.createdAt
        }
    }

    /// 分组可能已被删除（条目从回收站恢复后成为孤立条目），使用占位分组展示
    private static func group(for card: Card, in groupByID: [String: Group]) -> Group {
        groupByID[card.groupId] ?? Group(id: card.groupId, name: "未分类", colorHex: "#8E8E93")
    }

    private static func searchableVariants(group: String, card: String) -> Set<String> {
        let groupVariants = variants(for: group)
        let cardVariants = variants(for: card)
        var result = Set(groupVariants + cardVariants)

        for groupValue in groupVariants {
            for cardValue in cardVariants {
                result.insert(groupValue + cardValue)
            }
        }
        return result
    }

    private static func variants(for value: String) -> [String] {
        let original = normalize(value)
        let latin = value
            .applyingTransform(.toLatin, reverse: false)?
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current) ?? value
        let tokens = latin
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        let compactPinyin = normalize(tokens.joined())
        let initials = normalize(tokens.compactMap { $0.first }.map(String.init).joined())
        return Array(Set([original, compactPinyin, initials].filter { !$0.isEmpty }))
    }

    private static func matchScore(query: String, variants: Set<String>) -> Int? {
        guard !query.isEmpty else { return 3 }
        if variants.contains(query) { return 0 }
        if variants.contains(where: { $0.hasPrefix(query) }) { return 1 }
        if variants.contains(where: { $0.contains(query) }) { return 2 }
        return nil
    }

    private static func normalize(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
            .unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init)
            .joined()
    }
}

final class QuickSearchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class TransparentHostingView<Content: View>: NSHostingView<Content> {
    override var isOpaque: Bool { false }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }
}

private final class RoundedShadowView: NSView {
    private let radius: CGFloat
    private let contentInset: CGFloat

    init(cornerRadius: CGFloat, contentInset: CGFloat) {
        radius = cornerRadius
        self.contentInset = contentInset
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        let contentRect = bounds.insetBy(dx: contentInset, dy: contentInset)
        let path = CGPath(
            roundedRect: contentRect,
            cornerWidth: radius,
            cornerHeight: radius,
            transform: nil
        )
        context.saveGState()
        context.setShadow(
            offset: CGSize(width: 0, height: -7),
            blur: 22,
            color: NSColor.black.withAlphaComponent(0.34).cgColor
        )
        context.addPath(path)
        context.setFillColor(NSColor.windowBackgroundColor.cgColor)
        context.fillPath()
        context.restoreGState()
    }
}

final class QuickSearchWindowController: NSObject, NSWindowDelegate {
    private let panel: QuickSearchPanel
    private let dataService: DataService

    init(dataService: DataService) {
        self.dataService = dataService
        panel = QuickSearchPanel(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 510),
            styleMask: [.borderless, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()

        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.appearance = NSAppearance(named: .vibrantLight)
        // The system window shadow is calculated from the rectangular panel frame,
        // which leaves visible square corners around transparent material views.
        panel.hasShadow = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.delegate = self
    }

    func toggle() {
        panel.isVisible ? hide() : show()
    }

    func show() {
        let rootView = QuickSearchView(
            dataService: dataService,
            onDismiss: { [weak self] in self?.hide() },
            onOpen: { [weak self] card in self?.open(card) }
        )
        let hostingView = TransparentHostingView(rootView: rootView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor

        let containerView = NSView(frame: panel.contentRect(forFrameRect: panel.frame))
        containerView.wantsLayer = true
        containerView.layer?.masksToBounds = false

        let shadowView = RoundedShadowView(cornerRadius: quickSearchCornerRadius, contentInset: 40)
        shadowView.translatesAutoresizingMaskIntoConstraints = false

        let glassView = NSVisualEffectView()
        glassView.translatesAutoresizingMaskIntoConstraints = false
        glassView.material = .popover
        glassView.blendingMode = .behindWindow
        glassView.state = .active
        glassView.wantsLayer = true
        glassView.layer?.cornerRadius = quickSearchCornerRadius
        glassView.layer?.cornerCurve = .continuous
        glassView.layer?.masksToBounds = true
        glassView.maskImage = Self.roundedMask(cornerRadius: quickSearchCornerRadius)
        containerView.addSubview(shadowView)
        containerView.addSubview(glassView)
        containerView.addSubview(hostingView)
        NSLayoutConstraint.activate([
            shadowView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            shadowView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            shadowView.topAnchor.constraint(equalTo: containerView.topAnchor),
            shadowView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            glassView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 40),
            glassView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -40),
            glassView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 40),
            glassView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -40),
            hostingView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 40),
            hostingView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -40),
            hostingView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 40),
            hostingView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -40)
        ])
        panel.contentView = containerView
        panel.contentView?.superview?.wantsLayer = true
        panel.contentView?.superview?.layer?.backgroundColor = NSColor.clear.cgColor
        positionOnActiveScreen()
        panel.orderFrontRegardless()
        panel.makeKey()
    }

    private static func roundedMask(cornerRadius: CGFloat) -> NSImage {
        let side = cornerRadius * 2 + 2
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            NSColor.white.setFill()
            NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(
            top: cornerRadius,
            left: cornerRadius,
            bottom: cornerRadius,
            right: cornerRadius
        )
        image.resizingMode = .stretch
        return image
    }

    func hide() {
        panel.orderOut(nil)
    }

    func windowDidResignKey(_ notification: Notification) {
        hide()
    }

    private func open(_ card: Card) {
        guard !card.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            if CredentialPanelPreferences.isEnabled, card.isCredentialPanelEnabled {
                hide()
                NotificationCenter.default.post(name: .didOpenLaunchTarget, object: card.id)
                return
            }
            NSSound.beep()
            return
        }
        hide()
        _ = LaunchTarget.open(card.url, cardID: card.id)
    }

    private func positionOnActiveScreen() {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else {
            panel.center()
            return
        }
        let origin = NSPoint(
            x: visibleFrame.midX - panel.frame.width / 2,
            y: visibleFrame.maxY - panel.frame.height - 110
        )
        panel.setFrameOrigin(origin)
    }
}

struct QuickSearchView: View {
    @ObservedObject var dataService: DataService
    let onDismiss: () -> Void
    let onOpen: (Card) -> Void

    @State private var query = ""
    @State private var selectedIndex = 0

    private var results: [QuickSearchResult] {
        Array(QuickSearchMatcher.results(for: query, data: dataService.data).prefix(8))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Image("MenuBarIcon")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .foregroundColor(Color.primary.opacity(0.72))
                    .frame(width: 34, height: 34)
                    .accessibilityHidden(true)

                QuickSearchField(
                    text: $query,
                    onMoveUp: { moveSelection(by: -1) },
                    onMoveDown: { moveSelection(by: 1) },
                    onSubmit: openSelected,
                    onCancel: onDismiss
                )

                Text("esc")
                    .scaledFont(size: 11, weight: .medium, design: .rounded)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Color.primary.opacity(0.07))
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            }
            .padding(.horizontal, 24)
            .frame(height: 76)

            Divider().opacity(0.55)

            if !dataService.hasBoundFile {
                emptyState(icon: "doc.badge.plus", text: "请先在 XRecord 中绑定数据文件")
            } else if results.isEmpty {
                emptyState(icon: query.isEmpty ? "clock" : "magnifyingglass", text: query.isEmpty ? "暂无最近打开的条目" : "没有找到匹配的条目")
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                                resultRow(result, isSelected: index == selectedIndex)
                                    .id(result.id)
                                    .onTapGesture {
                                        selectedIndex = index
                                        onOpen(result.card)
                                    }
                            }
                        }
                        .padding(8)
                    }
                    .onChange(of: selectedIndex) { index in
                        guard results.indices.contains(index) else { return }
                        withAnimation(.easeOut(duration: 0.12)) {
                            proxy.scrollTo(results[index].id, anchor: .center)
                        }
                    }
                }
            }
        }
        .frame(width: 640, height: 430)
        .background(Color.clear)
        .overlay(
            RoundedRectangle(cornerRadius: quickSearchCornerRadius, style: .continuous)
                .stroke(Color.white.opacity(0.58), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: quickSearchCornerRadius, style: .continuous))
        .onChange(of: query) { _ in selectedIndex = 0 }
        .appFontSizeScaled()
    }

    private func resultRow(_ result: QuickSearchResult, isSelected: Bool) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color(hex: result.group.colorHex).opacity(isSelected ? 0.28 : 0.16))
                Image(systemName: LaunchTarget.isApplication(result.card.url) ? "app" : "link")
                    .scaledFont(size: 14, weight: .medium)
                    .foregroundColor(Color(hex: result.group.colorHex))
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 4) {
                Text(result.card.name)
                    .scaledFont(size: 14, weight: .semibold)
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Text(result.card.url.isEmpty ? "未设置地址" : LaunchTarget.displayName(for: result.card.url, dataService: dataService))
                    .scaledFont(size: 11)
                    .foregroundColor(result.card.url.isEmpty ? .orange : .secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            HStack(spacing: 5) {
                Circle()
                    .fill(Color(hex: result.group.colorHex))
                    .frame(width: 6, height: 6)
                Text(result.group.name)
                    .scaledFont(size: 11, weight: .medium)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.primary.opacity(0.06))
            .clipShape(Capsule())

            if isSelected {
                Image(systemName: "return")
                    .scaledFont(size: 11, weight: .medium)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 56)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(isSelected ? Color.accentColor.opacity(0.16) : Color.white.opacity(0.05))
        )
        .contentShape(RoundedRectangle(cornerRadius: 7))
    }

    private func emptyState(icon: String, text: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .scaledFont(size: 28, weight: .light)
                .foregroundColor(.secondary)
            Text(text)
                .scaledFont(size: 13)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func moveSelection(by offset: Int) {
        guard !results.isEmpty else { return }
        selectedIndex = min(max(selectedIndex + offset, 0), results.count - 1)
    }

    private func openSelected() {
        guard results.indices.contains(selectedIndex) else { return }
        onOpen(results[selectedIndex].card)
    }
}

private struct QuickSearchField: NSViewRepresentable {
    @Environment(\.appFontScale) private var fontScale
    @Binding var text: String
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onSubmit: () -> Void
    let onCancel: () -> Void

    private var fieldFont: NSFont {
        .systemFont(ofSize: 19 * fontScale, weight: .regular)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.placeholderString = "搜索分类或条目名称"
        field.font = fieldFont
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.delegate = context.coordinator

        DispatchQueue.main.async {
            field.window?.makeFirstResponder(field)
        }
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text {
            field.stringValue = text
        }
        if field.font != fieldFont {
            field.font = fieldFont
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: QuickSearchField

        init(parent: QuickSearchField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.moveUp(_:)):
                parent.onMoveUp()
            case #selector(NSResponder.moveDown(_:)):
                parent.onMoveDown()
            case #selector(NSResponder.insertNewline(_:)):
                parent.onSubmit()
            case #selector(NSResponder.cancelOperation(_:)):
                parent.onCancel()
            default:
                return false
            }
            return true
        }
    }
}
