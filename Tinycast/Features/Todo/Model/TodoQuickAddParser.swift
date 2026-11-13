import Foundation

/// Double quotes protect phrases; a leading backslash protects one word; both stay in the title.
struct TodoQuickAddParser: Sendable {
    private(set) var text: String
    private(set) var draft: TodoQuickAddDraft
    private let projects: [String]
    private let sections: [String]
    private let labels: [String]
    private let dateParser: @Sendable (String) -> TodoQuickAddDate?
    private var revertedRanges: [NSRange] = []

    init(
        text: String = "", projects: [String] = [], sections: [String] = [], labels: [String] = [],
        dateParser: @escaping @Sendable (String) -> TodoQuickAddDate? = { _ in nil }
    ) {
        self.text = text
        self.projects = projects
        self.sections = sections
        self.labels = labels
        self.dateParser = dateParser
        draft = Self.parse(text, projects: projects, sections: sections, labels: labels, dateParser: dateParser)
    }

    /// Date callbacks see UTF-16-preserving masks and return nil when no unmasked phrase remains.
    static func parse(
        _ text: String, projects: [String] = [], sections: [String] = [], labels: [String] = [],
        dateParser: (String) -> TodoQuickAddDate? = { _ in nil }
    ) -> TodoQuickAddDraft {
        parse(text, projects: projects, sections: sections, labels: labels, dateParser: dateParser, revertedRanges: [])
    }

    @discardableResult
    mutating func parse(_ text: String) -> TodoQuickAddDraft {
        remapRevertedRanges(to: text)
        self.text = text
        draft = Self.parse(
            text, projects: projects, sections: sections, labels: labels,
            dateParser: dateParser, revertedRanges: revertedRanges)
        return draft
    }

    /// Accepts a UTF-16 position inside a token or the caret immediately after it.
    @discardableResult
    mutating func revert(tokenAt offset: Int) -> TodoQuickAddDraft {
        guard offset >= 0, offset <= text.utf16.count else { return draft }
        guard let token = draft.tokens.first(where: { NSLocationInRange(offset, $0.range) })
            ?? draft.tokens.first(where: { NSMaxRange($0.range) == offset })
        else { return draft }
        revertedRanges.append(token.range)
        return parse(text)
    }

    /// Highlight ranges belong to each untrimmed line, so leading whitespace keeps its offsets.
    static func splitPaste(
        _ text: String, projects: [String] = [], sections: [String] = [], labels: [String] = [],
        dateParser: (String) -> TodoQuickAddDate? = { _ in nil }
    ) -> (drafts: [TodoQuickAddDraft], count: Int) {
        let drafts = text.components(separatedBy: .newlines)
            .filter { $0.contains { !$0.isWhitespace } }
            .map { parse($0, projects: projects, sections: sections, labels: labels, dateParser: dateParser) }
        return (drafts, drafts.count)
    }

    func splitPaste(_ text: String) -> (drafts: [TodoQuickAddDraft], count: Int) {
        Self.splitPaste(text, projects: projects, sections: sections, labels: labels, dateParser: dateParser)
    }

    private mutating func remapRevertedRanges(to newText: String) {
        guard !revertedRanges.isEmpty, !newText.utf16.elementsEqual(text.utf16) else { return }
        let old = Array(text.utf16)
        let new = Array(newText.utf16)
        let changes = new.difference(from: old)
        let removed = Set(changes.removals.map { change in
            switch change {
            case .remove(let offset, _, _), .insert(let offset, _, _): offset
            }
        })
        let inserted = Set(changes.insertions.map { change in
            switch change {
            case .remove(let offset, _, _), .insert(let offset, _, _): offset
            }
        })
        var positions: [Int: Int] = [:]
        var newOffset = 0
        for oldOffset in old.indices where !removed.contains(oldOffset) {
            while inserted.contains(newOffset) { newOffset += 1 }
            positions[oldOffset] = newOffset
            newOffset += 1
        }
        revertedRanges = revertedRanges.compactMap { range in
            let offsets = range.location..<NSMaxRange(range)
            guard let start = positions[range.location],
                offsets.allSatisfy({ positions[$0] == start + $0 - range.location })
            else { return nil }
            return NSRange(location: start, length: range.length)
        }
    }

    private static func parse(
        _ text: String, projects: [String], sections: [String], labels: [String],
        dateParser: (String) -> TodoQuickAddDate?, revertedRanges: [NSRange]
    ) -> TodoQuickAddDraft {
        let protected = protectedRanges(in: text) + revertedRanges
        var candidates = namedCandidates(in: text, projects: projects, sections: sections, labels: labels)
            .filter { candidate in !protected.contains { NSIntersectionRange($0, candidate.range).length > 0 } }
        candidates += dateCandidates(in: text, excluding: protected + candidates.map(\.range), dateParser: dateParser)
        var winners: [TodoQuickAddToken.Kind: Candidate] = [:]
        for candidate in candidates.sorted(by: { $0.range.location < $1.range.location }) {
            winners[candidate.kind] = candidate
        }
        let active = winners.values.sorted { $0.range.location < $1.range.location }
        var draft = TodoQuickAddDraft(title: title(in: text, removing: active.map(\.range)))
        for candidate in active {
            switch candidate.value {
            case .project(let name): draft.project = name
            case .section(let name): draft.section = name
            case .label(let name): draft.labels = [name]
            case .priority(let priority): draft.priority = priority
            case .date(let date): draft.date = date
            }
            draft.tokens.append(TodoQuickAddToken(kind: candidate.kind, range: candidate.range))
        }
        return draft
    }

