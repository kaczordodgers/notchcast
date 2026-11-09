import Foundation

enum PasteImagePolicy {
    static func accepts(types: [String]) -> Bool {
        !types.contains("public.file-url")
            && types.contains { ["public.png", "public.tiff", "public.jpeg", "public.heic"].contains($0) }
    }
}
