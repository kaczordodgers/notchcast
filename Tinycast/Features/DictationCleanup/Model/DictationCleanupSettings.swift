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
}
