import AppKit

struct PixelLayout: Decodable {
    struct Rect: Decodable {
        let width: Double
        let height: Double
        var area: Double { width * height }
    }
    let surface: Rect
    let canvas: Rect
}

/// Any opaque pixel brighter than the black island fill, on a 2 px grid so thin glyph strokes are seen.
func hasContent(_ image: NSBitmapImageRep) -> Bool {
    for y in stride(from: 0, to: image.pixelsHigh, by: 2) {
        for x in stride(from: 0, to: image.pixelsWide, by: 2) {
            if let color = image.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB), color.alphaComponent > 0.5,
               max(color.redComponent, color.greenComponent, color.blueComponent) > 0.25 { return true }
        }
    }
    return false
}

let directory = URL(filePath: CommandLine.arguments[1])
let pages = try String(contentsOf: directory.appending(path: "manifest.txt"), encoding: .utf8)
    .split(separator: "\n").map(String.init)
var failures = 0
var closedImages: [String: [(String, Data)]] = [:]
for page in pages {
    guard URL(filePath: page).lastPathComponent == page,
          let data = try? Data(contentsOf: directory.appending(path: page)),
          let image = NSBitmapImageRep(data: data) else {
        print("FAIL \(page): invalid PNG")
        failures += 1
        continue
    }
    if page.hasPrefix("island-closed-"), let shape = page.split(separator: "-").last {
        let key = String(shape)
        if let duplicate = closedImages[key]?.first(where: { $0.1 == data }) {
            print("FAIL \(page): identical closed state to \(duplicate.0)")
            failures += 1
        }
        closedImages[key, default: []].append((page, data))
    }
    var opaque = 0
    var colors: [Int: Int] = [:]
    var total = 0
    for y in stride(from: 0, to: image.pixelsHigh, by: 8) {
        for x in stride(from: 0, to: image.pixelsWide, by: 8) {
            total += 1
            guard let color = image.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                  color.alphaComponent > 0.1 else {
                colors[-1, default: 0] += 1
                continue
            }
            opaque += 1
            let key = (Int(color.redComponent * 31) << 10)
                | (Int(color.greenComponent * 31) << 5) | Int(color.blueComponent * 31)
            colors[key, default: 0] += 1
        }
    }
    let coverage = Double(opaque) / Double(max(total, 1))
    let diversity = Double(total - (colors.values.max() ?? 0)) / Double(max(total, 1))
    let layoutURL = directory.appending(path: page.replacingOccurrences(of: ".png", with: "-layout.json"))
    let layout = try JSONDecoder().decode(PixelLayout.self, from: Data(contentsOf: layoutURL))
    let expected = layout.surface.area / max(layout.canvas.area, 1)
    let minimumCoverage = page.hasPrefix("settings-") ? 0.95 : expected * 0.7
    if coverage < minimumCoverage || diversity < 0.001 {
        print("FAIL \(page): blank pixels (coverage \(coverage), diversity \(diversity))")
        failures += 1
    } else if page.hasPrefix("island-"), !page.hasPrefix("island-closed-idle-"),
              !page.hasPrefix("island-opening-middle-"), !page.hasPrefix("island-opening-end-"), !hasContent(image) {
        // The capture fills the island outline black before drawing, so a failed draw is a black shape: require lit pixels.
        // The opening's middle and end are the black alone by design: the closed content has faded before them.
        print("FAIL \(page): island surface without content (no lit pixel)")
        failures += 1
    }
}
print("pixels: \(pages.count - failures) PASS, \(failures) FAIL")
exit(failures == 0 && !pages.isEmpty ? 0 : 1)
