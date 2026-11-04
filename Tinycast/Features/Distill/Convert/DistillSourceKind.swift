import Foundation

nonisolated enum DistillSourceKind {
    case pdf, office, image, html, mhtml, media, text, visualText, unsupported

    init(_ source: URL) {
        switch source.pathExtension.lowercased() {
        case "pdf": self = .pdf
        case "doc", "docx", "rtf", "odt": self = .office
        case "png", "jpg", "jpeg", "webp", "tif", "tiff", "heic", "heif", "gif": self = .image
        case "html", "htm": self = .html
        case "mht", "mhtml": self = .mhtml
        case "mp4", "mov", "m4v", "webm", "avi", "mkv", "mp3", "m4a", "wav", "aac", "ogg",
            "flac", "opus": self = .media
        case "svg": self = .visualText
        case "", "txt", "text", "markdown", "mdown", "rst", "log", "csv", "tsv", "vtt", "srt",
            "json", "jsonl", "yaml", "yml", "xml", "toml", "ini", "cfg", "conf", "env", "example",
            "base", "local", "in", "cff", "0", "canvas", "ts", "tsx", "js", "jsx", "mjs", "cjs",
            "py", "rb", "php", "go", "rs", "java", "kt", "swift", "c", "cc", "cpp", "h", "hpp",
            "cs", "sh", "bash", "zsh", "fish", "ps1", "sql", "css", "scss", "sass", "less", "prfpset":
            self = .text
        default: self = .unsupported
        }
    }

    static let skippedFolders: Set<String> = ["node_modules", "venv", "__pycache__", "__MACOSX"]
    static let generatedFiles: Set<String> = [
        "_INDEX.md", "_CONVERSION-REPORT.md", "ALL-CONTENT.md",
        "linked-media-manifest.json", "linked-resources-manifest.json"
    ]

    var priority: Int {
        switch self {
        case .html, .mhtml: 0
        case .text, .visualText: 2
        default: 1
        }
    }
}
