import AppKit
import SwiftUI

private let credentialCornerRadius: CGFloat = 15
private let credentialPanelInset: CGFloat = 20
private let credentialPanelHeight: CGFloat = 164
private let expandedCredentialPanelWidth: CGFloat = 250
private let compactCredentialPanelWidth: CGFloat = 204

final class CredentialPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class CredentialPanelShadowView: NSView {
    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        let contentRect = bounds.insetBy(dx: credentialPanelInset, dy: credentialPanelInset)
        let path = CGPath(
            roundedRect: contentRect,
            cornerWidth: credentialCornerRadius,
            cornerHeight: credentialCornerRadius,
            transform: nil
        )
        context.saveGState()
        context.addRect(bounds)
        context.addPath(path)
        context.clip(using: .evenOdd)
        context.setShadow(
            offset: CGSize(width: 0, height: -4),
            blur: 18,
            color: NSColor.black.withAlphaComponent(0.62).cgColor
        )
        context.addPath(path)
        context.setFillColor(NSColor.black.cgColor)
        context.fillPath()
        context.restoreGState()

        context.addPath(path)
        context.setFillColor(NSColor.windowBackgroundColor.withAlphaComponent(0.1).cgColor)
        context.fillPath()
    }
}

final class CredentialPanelController {
    private let panel: CredentialPanel
    private var presentationID = UUID()
    private var autoDismissWorkItem: DispatchWorkItem?

    init() {
        panel = CredentialPanel(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: expandedCredentialPanelWidth,
                height: credentialPanelHeight
            ),
            styleMask: [.borderless, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isMovableByWindowBackground = true
        panel.animationBehavior = .utilityWindow
    }

    func show(card: Card, groupName: String, groupColorHex: String) {
        guard !card.username.isEmpty || !card.password.isEmpty else {
            hide()
            return
        }

        let currentPresentationID = UUID()
        presentationID = currentPresentationID
        let initialCredentialCount = [card.username, card.password].filter { !$0.isEmpty }.count
        let content = CredentialPanelView(
            card: card,
            groupName: groupName,
            groupColorHex: groupColorHex,
            onCredentialCountChange: { [weak self] count in
                self?.resize(forCredentialCount: count, animated: true)
            },
            onUse: { [weak self] in
                self?.scheduleAutoDismiss()
            },
            onDismiss: { [weak self] in
                guard self?.presentationID == currentPresentationID else { return }
                self?.hide()
            }
        )
        let hostingView = NSHostingView(rootView: content)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor

        let containerView = NSView(frame: panel.contentRect(forFrameRect: panel.frame))
        containerView.wantsLayer = true
        containerView.layer?.backgroundColor = NSColor.clear.cgColor

        let shadowView = CredentialPanelShadowView()
        shadowView.translatesAutoresizingMaskIntoConstraints = false

        let effectView = NSVisualEffectView()
        effectView.translatesAutoresizingMaskIntoConstraints = false
        effectView.material = .popover
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = credentialCornerRadius
        effectView.layer?.cornerCurve = .continuous
        effectView.layer?.masksToBounds = true

        containerView.addSubview(shadowView)
        containerView.addSubview(effectView)
        containerView.addSubview(hostingView)
        NSLayoutConstraint.activate([
            shadowView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            shadowView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            shadowView.topAnchor.constraint(equalTo: containerView.topAnchor),
            shadowView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            effectView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: credentialPanelInset),
            effectView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -credentialPanelInset),
            effectView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: credentialPanelInset),
            effectView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -credentialPanelInset),
            hostingView.leadingAnchor.constraint(equalTo: effectView.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: effectView.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: effectView.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: effectView.bottomAnchor)
        ])

        panel.contentView = containerView
        resize(forCredentialCount: initialCredentialCount, animated: false)
        positionOnActiveScreen()
        panel.orderFrontRegardless()
        scheduleAutoDismiss()
    }

    func hide() {
        cancelAutoDismiss()
        panel.orderOut(nil)
    }

    private func scheduleAutoDismiss() {
        cancelAutoDismiss()
        let seconds = CredentialPanelPreferences.autoDismissSeconds
        guard seconds > 0 else { return }

        let workItem = DispatchWorkItem { [weak self] in
            self?.hide()
        }
        autoDismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(seconds), execute: workItem)
    }

    private func cancelAutoDismiss() {
        autoDismissWorkItem?.cancel()
        autoDismissWorkItem = nil
    }

    private func resize(forCredentialCount count: Int, animated: Bool) {
        guard count > 0 else { return }
        let targetWidth = count > 1 ? expandedCredentialPanelWidth : compactCredentialPanelWidth
        guard panel.frame.width != targetWidth || panel.frame.height != credentialPanelHeight else { return }

        let currentFrame = panel.frame
        let targetFrame = NSRect(
            x: currentFrame.maxX - targetWidth,
            y: currentFrame.maxY - credentialPanelHeight,
            width: targetWidth,
            height: credentialPanelHeight
        )
        panel.setFrame(targetFrame, display: true, animate: animated && panel.isVisible)
    }

    private func positionOnActiveScreen() {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else {
            panel.center()
            return
        }
        panel.setFrameOrigin(
            NSPoint(
                x: visibleFrame.maxX - panel.frame.width - 18,
                y: visibleFrame.maxY - panel.frame.height - 18
            )
        )
    }
}

