import Foundation

struct MachineBackupConfiguration: Sendable, Equatable {
    let jobLabel: String
    let userID: UInt32
    let resticExecutable: URL
    let repository: String
    let host: String
    let passwordCommand: String
    let homeDirectory: URL

    var downloadsDirectory: URL { homeDirectory.appendingPathComponent("Downloads", isDirectory: true) }

    func validate() throws {
        let labelCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-_"))
        guard !jobLabel.isEmpty, jobLabel.unicodeScalars.allSatisfy(labelCharacters.contains),
              resticExecutable.isFileURL, resticExecutable.path.hasPrefix("/"),
              !repository.isEmpty, !host.isEmpty, !passwordCommand.isEmpty,
              homeDirectory.isFileURL, homeDirectory.path.hasPrefix("/"),
              homeDirectory.path != "/" else { throw MachineBackupFailure.configuration }
    }
}
