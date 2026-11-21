// notchcast-sources: Tinycast/Platform/Appearance.swift Tinycast/DesignSystem/Theme.swift
// notchcast-sources: notchcast/vendor/Obsidian/ObsidianTokens.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/UI/NotchcastCommandRowLayout.swift
import AppKit
import SwiftUI

@MainActor
@main
struct CommandRowLayoutTest {
    static let name = "Synchronize project backups to the NAS"
    static var titleBounds = CGRect.zero
    static var controlsBounds = CGRect.zero
    static var checkboxBounds = CGRect.zero
    static var rowBounds = CGRect.zero

    static func main() {
        let wide = check(width: 700, minimumTitle: NotchcastCommandRowLayout.titleMinimum, stacked: false)
        let middle = check(width: 400, minimumTitle: 200, stacked: true)
        let narrow = check(width: 300, minimumTitle: 150, stacked: true)
        precondition(abs(wide.width - middle.width) < 0.5, "the stacked checkbox keeps its full label")
        precondition(wide.width - narrow.width > 50, "the narrow checkbox drops the label")
        precondition(narrow.width > 0 && narrow.height > 0, "the narrow checkbox stays visible")
        checkIdentity()
        print("PASS command rows keep names readable and adapt controls and labels at all three widths")
    }

    static func check(width: CGFloat, minimumTitle: CGFloat, stacked: Bool) -> CGRect {
        titleBounds = .zero
        controlsBounds = .zero
        checkboxBounds = .zero
        rowBounds = .zero
        let row = NotchcastCommandRow {
            Text(name)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minWidth: NotchcastCommandRowLayout.titleMinimum, alignment: .leading)
                .background(probe { titleBounds = $0 })
        } trailing: {
            Image(systemName: "trash")
        } controls: {
            Color.gray.frame(width: Theme.Size.shortcutRecorder, height: 24)
            Color.gray.frame(width: Theme.Size.shortcutRecorder, height: 24)
                .background(probe { controlsBounds = $0 })
            Toggle(isOn: .constant(true)) {
                NotchcastLauncherCheckboxLabel(title: Text("Show in launcher"))
            }
            .toggleStyle(.checkbox)
            .background(probe { checkboxBounds = $0 })
        }
        .background(probe { rowBounds = $0 })
        .coordinateSpace(name: "row")
        .frame(width: width)
        .padding(Theme.Spacing.lg)
        .background(Color.black)
        .environment(\.colorScheme, .dark)

        let renderer = ImageRenderer(content: row)
        renderer.scale = 2
        guard let image = renderer.nsImage else { preconditionFailure("width \(width): nothing rendered") }
        if let folder = ProcessInfo.processInfo.environment["NC_AUDIT_RENDERS"],
           let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
           let png = bitmap.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: folder).appendingPathComponent("command-row-\(Int(width)).png"))
        }
        print("width \(width): title \(titleBounds), controls \(controlsBounds), checkbox \(checkboxBounds)")
        precondition(titleBounds.width >= minimumTitle, "width \(width): title collapsed")
        precondition(rowBounds.width <= width + 0.5 && checkboxBounds.maxX <= width + 0.5, "width \(width): overflow")
        if stacked {
            precondition(controlsBounds.minY >= titleBounds.maxY, "width \(width): controls should move below title")
        } else {
            precondition(abs(controlsBounds.midY - titleBounds.midY) < 0.5, "width \(width): controls should stay inline")
        }
        return checkboxBounds
    }

    static func checkIdentity() {
        var mounted: [NSView] = []
        let row = NotchcastCommandRow {
            Text(name).frame(minWidth: NotchcastCommandRowLayout.titleMinimum)
        } trailing: {
            EmptyView()
        } controls: {
            ControlProbe { mounted.append($0) }
                .frame(width: Theme.Size.shortcutRecorder, height: 24)
            ControlProbe { mounted.append($0) }
                .frame(width: Theme.Size.shortcutRecorder, height: 24)
            Toggle(isOn: .constant(true)) {
                NotchcastLauncherCheckboxLabel(title: Text("Show in launcher"))
            }
            .toggleStyle(.checkbox)
        }
        .environment(\.colorScheme, .dark)

        let host = NSHostingView(rootView: row)
        host.setFrameSize(NSSize(width: 700, height: 120))
        host.layoutSubtreeIfNeeded()
        precondition(mounted.count == 2, "the two controls mount once at the wide width")
        let widePosition = mounted[0].convert(.zero, to: host) as CGPoint

        host.setFrameSize(NSSize(width: 300, height: 120))
        host.layoutSubtreeIfNeeded()
        let narrowPosition = mounted[0].convert(.zero, to: host) as CGPoint
        precondition(widePosition.y != narrowPosition.y, "resizing moves the existing controls")
        precondition(mounted.count == 2 && mounted.allSatisfy { $0.isDescendant(of: host) }, "both controls stay mounted")
        print("PASS both control views survive resize")
    }

    private struct ControlProbe: NSViewRepresentable {
        let mounted: (NSView) -> Void

        func makeNSView(context: Context) -> NSView {
            let view = NSView()
            mounted(view)
            return view
        }

        func updateNSView(_ view: NSView, context: Context) {}
    }

    static func probe(_ record: @escaping @MainActor (CGRect) -> Void) -> some View {
        GeometryReader { proxy in
            record(proxy.frame(in: .named("row")))
            return Color.clear
        }
    }
}
