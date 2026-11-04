import Foundation
import NaturalLanguage

struct EditorStatistics: Sendable {
    let words: Int
    let characters: Int
    let lines: Int

    @concurrent
    static func count(_ source: String) async -> Self {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = source
        var words = 0
        tokenizer.enumerateTokens(in: source.startIndex..<source.endIndex) { _, _ in
            words += 1
            return true
        }
        return Self(
            words: words, characters: EditorTextPolicy.characterCount(source),
            lines: EditorTextPolicy.lineCount(source))
    }
}
