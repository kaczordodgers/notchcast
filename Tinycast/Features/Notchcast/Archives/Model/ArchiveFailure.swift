import Foundation

nonisolated struct ArchiveProcessResult: Equatable, Sendable {
    var status: Int32
    var output = ""
    var errors = ""
}

/// Every way an extraction or a compression stops short, each with the words the island shows.
nonisolated enum ArchiveFailure: Error, Equatable, Sendable {
    case notArchive(String)
    case missingTool(ArchiveTool)
    case unsafe(ArchiveRefusal)
    case noSpace(String)
    case damaged(String)
    case password
    case startedElsewhere(String)
    case resumeJournalMismatch
    case failed(String)
    case nothingSelected
    case automationRefused
    case severalFolders
    case notWritable(String)
    case notCompressible(String)
    case busy(String)
    case compressionFailed(String)

    /// HatchZip's documented exit statuses; 130 is a pause, so the caller treats it as a stop.
    static let hatchzipPaused: Int32 = 130
    static let hatchzipNoSpace: Int32 = 3
    static let hatchzipPassword: Int32 = 5

    static func hatchzip(_ result: ArchiveProcessResult) -> ArchiveFailure? {
        switch result.status {
        case 0: nil
        case hatchzipNoSpace: .noSpace(detail(result))
        case 4: .damaged(detail(result))
        case hatchzipPassword: .password
        case 1 where result.errors.contains(".hatchzip does not belong to "): .resumeJournalMismatch
        case 1 where result.errors.contains("already partially extracted to "):
            .startedElsewhere(partialExtractionPath(result.errors))
        default: .failed(detail(result))
        }
    }

    private static func partialExtractionPath(_ errors: String) -> String {
        let prefix = "already partially extracted to "
        let suffix = ". Complete or restore that extraction first"
        for line in errors.split(whereSeparator: \.isNewline) {
            guard let marker = line.range(of: prefix) else { continue }
            let reported = line[marker.upperBound...]
            return reported.hasSuffix(suffix) ? String(reported.dropLast(suffix.count)) : String(reported)
        }
        return ""
    }

    static func tool(_ result: ArchiveProcessResult) -> ArchiveFailure? {
        result.status == 0 ? nil : .failed(detail(result))
    }

    /// The last thing the tool said, without its `error:` prefix.
    static func detail(_ result: ArchiveProcessResult) -> String {
        let said = [result.errors, result.output].lazy
            .compactMap { $0.split(whereSeparator: \.isNewline).last.map(String.init) }.first ?? ""
        let line = said.trimmingCharacters(in: .whitespaces)
        return line.hasPrefix("error: ") ? String(line.dropFirst(7)) : line
    }

    var message: String {
        switch self {
        case .notArchive(let name):
            String(localized: "\(name) is not an archive Notchcast opens.", table: "NotchcastArchives")
        case .missingTool(let tool):
            String(localized: "\(tool.name) is not installed. Install it with: \(tool.installCommand)",
                   table: "NotchcastArchives")
        case .unsafe(let refusal): refusal.message
        case .noSpace(let detail):
            detail.isEmpty ? String(localized: "Not enough free space.", table: "NotchcastArchives") : detail
        case .damaged(let detail):
            detail.isEmpty ? String(localized: "The archive is damaged.", table: "NotchcastArchives") : detail
        case .password:
            String(localized: "The password was not accepted.", table: "NotchcastArchives")
        case .startedElsewhere:
            String(localized: "Finish this extraction with hatchzip first.", table: "NotchcastArchives")
        case .resumeJournalMismatch:
            String(localized: "Undo moves or renames, side files too.", table: "NotchcastArchives")
        case .failed(let detail):
            detail.isEmpty ? String(localized: "Extraction failed.", table: "NotchcastArchives") : detail
        case .nothingSelected:
            String(localized: "Select files or folders in Finder first.", table: "NotchcastArchives")
        case .automationRefused:
            String(localized: "Allow Automation access to read the Finder selection.", table: "NotchcastArchives")
        case .severalFolders:
            String(localized: "Select items from one folder.", table: "NotchcastArchives")
        case .notWritable(let folder):
            String(localized: "Notchcast cannot write to \(folder).", table: "NotchcastArchives")
        case .notCompressible(let name):
            String(localized: "\(name) cannot be compressed.", table: "NotchcastArchives")
        case .busy(let name):
            String(localized: "Wait for \(name) to finish.", table: "NotchcastArchives")
        case .compressionFailed(let detail):
            detail.isEmpty ? String(localized: "Compression failed.", table: "NotchcastArchives") : detail
        }
    }
}
