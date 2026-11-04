import Foundation

struct DictationCleanupSettings: Codable, Equatable, Sendable {
    enum Effort: String, Codable, CaseIterable, Sendable {
        case low, medium, high
    }

    struct VocabularyTerm: Codable, Equatable, Sendable {
        var spelling: String
        var misheardForms: [String] = []
    }

    var isEnabled = false
    var baseURL = "http://127.0.0.1:8317"
    var effort: Effort = .low
    var promptAddition = ""
    var vocabulary: [VocabularyTerm] = []

    static func vocabulary(from text: String) -> [VocabularyTerm] {
        text.components(separatedBy: "\n").map { line in
            let parts = line.components(separatedBy: "|").map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return .init(spelling: parts[0], misheardForms: Array(parts.dropFirst()))
        }
    }
}
