import AppKit
import SwiftUI

/// Deliberately not a focusable control. See docs/features/hotkeys.md#recorder.
struct ShortcutRecorder: View {
    let action: HotKeyAction
    /// Drops the empty well's fill: a column of identical pills reads louder than its rows.
    var isQuiet = false

    static let horizontalInset = Theme.Spacing.sm

    @Environment(HotKeyManager.self) private var hotKeys
    @Environment(\.shortcutDeepLink) private var deepLink
    /// Observed so a modifier-only binding surfaces its warning when the grant changes.
    private var modifierTapMonitor: ModifierTapMonitor { hotKeys.modifierTapMonitor }
    @State private var hovered = false

    private var isRecording: Bool { hotKeys.recordingAction == action }

    /// Sits back a shade until pointed at, without reading as something you cannot press.
    private var unsetInk: Color {
        isRecording || !isQuiet || hovered
            ? Theme.Colors.textSecondary : Theme.Colors.textTertiary
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.menu, style: .continuous)
        // The width is kept either way, so a column of recorders stays aligned as they fill in.
        let showsFill = !isQuiet || isRecording || hovered || hotKeys.binding(for: action) != nil
        content
            .padding(.horizontal, Self.horizontalInset)
            .frame(width: Theme.Size.shortcutRecorder, height: Theme.Size.settingsRowButton)
            .background(shape.fill(Theme.Colors.cardFill).opacity(showsFill ? 1 : 0))
            .background {
                if isRecording { ShortcutRecorderHitRegion(capture: hotKeys.capture) }
            }
            .overlay(shape.strokeBorder(Theme.Colors.cardStroke, lineWidth: 1))
            // An over-long binding truncates rather than resizing the field.
            .clipShape(shape)
            .contentShape(shape)
            .onTapGesture { hotKeys.recordingAction = isRecording ? nil : action }
            .onHover { hovered = $0 }
            .anchorPreference(key: ShortcutRecorderAnchorKey.self, value: .bounds) {
                isRecording ? $0 : nil
            }
            // Rows are lazy: a recording row scrolled away must release the session.
            .onDisappear { if isRecording { hotKeys.recordingAction = nil } }
            // A reused table row can hand this field another action while the old one records.
            .onChange(of: action) { old, _ in
                if hotKeys.recordingAction == old { hotKeys.recordingAction = nil }
            }
            .animation(.easeOut(duration: 0.12), value: hovered)
            .contextMenu {
                if let deepLink, let url = deepLink.url(action) {
                    Button("Copy Deeplink", systemImage: "link") { deepLink.copy(url) }
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        if let binding = hotKeys.binding(for: action) {
            ShortcutRecorderBindingLabel(
                binding: binding,
                showsAccessibilityWarning: binding.usesModifierTapMonitor && modifierTapMonitor.needsAccessibility,
                hovered: hovered
            ) {
                hotKeys.setBinding(nil, for: action)
            }
        } else {
            Text(isRecording ? "Waiting for a shortcut…" : "Record Hotkey")
                .font(Theme.Typography.keyCap)
                .foregroundStyle(unsetInk)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct ShortcutRecorderBindingLabel: View {
    let binding: HotKeyBinding
    let showsAccessibilityWarning: Bool
    let hovered: Bool
    let onClear: () -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.xxs) {
            if showsAccessibilityWarning {
                Button {
                    Permissions.openAccessibilitySettings()
                } label: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open Accessibility settings")
                .help("Modifier-only hotkeys need Accessibility access. Click to grant it.")
            }
            ViewThatFits(in: .horizontal) {
                keycaps(compact: false)
                keycaps(compact: true)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(binding.keycaps.joined(separator: " "))
            .frame(maxWidth: .infinity)

            Button(action: onClear) {
                Image(systemName: "xmark.circle.fill")
                    .font(Theme.Typography.compactKeyCap)
                    .foregroundStyle(.tertiary)
                    .frame(width: Theme.Size.recorderKeyCap, height: Theme.Size.recorderKeyCap)
                    .opacity(hovered ? 1 : 0)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Clear shortcut", tableName: "Notchcast"))
            .allowsHitTesting(hovered)
        }
    }

    private func keycaps(compact: Bool) -> some View {
        let spacing = compact ? Theme.Spacing.xxs : Theme.Spacing.xs
        let capSize = Theme.Size.recorderKeyCap
        let capWidth = compact ? Theme.Size.compactRecorderKeyCapWidth : capSize
        return HStack(spacing: spacing) {
            ForEach(Array(binding.recorderKeycaps.enumerated()), id: \.offset) { _, cap in
                KeyCapChip.Label(text: cap, prefix: binding.recorderPrefix)
                    .font(compact ? Theme.Typography.compactKeyCap : Theme.Typography.keyCap)
                    .lineLimit(1)
                    .minimumScaleFactor(Theme.Size.recorderKeyCapMinimumScale)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, spacing)
                    .frame(minWidth: capWidth, minHeight: capSize)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Radius.recorderKeyCap, style: .continuous)
                            .fill(Color.primary.opacity(0.08))
                    )
            }
        }
    }
}

private struct ShortcutRecorderHitRegion: NSViewRepresentable {
    let capture: ShortcutCaptureSession

    func makeNSView(context: Context) -> PassiveView {
        let view = PassiveView()
        view.capture = capture
        capture.setActiveRecorderView(view)
        return view
    }

    func updateNSView(_ view: PassiveView, context: Context) {
        if view.capture !== capture { view.capture?.clearActiveRecorderView(view) }
        view.capture = capture
        capture.setActiveRecorderView(view)
    }

    static func dismantleNSView(_ view: PassiveView, coordinator: ()) {
        view.capture?.clearActiveRecorderView(view)
    }

    final class PassiveView: NSView {
        weak var capture: ShortcutCaptureSession?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
