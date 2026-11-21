// notchcast-hosted-only
// notchcast-sources: Tinycast/Platform/Appearance.swift Tinycast/DesignSystem/Theme.swift
// notchcast-sources: Tinycast/DesignSystem/InterfaceMetrics.swift Tinycast/Features/Notchcast/NotchTheme.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandPresentation.swift Tinycast/Features/Calendar/Model/*.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandLook.swift Tinycast/Features/Island/Model/PillMenuRows.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandKeyline.swift Tinycast/Features/Island/Model/IslandPlayer.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandNoticeArt.swift Tinycast/Features/Island/Service/IslandCanvas.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandExpansionArt.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandSongArt.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandLevelArt.swift Tinycast/Features/Island/Model/IslandLevelDwell.swift
import AppKit
import SwiftUI

/// #938's island states in Dark, both forms, to `NC_AUDIT_RENDERS`; Frosted by `NC_AUDIT_LOOK=frosted`.
@MainActor
@main
struct ScrollingCaptureRenderTest {
    static let folder = URL(fileURLWithPath: ProcessInfo.processInfo.environment["NC_AUDIT_RENDERS"]
        ?? NSTemporaryDirectory() + "nc-scrolling-capture-renders")
    static let frosted = ProcessInfo.processInfo.environment["NC_AUDIT_LOOK"] == "frosted"
    static let notchSize = CGSize(width: 185, height: 32)

    static func write(_ name: String, size: CGSize, _ draw: @escaping (CGRect) -> Void) {
        let image = NSImage(size: size, flipped: false) { rect in
            draw(rect)
            return true
        }
        var proposed = CGRect(origin: .zero, size: size)
        guard let cgImage = image.cgImage(forProposedRect: &proposed, context: nil,
                                          hints: [.ctm: AffineTransform(scale: 2)]),
            let data = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:])
        else { preconditionFailure("\(name) did not render") }
        do {
            try data.write(to: folder.appendingPathComponent("\(name).png"))
        } catch {
            preconditionFailure("\(name): \(error)")
        }
    }

    /// Black's pill on a grey desk; Frosted's glass tint over a white wallpaper, as the canvas fills it.
    static func paint(_ rect: CGRect, island: NSBezierPath) {
        (frosted ? NSColor.white : NSColor(white: 0.18, alpha: 1)).setFill()
        rect.fill()
        NSColor(frosted ? NotchTheme.Colors.islandGlassTint : NotchTheme.Colors.islandSurface).setFill()
        island.fill()
    }

    /// The island hanging from the top edge, `body` tall below the notch, its art drawn in that lower part.
    static func island(_ name: String, width: CGFloat, body: CGFloat, notch: Bool, radius: CGFloat,
                       notchLeft: CGFloat? = nil, _ draw: @escaping (CGRect) -> Void) {
        let top = notch ? notchSize.height : 0
        let size = CGSize(width: max(width, notch ? notchSize.width : NotchTheme.Size.islandRest.width) + 64,
                          height: top + body + 32)
        write(name, size: size) { rect in
            let shape = CGRect(x: 32, y: rect.maxY - top - body, width: size.width - 64, height: top + body)
            let path = NSBezierPath()
            path.move(to: CGPoint(x: shape.minX, y: rect.maxY))
            path.line(to: CGPoint(x: shape.minX, y: shape.minY + radius))
            path.appendArc(withCenter: CGPoint(x: shape.minX + radius, y: shape.minY + radius), radius: radius,
                           startAngle: 180, endAngle: 270)
            path.line(to: CGPoint(x: shape.maxX - radius, y: shape.minY))
            path.appendArc(withCenter: CGPoint(x: shape.maxX - radius, y: shape.minY + radius), radius: radius,
                           startAngle: 270, endAngle: 360)
            path.line(to: CGPoint(x: shape.maxX, y: rect.maxY))
            path.close()
            paint(rect, island: notch || body > NotchTheme.Size.islandRest.height ? path
                  : NSBezierPath(roundedRect: shape, xRadius: body / 2, yRadius: body / 2))
            if notch {
                NSColor.black.setFill()
                CGRect(x: shape.minX + (notchLeft ?? (shape.width - notchSize.width) / 2),
                       y: rect.maxY - notchSize.height, width: notchSize.width, height: notchSize.height).fill()
            }
            draw(notch && body == 0 ? CGRect(x: shape.minX, y: shape.minY, width: shape.width, height: top)
                 : CGRect(x: shape.minX, y: shape.minY, width: shape.width, height: body))
        }
    }

    /// The compact pill: content hugs the ends, a notch keeps the middle, as the engine sizes the slots.
    static func compact(_ name: String, _ art: some PillArt, notch: Bool) {
        let inner = notch ? Theme.Spacing.md : 0
        let width = (notch ? notchSize.width : 0) + 2 * (Theme.Spacing.lg + inner) + art.layout.leading
            + art.layout.trailing
        island(name, width: width, body: notch ? 0 : NotchTheme.Size.islandRest.height, notch: notch,
               radius: notch ? 10 : 12, notchLeft: Theme.Spacing.lg + Theme.Spacing.md + art.layout.leading) {
            art.draw(in: $0)
        }
    }

    /// Beside a notch only the glyph shows; the text comes out below it, as a notice does.
    static func notice(_ name: String, _ notice: IslandNotice, notch: Bool) {
        guard notch else { return compact(name, IslandNoticeArt(notice, notch: false, frosted: frosted), notch: false) }
        let line = IslandHeadlineArt(notice, notch: notchSize.width, frosted: frosted)
        island(name, width: line.size.width, body: line.size.height, notch: true, radius: Theme.Radius.panel) {
            line.draw(in: $0)
        }
    }

    static func main() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        NSApp.appearance = NSAppearance(named: .darkAqua)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let look = frosted ? "frosted" : "black"
        let running = IslandStatus(id: "screenshot.scrolling", symbol: "stop.circle", text: "1.2k",
                                   label: "Finish Scrolling Capture")
        let notices = [
            ("d-copied", IslandNotice(id: "screenshot.copied", symbol: "camera", text: "Copied")),
            ("e-height-limit", IslandNotice(id: "screenshot.copied", symbol: "camera",
                                            text: "Scrolling capture reached the 20,000 pixel limit.", seconds: 4)),
            ("e-guard-limit", IslandNotice(id: "screenshot.copied", symbol: "camera",
                                           text: "Scrolling capture stopped at its limit.", seconds: 4)),
            ("f-page-changed", IslandNotice(id: "screenshot.copied", symbol: "camera",
                                            text: "Kept the part before the page changed.", seconds: 4)),
            ("g-no-access", IslandNotice(id: "screenshot.failed", symbol: "camera",
                                         text: "Screen Recording access is required.", isFailure: true)),
        ]
        for notch in [false, true] {
            let form = notch ? "notch" : "nonotch"
            for text in ["1.2k", "20k", nil] {
                var status = running
                status.text = text
                compact("938-b-status-\(text ?? "starting")-\(form)-\(look)",
                        IslandStatusArt([status], notch: notch, frosted: frosted), notch: notch)
            }
            for (name, shown) in notices { notice("938-\(name)-\(form)-\(look)", shown, notch: notch) }
        }
        print("nc-Screenshots-scrolling-render-test: ok, \(folder.path)")
    }
}
