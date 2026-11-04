import AppKit

let scratch = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: scratch) }
let checker = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "check-pixels.swift")

/// Fixture name, page name, whether the guard passes it, and the pixel at (x, y) as (white, alpha).
let fixtures: [(String, String, Bool, (Int, Int) -> (CGFloat, CGFloat))] = [
    ("transparent", "page.png", false, { _, _ in (0, 0) }),
    ("uniform", "page.png", false, { _, _ in (0, 1) }),
    ("content", "page.png", true, { x, _ in (x < 32 ? 1 : 0, 1) }),
    // A black island outline on a transparent canvas: the fill drew, the content did not.
    ("island outline only", "island-open-home-entries-mba.png", false, { x, _ in (0, x < 32 ? 1 : 0) }),
    ("island with content", "island-open-home-entries-mba.png", true, { x, y in (x == 10 && y < 8 ? 1 : 0, x < 32 ? 1 : 0) }),
    ("idle island is empty by design", "island-closed-idle-mba.png", true, { x, _ in (0, x < 32 ? 1 : 0) }),
]
for (fixture, page, passes, pixel) in fixtures {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 64, pixelsHigh: 64,
                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                  isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    for y in 0..<64 {
        for x in 0..<64 {
            let (value, alpha) = pixel(x, y)
            bitmap.setColor(NSColor(deviceRed: value, green: value, blue: value, alpha: alpha), atX: x, y: y)
        }
    }
    try bitmap.representation(using: .png, properties: [:])!.write(to: scratch.appending(path: page))
    try "\(page)\n".write(to: scratch.appending(path: "manifest.txt"), atomically: true, encoding: .utf8)
    let surface = ["width": page == "page.png" ? 64 : 32, "height": 64]
    try JSONSerialization.data(withJSONObject: ["surface": surface, "canvas": ["width": 64, "height": 64]])
        .write(to: scratch.appending(path: page.replacingOccurrences(of: ".png", with: "-layout.json")))
    let process = Process()
    process.executableURL = URL(filePath: "/usr/bin/swift")
    process.arguments = [checker.path, scratch.path]
    try process.run()
    process.waitUntilExit()
    precondition((process.terminationStatus == 0) == passes, fixture)
}
print("pixel guard fixtures: PASS (blank, uniform, content, island outline only, island content, idle island)")
