import AppKit

let scratch = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: scratch) }
let checker = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "check-pixels.swift")
for fixture in ["transparent", "uniform", "content"] {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 64, pixelsHigh: 64,
                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                  isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    for y in 0..<64 {
        for x in 0..<64 {
            let value: CGFloat = fixture == "content" && x < 32 ? 1 : 0
            let color = NSColor(deviceRed: value, green: value, blue: value,
                                alpha: fixture == "transparent" ? 0 : 1)
            bitmap.setColor(color, atX: x, y: y)
        }
    }
    try bitmap.representation(using: .png, properties: [:])!.write(to: scratch.appending(path: "page.png"))
    try "page.png\n".write(to: scratch.appending(path: "manifest.txt"), atomically: true, encoding: .utf8)
    let rect = ["width": 64, "height": 64]
    try JSONSerialization.data(withJSONObject: ["surface": rect, "canvas": rect])
        .write(to: scratch.appending(path: "page-layout.json"))
    let process = Process()
    process.executableURL = URL(filePath: "/usr/bin/swift")
    process.arguments = [checker.path, scratch.path]
    try process.run()
    process.waitUntilExit()
    precondition((process.terminationStatus == 0) == (fixture == "content"), fixture)
}
print("pixel guard fixtures: PASS")
