#if DEBUG
import AppKit

@MainActor
enum GalleryCapture {
    struct Element: Encodable {
        let role: String
        let label: String
        let frame: Rect
    }

    struct Rect: Encodable {
        let x: CGFloat
        let y: CGFloat
        let width: CGFloat
        let height: CGFloat

        init(_ rect: CGRect) {
            x = rect.minX
            y = rect.minY
            width = rect.width
            height = rect.height
        }
    }

    struct Layout: Encodable {
        let page: String
        let scale: Int
        let canvas: Rect
        let surface: Rect
        let hardwareNotch: Rect?
        let elements: [Element]
        let accessibilityComplete = false
        let accessibilityGap = "SwiftUI omits virtual children in never-ordered windows; raw exposed AX elements only."
    }

    static func write(page: GalleryPage, window: NSWindow, output: URL) throws {
        guard !window.isVisible, !window.isKeyWindow, let view = window.contentView else {
            throw GalleryFailure.capture("visible or missing window: " + page.name)
        }
        view.layoutSubtreeIfNeeded()
        let bounds = view.bounds
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(bounds.width * 2), pixelsHigh: Int(bounds.height * 2),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: bitmap),
              let cached = view.bitmapImageRepForCachingDisplay(in: bounds) else {
            throw GalleryFailure.capture(page.name)
        }
        bitmap.size = bounds.size
        window.appearance?.performAsCurrentDrawingAppearance {
            view.cacheDisplay(in: bounds, to: cached)
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        let graphics = context.cgContext
        graphics.scaleBy(x: 2, y: 2)
        let path = page.silhouette?(window)
        if let path {
            graphics.addPath(path)
            graphics.setFillColor(NSColor.black.cgColor)
            graphics.fillPath()
            graphics.addPath(path)
            graphics.clip()
        } else {
            window.appearance?.performAsCurrentDrawingAppearance {
                window.backgroundColor.setFill()
                bounds.fill()
            }
        }
        cached.draw(in: bounds)
        NSGraphicsContext.restoreGraphicsState()
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw GalleryFailure.capture(page.name)
        }
        try png.write(to: output.appending(path: page.name + ".png"))
        let surface = path?.boundingBoxOfPath ?? bounds
        let layout = Layout(page: page.name, scale: 2, canvas: Rect(bounds), surface: Rect(surface),
                            hardwareNotch: page.hardwareNotch.map(Rect.init), elements: elements(in: view))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(layout).write(to: output.appending(path: page.name + "-layout.json"))
    }

    static func elements(in view: NSView) -> [Element] {
        var result: [Element] = []
        var visited = Set<ObjectIdentifier>()
        func walk(_ object: AnyObject) {
            guard visited.insert(ObjectIdentifier(object)).inserted,
                  let element = object as? NSObject else { return }
            func value(_ key: String) -> Any? {
                element.responds(to: NSSelectorFromString(key)) ? element.value(forKey: key) : nil
            }
            if let native = element as? NSView, native.isHidden { return }
            if value("isAccessibilityHidden") as? Bool == true { return }
            let screenFrame = (value("accessibilityFrame") as? NSValue)?.rectValue ?? .zero
            let frame = view.window?.convertFromScreen(screenFrame) ?? .zero
            if frame.width > 0, frame.height > 0 {
                result.append(Element(role: value("accessibilityRole") as? String ?? "unknown",
                                      label: value("accessibilityLabel") as? String
                                        ?? value("accessibilityValue") as? String
                                        ?? value("accessibilityTitle") as? String ?? "", frame: Rect(frame)))
            }
            let children = value("accessibilityChildren") as? [AnyObject] ?? []
            for child in children { walk(child) }
            if let native = element as? NSView {
                for child in native.subviews { walk(child) }
            }
        }
        if view is IslandSurfaceView {
            for child in view.subviews { walk(child) }
        } else { walk(view) }
        return result
    }
}
#endif
