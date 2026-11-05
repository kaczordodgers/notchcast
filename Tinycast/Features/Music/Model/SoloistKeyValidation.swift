import Foundation

enum SoloistKeyValidation {
    static let maximumBytes = 4_096

    static func validated(_ pasted: String) throws -> String {
        if let problem = problem(in: pasted) { throw SoloistFailure.invalidKey.detail("refused: \(problem)") }
        return pasted.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Which check refuses the text, never its content. A plain loop on purpose: Xcode 27.1 linked
    /// `unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)` to `allSatisfy`'s helper.
    static func problem(in pasted: String) -> String? {
        guard pasted.utf8.count <= maximumBytes else { return "longer than \(maximumBytes) bytes" }
        let key = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return "empty" }
        for scalar in key.unicodeScalars {
            if scalar.properties.isWhitespace { return "space or line break" }
            switch scalar.properties.generalCategory {
            case .control, .format: return "hidden character"
            default: continue
            }
        }
        return nil
    }
}
