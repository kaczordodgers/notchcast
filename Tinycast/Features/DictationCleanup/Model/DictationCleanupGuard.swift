import Foundation

enum DictationCleanupGuard {
    static func accepts(
        _ reply: String, raw: String, vocabulary: [DictationCleanupSettings.VocabularyTerm]
    ) -> Bool {
        guard reply.count <= raw.count * 2 + 128 else { return false }
        let heard = canonicalWords(raw, vocabulary: vocabulary)
        let spoken = heard.filter { !isHesitation($0) }
        let written = canonicalWords(reply, vocabulary: vocabulary)
        if written.isEmpty { return spoken.isEmpty }
        guard !spoken.isEmpty, heard.count <= 4_096, written.count <= 4_096 else { return false }
        guard written.count <= spoken.count + max(1, spoken.count / 5) else { return false }
        let correction = heard.contains("znaczy") || heard.contains("raczej")
            || zip(heard, heard.dropFirst()).contains { $0 == "a" && $1 == "nie" }
        if !correction {
            for negation in ["nie", "not", "never", "bez", "no", "without", "neither", "nor",
                             "nobody", "nothing", "nowhere", "none", "cannot", "don", "doesn",
                             "didn", "isn", "aren", "wasn", "weren", "haven", "hasn", "hadn",
                             "won", "wouldn", "shouldn", "couldn", "mustn", "needn", "shan", "ain"] {
                guard heard.filter({ $0 == negation }).count == written.filter({ $0 == negation }).count
                else { return false }
            }
        }
        let question = fold(raw).trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        if raw.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("?")
            || question.hasSuffix("znak zapytania") || question.hasSuffix("question mark") {
            guard reply.contains("?") else { return false }
        }
        let joined = zip(heard, heard.dropFirst()).map { $0 + $1 }
        let known = heard + joined
        for word in vocabulary.flatMap({ words($0.spelling) })
            where written.contains(where: { related($0, word) && !known.contains($0) }) {
            return false
        }
        let novel = written.filter { word in
            !word.allSatisfy(\.isNumber) && !unitAbbreviations.contains(word)
                && !known.contains { related(word, $0) }
        }
        guard novel.count * 4 <= written.count else { return false }
        return distance(spoken, written) * 4 <= max(spoken.count, written.count) * 3
    }

    private static func canonicalWords(
        _ text: String, vocabulary: [DictationCleanupSettings.VocabularyTerm]
    ) -> [String] {
        var result = words(text)
        let replacements = vocabulary.flatMap { term in
            term.misheardForms.map { (words($0), words(term.spelling)) }
        }.filter { !$0.0.isEmpty && !$0.1.isEmpty }.sorted { $0.0.count > $1.0.count }
        var index = 0
        while index < result.count {
            if let replacement = replacements.first(where: {
                result[index...].starts(with: $0.0)
                    || ($0.0.count == 1 && $0.1.count == 1
                        && result[index].hasPrefix($0.0[0])
                        && result[index].count - $0.0[0].count <= 3
                        && result[index].dropFirst($0.0[0].count).allSatisfy(\.isLetter))
            }) {
                var spelling = replacement.1
                if replacement.0.count == 1 && spelling.count == 1 {
                    spelling[0] += result[index].dropFirst(replacement.0[0].count)
                }
                result.replaceSubrange(index..<(index + replacement.0.count), with: spelling)
                index += replacement.1.count
            } else {
                index += 1
            }
        }
        return result
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: .diacriticInsensitive, locale: Locale(identifier: "pl_PL")).lowercased()
            .replacingOccurrences(of: "ł", with: "l").replacingOccurrences(of: "đ", with: "d")
    }

    private static func words(_ text: String) -> [String] {
        fold(text).replacingOccurrences(of: "\\bcan['’]t\\b", with: "cannot", options: .regularExpression)
            .split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }

    private static func isHesitation(_ word: String) -> Bool {
        ["uh", "um", "uhm", "ehm", "eh", "hm", "hmm", "mm", "mmm"].contains(word)
            || word.allSatisfy { $0 == "y" } || word.allSatisfy { $0 == "e" }
    }

    private static let unitAbbreviations: Set<String> = [
        "mg", "g", "kg", "ml", "l", "mm", "cm", "m", "km", "s", "min", "h", "zl"
    ]

    private static func related(_ first: String, _ second: String) -> Bool {
        if first == second { return true }
        let stem = zip(first, second).prefix { $0 == $1 }.count
        let shorter = min(first.count, second.count)
        let longer = max(first.count, second.count)
        if stem >= 4 && stem * 3 >= shorter * 2 { return true }
        guard longer >= 5 else { return false }
        return distance(Array(first), Array(second)) * 3 <= longer
    }

    private static func distance<Element: Equatable>(_ first: [Element], _ second: [Element]) -> Int {
        var row = Array(0...second.count)
        for (index, value) in first.enumerated() {
            var diagonal = row[0]
            row[0] = index + 1
            for (column, other) in second.enumerated() {
                let above = row[column + 1]
                row[column + 1] = min(above + 1, row[column] + 1, diagonal + (value == other ? 0 : 1))
                diagonal = above
            }
        }
        return row[second.count]
    }
}
