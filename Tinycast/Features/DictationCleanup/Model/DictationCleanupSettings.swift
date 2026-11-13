import Foundation

struct DictationCleanupSettings: Codable, Equatable, Sendable {
    static let promptLimit = 16_384
    static let vocabularyLimit = 500
    static let misheardFormsLimit = 50
    static let termLimit = 256
    enum Effort: String, Codable, CaseIterable, Sendable {
        case low, medium, high
    }

    struct VocabularyTerm: Codable, Equatable, Sendable {
        var spelling: String
        var misheardForms: [String] = []
    }

    var isEnabled = false
    var baseURL = MagpieGateway.defaultAddress
    var effort: Effort = .low
    var promptAddition = ""
    var vocabulary: [VocabularyTerm] = []

    static func vocabularyInput(_ text: String) -> String {
        text.components(separatedBy: "\n").prefix(vocabularyLimit).map { line in
            line.components(separatedBy: "|").prefix(misheardFormsLimit + 1)
                .map { String($0.prefix(termLimit)) }.joined(separator: "|")
        }.joined(separator: "\n")
    }

    static func vocabulary(from text: String) -> [VocabularyTerm] {
        vocabularyInput(text).components(separatedBy: "\n").map { line in
            let parts = line.components(separatedBy: "|").map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return .init(spelling: parts[0], misheardForms: Array(parts.dropFirst()))
        }
    }
}