private struct CredentialPanelView: View {
    let card: Card
    let groupName: String
    let groupColorHex: String
    let onCredentialCountChange: (Int) -> Void
    let onUse: () -> Void
    let onDismiss: () -> Void

    @State private var showsUsername = true
    @State private var showsPassword = true
    @State private var toastText: String?

    private var groupColor: Color {
        Color(hex: groupColorHex)
    }

    var body: some View {
        VStack(spacing: 5) {
            HStack(spacing: 7) {
                Image("MenuBarIcon")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .foregroundColor(Color.primary.opacity(0.72))
                    .frame(width: 24, height: 24)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 1) {
                    Text("XRecord")
                        .font(.system(size: 12, weight: .semibold))
                    HStack(spacing: 4) {
                        Circle()
                            .fill(groupColor)
                            .frame(width: 6, height: 6)
                        Text("\(groupName) · \(card.name)")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("关闭")
            }

            SwiftUI.Group {
                if let toastText {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text(toastText)
                            .font(.system(size: 12, weight: .medium))
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                } else {
                    Color.clear
                }
            }
            .frame(height: 16)

            HStack(spacing: 26) {
                if !card.username.isEmpty && showsUsername {
                    credentialButton(title: "账号", icon: "person.crop.circle") {
                        let remainingCount = card.password.isEmpty || !showsPassword ? 0 : 1
                        showsUsername = false
                        copy(card.username, label: "账号", remainingCount: remainingCount)
                    }
                }
                if !card.password.isEmpty && showsPassword {
                    credentialButton(title: "密码", icon: "key.fill") {
                        let remainingCount = card.username.isEmpty || !showsUsername ? 0 : 1
                        showsPassword = false
                        copy(card.password, label: "密码", remainingCount: remainingCount)
                    }
                }
            }
            .frame(height: 57, alignment: .center)
            .transition(.opacity)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.16))
        .clipShape(RoundedRectangle(cornerRadius: credentialCornerRadius, style: .continuous))
    }

    private func credentialButton(
        title: String,
        icon: String,
        action: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 3) {
            Button(action: action) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(groupColor.opacity(0.92))
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.3), lineWidth: 0.7)
                    )
                    .shadow(color: groupColor.opacity(0.2), radius: 3, y: 2)
            }
            .buttonStyle(.plain)

            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
    }

    private func copy(_ value: String, label: String, remainingCount: Int) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)

        withAnimation(.easeInOut(duration: 0.16)) {
            toastText = "\(label)已复制到剪贴板"
        }
        onCredentialCountChange(remainingCount)
        onUse()

        DispatchQueue.main.asyncAfter(deadline: .now() + (remainingCount > 0 ? 0.9 : 0.65)) {
            if remainingCount > 0 {
                withAnimation(.easeInOut(duration: 0.16)) {
                    toastText = nil
                }
            } else {
                onDismiss()
            }
        }
    }
}
