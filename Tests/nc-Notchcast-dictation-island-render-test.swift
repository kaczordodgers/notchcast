// notchcast-hosted-only
// notchcast-sources: Tinycast/Platform/Appearance.swift Tinycast/DesignSystem/Theme.swift
// notchcast-sources: Tinycast/DesignSystem/InterfaceMetrics.swift Tinycast/Features/Notchcast/NotchTheme.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandPresentation.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandNoticeArt.swift Tinycast/Features/Island/UI/IslandTone+Ink.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandCanvas.swift Tinycast/Features/Island/Model/PillMenuRows.swift
// notchcast-sources: Tinycast/Features/Calendar/Model/*.swift Tinycast/Features/Island/Model/IslandLevelDwell.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandSongArt.swift Tinycast/Features/Island/Model/IslandPlayer.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandLevelArt.swift Tinycast/Features/Island/Model/IslandLook.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandKeyline.swift Tinycast/Features/Island/Service/IslandExpansionArt.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/Model/DictationIslandSession.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/Model/DictationIslandNotice.swift
import AppKit

/// #960's closed dictation states, both forms and looks, 2x PNGs into `NC_AUDIT_RENDERS`.
@MainActor
@main
struct DictationIslandRenderTest {
    static let folder = URL(fileURLWithPath: ProcessInfo.processInfo.environment["NC_AUDIT_RENDERS"]
        ?? NSTemporaryDirectory() + "nc-island-audit-renders")
    static let notchSize = CGSize(width: 185, height: 32)

    static func write(_ name: String, size: CGSize, _ draw: @escaping (CGRect) -> Void) {
        let image = NSImage(size: size, flipped: false) { rect in
            draw(rect)
            return true
        }
        var proposed = CGRect(origin: .zero, size: size)
        let cg = image.cgImage(forProposedRect: &proposed, context: nil, hints: [.ctm: AffineTransform(scale: 2)])
        guard let cg, let data = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else {
            preconditionFailure("\(name) did not render")
        }
        do { try data.write(to: folder.appendingPathComponent("\(name).png")) } catch {
            preconditionFailure("\(name): \(error)")
        }
    }

    /// The island hanging from the top edge, `body` tall below the notch, art in that lower part.
    static func island(_ name: String, width: CGFloat, body: CGFloat, notch: Bool, radius: CGFloat, frosted: Bool,
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
            (frosted ? NSColor.white : NSColor(white: 0.18, alpha: 1)).setFill()
            rect.fill()
            NSColor(frosted ? NotchTheme.Colors.islandGlassTint : NotchTheme.Colors.islandSurface).setFill()
            (notch || body > NotchTheme.Size.islandRest.height ? path
                : NSBezierPath(roundedRect: shape, xRadius: body / 2, yRadius: body / 2)).fill()
            if notch {
                NSColor.black.setFill()
                CGRect(x: shape.minX + (notchLeft ?? (shape.width - notchSize.width) / 2),
                       y: rect.maxY - notchSize.height, width: notchSize.width, height: notchSize.height).fill()
            }
            draw(notch && body == 0 ? CGRect(x: shape.minX, y: shape.minY, width: shape.width, height: top)
                 : CGRect(x: shape.minX, y: shape.minY, width: shape.width, height: body))
        }
    }

    /// The compact pill as the engine sizes it: content hugs the ends, a notch keeps the middle.
    static func compact(_ name: String, _ art: IslandNoticeArt, notch: Bool, frosted: Bool) {
        let inner = notch ? Theme.Spacing.md : 0
        let width = (notch ? notchSize.width : 0) + 2 * (Theme.Spacing.lg + inner) + art.layout.leading
            + art.layout.trailing
        island(name, width: width, body: notch ? 0 : NotchTheme.Size.islandRest.height, notch: notch,
               radius: notch ? 10 : 12, frosted: frosted,
               notchLeft: Theme.Spacing.lg + Theme.Spacing.md + art.layout.leading) { art.draw(in: $0) }
        print("\(name): leading \(art.layout.leading) trailing \(art.layout.trailing) width \(width)")
    }

    static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        NSApp.appearance = NSAppearance(named: .darkAqua)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for old in try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        where old.lastPathComponent.hasPrefix("960-") && !old.lastPathComponent.hasPrefix("960-open-") {
            try FileManager.default.removeItem(at: old)
        }
        var session = DictationIslandSession()
        session.begin(copies: false, at: 0)
        _ = session.hear(levels: (0..<21).map { Float(0.25 + 0.7 * sin(Double($0) / 3).magnitude) }, at: 7.4)
        let recording = IslandNotice(dictation: session)!
        var settled = recording
        settled.progress?.headline = false
        var long = session
        _ = long.hear(levels: [0.6], at: 600)
        var longNotice = IslandNotice(dictation: long)!
        longNotice.progress?.headline = false
        _ = session.transcribe()
        let transcribing = IslandNotice(dictation: session)!
        _ = session.cleanUp()
        let cleaning = IslandNotice(dictation: session)!
        let states: [(String, IslandNotice, Bool)] = [
            ("01-recording-hint", recording, false), ("03-recording-10min", longNotice, false),
            ("04-transcribing", transcribing, false), ("05-cleaning-up", cleaning, false),
            ("06-pasted", IslandNotice(dictation: .pasted), false), ("07-copied", IslandNotice(dictation: .copied), false),
            ("08-no-speech", IslandNotice(dictation: .noSpeech), false),
            ("09-pasted-without-cleanup", IslandNotice(dictation: .pastedRaw), false),
            ("09b-copied-without-cleanup", IslandNotice(dictation: .copiedRaw), false),
            ("09c-no-model-paste", IslandNotice(dictation: .noCleanupModel(copies: false)), false),
            ("09d-no-model-copy", IslandNotice(dictation: .noCleanupModel(copies: true)), false),
            ("10-paste-failed", IslandNotice(dictation: .pasteFailed), false),
            ("11-part-lost", IslandNotice(dictation: .partLost), false),
            ("12-failed", IslandNotice(dictation: .failed), false), ("13-recording-still", settled, true),
        ]
        var count = 0
        for frosted in [false, true] {
            let ink = frosted ? "frosted" : "black"
            for (step, notice, still) in states {
                for notch in [false, true] {
                    let name = "960-\(step)-\(notch ? "notch" : "island")-\(ink)"
                    if notch, notice.isHeadline {
                        let line = IslandHeadlineArt(notice, notch: notchSize.width, frosted: frosted, still: still)
                        island(name, width: line.size.width, body: line.size.height, notch: true,
                               radius: Theme.Radius.panel, frosted: frosted) { line.draw(in: $0) }
                        print("\(name): headline \(line.size)")
                    } else {
                        compact(name, IslandNoticeArt(notice, notch: notch, frosted: frosted, still: still),
                                notch: notch, frosted: frosted)
                    }
                    count += 1
                }
                if step == "01-recording-hint" {
                    compact("960-02-recording-compact-notch-\(ink)", IslandNoticeArt(settled, notch: true,
                            frosted: frosted), notch: true, frosted: frosted)
                    count += 1
                }
            }
        }
        precondition(count == 62, "31 pictures a look")
        print("PASS rendered \(count) dictation island states to \(folder.path)")
    }
}
