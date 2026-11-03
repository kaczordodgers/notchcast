import Foundation

enum SoloistKeyValidation {
    static let maximumBytes = 4_096

    static func validated(_ pasted: String) throws -> String {
        guard pasted.utf8.count <= maximumBytes else { throw SoloistFailure.invalidKey }
        let key = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !key.contains(where: { $0.isWhitespace || $0.isNewline }),
              !key.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            throw SoloistFailure.invalidKey
        }
        return key
    }
}
