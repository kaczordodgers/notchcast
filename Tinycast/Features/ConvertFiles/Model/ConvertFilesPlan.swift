import Foundation

struct ConvertFilesPlan: Sendable, Equatable {
    /// Stands in for the output path in `Item.arguments`; the runner swaps in the scratch file.
    static let outputPlaceholder = "{output}"

    struct Item: Sendable, Equatable {
        let sources: [URL]
        /// Published through `JobOutput`, which numbers the name only then, so it is chosen once.
        let stem: String
        let suffix: String
        let tool: String
        let arguments: [String]
    }

    struct Failure: LocalizedError, Equatable {
        let message: String
        var errorDescription: String? { message }
    }

    let items: [Item]

    static func make(sources: [URL], target: String, pages: String = "") throws -> Self {
        guard !sources.isEmpty, sources.allSatisfy({ $0.isFileURL && $0.path.hasPrefix("/") }) else {
            throw Failure(message: String(localized: "Choose local files.", table: "Notchcast"))
        }
        let format = target.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        let out = outputPlaceholder
        if format == "pdf-merge" {
            guard sources.allSatisfy({ $0.pathExtension.lowercased() == "pdf" }) else {
                throw Failure(message: String(localized: "PDF merge requires PDF files.", table: "Notchcast"))
            }
            let base = sources[0].deletingPathExtension().lastPathComponent
            return Self(items: [Item(sources: sources, stem: base + " merged", suffix: ".pdf", tool: "native",
                                     arguments: [format, pages] + sources.map(\.path))])
        }
        if ["zip", "7z", "tar.gz"].contains(format) {
            var arguments = ["-c", "-f", out]
            arguments += format == "tar.gz" ? ["-z", "--format=pax"]
                : ["--format=" + (format == "7z" ? "7zip" : "zip")]
            for source in sources {
                arguments += ["-C", source.deletingLastPathComponent().path, "./" + source.lastPathComponent]
            }
            let base = sources[0].deletingPathExtension().lastPathComponent
            return Self(items: [Item(sources: sources, stem: base, suffix: "." + format, tool: "tar", arguments: arguments)])
        }
        let images = Set(("jpg jpeg png webp heic heif tiff tif avif bmp ico icns cr2 cr3 nef arw dng raf orf "
            + "psd exr hdr jp2 tga ppm").split(separator: " ").map(String.init))
        let imageOutputs = Set("jpg png webp heic tiff avif ico icns gif bmp pdf".split(separator: " ").map(String.init))
        let documents = Set("docx doc odt rtf rtfd html htm txt webarchive".split(separator: " ").map(String.init))
        let audio = Set(("mp3 aac wav flac m4a ogg oga opus aiff aif wma amr ape wv ac3 alac caf au snd "
            + "dsf dff mpc spx xa ra").split(separator: " ").map(String.init))
        let video = Set(("mp4 mov mkv webm avi mpg gif ts mpeg vob m2ts mts m4v flv 3gp asf wmv rmvb "
            + "ogv mxf nut dv gxf rm cdxl wtv").split(separator: " ").map(String.init))
        let subtitles = Set(["srt", "ass", "ssa", "vtt"])
        let audioOutputs = Set(["mp3", "aac", "wav", "flac", "m4a", "ogg", "opus", "aiff"])
        let videoOutputs = Set(["mp4", "mov", "mkv", "webm", "avi", "mpg", "gif"])
        let data = Set(["json", "yaml", "yml", "toml", "csv"])
        var items: [Item] = []
        for source in sources {
            let ext = source.pathExtension.lowercased()
            var stem = source.deletingPathExtension().lastPathComponent
            var suffix = "." + format
            if format == "extract" {
                stem += " extracted"
                suffix = ""
            } else if format == "pdf-split" {
                stem += " pages"
                suffix = ""
            } else if format == "pdf-range" {
                stem += " pages"
                suffix = ".pdf"
            }
            var tool: String
            var arguments: [String]
            if format == "extract", ["zip", "7z", "rar", "tar", "gz", "bz2", "xz", "tgz", "iso", "cab"].contains(ext) {
                tool = "tar"
                arguments = ["-x", "--keep-old-files", "--no-same-owner", "--no-same-permissions",
                             "-f", source.path, "-C", out]
            } else if ext == "pdf", ["pdf-split", "pdf-range", "txt"].contains(format) {
                tool = "native"
                arguments = [format == "txt" ? "pdf-text" : format, pages, source.path]
            } else if data.contains(ext), data.contains(format) {
                tool = "native"
                arguments = ["data", format, source.path]
            } else if images.contains(ext), imageOutputs.contains(format) {
                if format == "webp" {
                    tool = "cwebp"
                    arguments = ["-quiet", "-lossless", source.path, "-o", out]
                } else if ["heic", "avif"].contains(format) {
                    tool = "sips"
                    arguments = ["-s", "format", format, source.path, "--out", out]
                } else {
                    tool = "native"
                    arguments = ["image", format, source.path]
                }
            } else if (ext == "md" || ext == "markdown") && ["docx", "html", "epub"].contains(format)
                        || ["docx", "html", "htm", "epub"].contains(ext) && format == "md" {
                tool = "pandoc"
                arguments = ["--sandbox", "--standalone", source.path, "-o", out]
            } else if documents.contains(ext), documents.contains(format), format != "htm", format != "webarchive" {
                tool = "textutil"
                arguments = ["-convert", format, "-encoding", "UTF-8", "-noload", "-nostore", "-strip",
                             "-output", out, source.path]
            } else if subtitles.contains(ext) && subtitles.contains(format)
                        || audio.contains(ext) && audioOutputs.contains(format)
                        || video.contains(ext) && audioOutputs.union(videoOutputs).contains(format) {
                tool = "ffmpeg"
                arguments = ["-nostdin", "-v", "error", "-n", "-protocol_whitelist", "file,pipe,crypto,data",
                             "-i", source.path, out]
            } else {
                throw Failure(message: String(localized: "This file conversion is not supported.", table: "Notchcast"))
            }
            items.append(Item(sources: [source], stem: stem, suffix: suffix, tool: tool, arguments: arguments))
        }
        return Self(items: items)
    }
}