    private enum Value {
        case project(String)
        case section(String)
        case label(String)
        case priority(Int)
        case date(TodoQuickAddDate)
    }

    private struct Candidate {
        let value: Value
        let range: NSRange

        var kind: TodoQuickAddToken.Kind {
            switch value {
            case .project: .project
            case .section: .section
            case .label: .label
            case .priority: .priority
            case .date: .date
            }
        }
    }

    private static func namedCandidates(
        in text: String, projects: [String], sections: [String], labels: [String]
    ) -> [Candidate] {
        var result: [Candidate] = []
        var index = text.startIndex
        while index < text.endIndex {
            guard index == text.startIndex || text[text.index(before: index)].isWhitespace else {
                text.formIndex(after: &index)
                continue
            }
            let names: [String]
            let makeValue: (String) -> Value
            switch text[index] {
            case "#": (names, makeValue) = (projects, Value.project)
            case "/": (names, makeValue) = (sections, Value.section)
            case "@": (names, makeValue) = (labels, Value.label)
            default: (names, makeValue) = ([], Value.label)
            }
            let start = text.index(after: index)
            var longest: (name: String, end: String.Index)?
            for name in names where !name.isEmpty && !name.contains(where: \.isNewline) {
                guard let range = text.range(of: name, options: [.anchored, .caseInsensitive], range: start..<text.endIndex),
                    isEndBoundary(range.upperBound, in: text),
                    range.upperBound > (longest?.end ?? start)
                else { continue }
                longest = (name, range.upperBound)
            }
            if let longest {
                result.append(Candidate(value: makeValue(longest.name), range: NSRange(index..<longest.end, in: text)))
                index = longest.end
                continue
            }
            if text[index] == "p" || text[index] == "P", start < text.endIndex,
                let number = text[start].wholeNumberValue, (1...4).contains(number),
                text[start].isASCII
            {
                let end = text.index(after: start)
                if isEndBoundary(end, in: text) {
                    result.append(Candidate(value: .priority(5 - number), range: NSRange(index..<end, in: text)))
                    index = end
                    continue
                }
            }
            text.formIndex(after: &index)
        }
        return result
    }

    private static func isEndBoundary(_ index: String.Index, in text: String) -> Bool {
        index == text.endIndex || text[index].isWhitespace
    }

    private static func protectedRanges(in text: String) -> [NSRange] {
        var ranges: [NSRange] = []
        var index = text.startIndex
        while index < text.endIndex {
            let start = index
            if text[index] == "\"" {
                text.formIndex(after: &index)
                while index < text.endIndex {
                    let character = text[index]
                    text.formIndex(after: &index)
                    if character == "\"" { break }
                    if character == "\\", index < text.endIndex { text.formIndex(after: &index) }
                }
            } else if text[index] == "\\",
                index == text.startIndex || text[text.index(before: index)].isWhitespace
            {
                while index < text.endIndex, !text[index].isWhitespace { text.formIndex(after: &index) }
            } else {
                text.formIndex(after: &index)
                continue
            }
            ranges.append(NSRange(start..<index, in: text))
        }
        return ranges
    }

    /// The callback returns one match per call; consumed ranges become spaces with equal UTF-16 length.
    private static func dateCandidates(
        in text: String, excluding ranges: [NSRange], dateParser: (String) -> TodoQuickAddDate?
    ) -> [Candidate] {
        var units = Array(text.utf16)
        for range in ranges {
            units.replaceSubrange(range.location..<NSMaxRange(range), with: repeatElement(0xFFFC, count: range.length))
        }
        var excluded = ranges
        var result: [Candidate] = []
        while let date = dateParser(String(decoding: units, as: UTF16.self)) {
            let range = date.range
            guard range.location >= 0, range.length > 0, range.location <= units.count,
                range.length <= units.count - range.location,
                let indices = Range(range, in: text),
                text.indices.contains(indices.lowerBound),
                indices.upperBound == text.endIndex || text.indices.contains(indices.upperBound),
                !excluded.contains(where: { NSIntersectionRange($0, range).length > 0 })
            else { break }
            excluded.append(range)
            units.replaceSubrange(range.location..<NSMaxRange(range), with: repeatElement(32, count: range.length))
            guard indices.lowerBound == text.startIndex || text[text.index(before: indices.lowerBound)].isWhitespace,
                isEndBoundary(indices.upperBound, in: text), text[indices].contains(where: { !$0.isWhitespace })
            else { continue }
            result.append(Candidate(value: .date(date), range: range))
        }
        return result
    }

    private static func title(in text: String, removing ranges: [NSRange]) -> String {
        var title = ""
        var start = text.startIndex
        for range in ranges {
            guard let indices = Range(range, in: text) else { continue }
            title += text[start..<indices.lowerBound]
            start = indices.upperBound
        }
        title += text[start...]
        return title.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
