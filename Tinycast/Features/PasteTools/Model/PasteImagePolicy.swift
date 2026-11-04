import Foundation

struct PasteImagePolicy: Sendable {
    private var swallowing = false

    mutating func take(down: Bool, repeatKey: Bool, eligible: Bool) -> Bool {
        guard down else {
            defer { swallowing = false }
            return swallowing
        }
        if repeatKey { return swallowing }
        swallowing = eligible
        return eligible
    }

    static func accepts(types: [String]) -> Bool {
        !types.contains("public.file-url")
            && types.contains { ["public.png", "public.tiff", "public.jpeg", "public.heic"].contains($0) }
    }
}
