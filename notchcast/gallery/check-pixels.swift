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

let directory = URL(filePath: CommandLine.arguments[1])
let pages = try String(contentsOf: directory.appending(path: "manifest.txt"), encoding: .utf8)
    .split(separator: "\n").map(String.init)
var failures = 0
for page in pages {
    guard URL(filePath: page).lastPathComponent == page,
          let data = try? Data(contentsOf: directory.appending(path: page)),
          let image = NSBitmapImageRep(data: data) else {
        print("FAIL \(page): invalid PNG")
        failures += 1
        continue
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
    }
}
print("pixels: \(pages.count - failures) PASS, \(failures) FAIL")
exit(failures == 0 && !pages.isEmpty ? 0 : 1)
