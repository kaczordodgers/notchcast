import Foundation

enum TodoFilterParser {
    static func parse(
        _ source: String,
        projectNames: [String]? = nil,
        labelNames: [String]? = nil,
        sectionNames: [String]? = nil,
        dateResolver: (String) -> Date?
    ) throws(TodoFilterError) -> TodoFilterQuery {
        var parser = Parser(
            characters: Array(source), tokens: TodoFilterLexer.tokenize(source),
            projectNames: projectNames, labelNames: labelNames, sectionNames: sectionNames)
        return try parser.parse(dateResolver: dateResolver)
    }

    private struct Parser {
        let characters: [Character]
        let tokens: [TodoFilterLexer.Token]
        let projectNames: [String]?
        let labelNames: [String]?
        let sectionNames: [String]?
        var index = 0
        var parenthesisDepth = 0

        var token: TodoFilterLexer.Token? { index < tokens.count ? tokens[index] : nil }

        var currentRange: Range<Int> { token?.characterRange ?? characters.count..<characters.count }

        mutating func parse(dateResolver: (String) -> Date?) throws(TodoFilterError) -> TodoFilterQuery {
            var lists = [try parseOr(dateResolver: dateResolver)]
            while token?.kind == .comma {
                index += 1
                lists.append(try parseOr(dateResolver: dateResolver))
            }
            if let token {
                throw TodoFilterError(
                    characterRange: token.characterRange,
                    reason: token.kind == .rightParenthesis ? .unbalancedParenthesis : .implicitAnd)
            }
            return TodoFilterQuery(lists: lists)
        }

        mutating func parseOr(dateResolver: (String) -> Date?) throws(TodoFilterError) -> TodoFilterQuery.Expression {
            var expression = try parseAnd(dateResolver: dateResolver)
            while token?.kind == .or {
                index += 1
                expression = .or(expression, try parseAnd(dateResolver: dateResolver))
            }
            return expression
        }

        mutating func parseAnd(dateResolver: (String) -> Date?) throws(TodoFilterError) -> TodoFilterQuery.Expression {
            var expression = try parseUnary(dateResolver: dateResolver)
            while token?.kind == .and {
                index += 1
                expression = .and(expression, try parseUnary(dateResolver: dateResolver))
            }
            return expression
        }

        mutating func parseUnary(dateResolver: (String) -> Date?) throws(TodoFilterError) -> TodoFilterQuery.Expression {
            guard let token else {
                throw TodoFilterError(characterRange: currentRange, reason: .missingOperand)
            }
            switch token.kind {
            case .not:
                index += 1
                return .not(try parseUnary(dateResolver: dateResolver))
            case .leftParenthesis:
                index += 1
                parenthesisDepth += 1
                guard self.token != nil else {
                    throw TodoFilterError(characterRange: token.characterRange, reason: .unbalancedParenthesis)
                }
                let expression = try parseOr(dateResolver: dateResolver)
                guard self.token?.kind == .rightParenthesis else {
                    if self.token == nil || self.token?.kind == .comma {
                        throw TodoFilterError(characterRange: token.characterRange, reason: .unbalancedParenthesis)
                    }
                    throw TodoFilterError(characterRange: currentRange, reason: .implicitAnd)
                }
                index += 1
                parenthesisDepth -= 1
                return expression
            case .word(let word):
                return .operand(try parseOperand(word, dateResolver: dateResolver))
            case .rightParenthesis:
                throw TodoFilterError(characterRange: token.characterRange,
                                      reason: parenthesisDepth > 0 ? .missingOperand : .unbalancedParenthesis)
            default:
                throw TodoFilterError(characterRange: token.characterRange, reason: .missingOperand)
            }
        }

        mutating func parseOperand(
            _ word: String, dateResolver: (String) -> Date?
        ) throws(TodoFilterError) -> TodoFilterQuery.Operand {
            if word.hasPrefix("#") || word.hasPrefix("@") || word.hasPrefix("/") {
                return try parseName(word)
            }
            let start = currentRange.lowerBound
            index += 1
            switch word.lowercased() {
            case "today": return .today
            case "tomorrow": return .tomorrow
            case "overdue": return .overdue
            case "recurring": return .recurring
            case "subtask": return .subtask
            case "all": return .all
            case "p1": return .priority(4)
            case "p2": return .priority(3)
            case "p3": return .priority(2)
            case "p4": return .priority(1)
            case "no":
                if consumeWord("date") { return .noDate }
                if consumeWord("labels") { return .noLabels }
            case "search":
                guard token?.kind == .colon else { break }
                index += 1
                let range = try consumeText()
                return .search(text(range))
            case "due":
                let before = consumeWord("before")
                guard before || consumeWord("after"), token?.kind == .colon else { break }
                index += 1
                let range = try consumeText()
                let value = text(range)
                guard let date = dateResolver(value) else {
                    throw TodoFilterError(characterRange: range, reason: .invalidDate(value))
                }
                return before ? .dueBefore(date) : .dueAfter(date)
            case "next":
                return try parseDays(start: start)
            default:
                if word.allSatisfy(\.isNumber) {
                    index -= 1
                    return try parseDays(start: start)
                }
            }
            throw TodoFilterError(characterRange: start..<tokens[index - 1].characterRange.upperBound,
                                  reason: .unknownOperand(text(start..<tokens[index - 1].characterRange.upperBound)))
        }

        mutating func parseDays(start: Int) throws(TodoFilterError) -> TodoFilterQuery.Operand {
            guard let token, case .word(let value) = token.kind else {
                throw TodoFilterError(characterRange: currentRange, reason: .missingOperand)
            }
            index += 1
            guard let count = Int(value), count > 0 else {
                throw TodoFilterError(characterRange: token.characterRange, reason: .invalidDayCount)
            }
            guard consumeWord("days") else {
                throw TodoFilterError(characterRange: start..<token.characterRange.upperBound,
                                      reason: .unknownOperand(text(start..<token.characterRange.upperBound)))
            }
            return .days(count)
        }

        mutating func parseName(_ word: String) throws(TodoFilterError) -> TodoFilterQuery.Operand {
            let range = currentRange
            let prefixCount = word.hasPrefix("##") ? 2 : 1
            let names = word.hasPrefix("#") ? projectNames : word.hasPrefix("@") ? labelNames : sectionNames
            let start = range.lowerBound + prefixCount
            guard start < range.upperBound else {
                throw TodoFilterError(characterRange: range, reason: .missingOperand)
            }
            var end = index + 1
            var match: (end: Int, name: String)?
            repeat {
                let name = text(start..<tokens[end - 1].characterRange.upperBound)
                if names == nil || names?.contains(where: {
                    $0.compare(name, options: .caseInsensitive) == .orderedSame
                }) == true {
                    match = (end, name)
                }
                if names == nil { break }
                guard end < tokens.count, case .word(let next) = tokens[end].kind,
                      !next.hasPrefix("#"), !next.hasPrefix("@"), !next.hasPrefix("/") else { break }
                end += 1
            } while true
            guard let match else {
                let nameRange = start..<tokens[end - 1].characterRange.upperBound
                let name = text(nameRange)
                let reason: TodoFilterError.Reason = word.hasPrefix("#") ? .unknownProject(name)
                    : word.hasPrefix("@") ? .unknownLabel(name) : .unknownSection(name)
                throw TodoFilterError(characterRange: range.lowerBound..<nameRange.upperBound, reason: reason)
            }
            index = match.end
            if word.hasPrefix("#") { return .project(match.name, includingSubprojects: prefixCount == 2) }
            if word.hasPrefix("@") { return .label(match.name) }
            return .section(match.name)
        }

        mutating func consumeWord(_ expected: String) -> Bool {
            guard let token, case .word(let word) = token.kind, word.lowercased() == expected else { return false }
            index += 1
            return true
        }

        mutating func consumeText() throws(TodoFilterError) -> Range<Int> {
            let start = currentRange.lowerBound
            var end = start
            while let token {
                switch token.kind {
                case .word, .colon: break
                default: return try textRange(start: start, end: end)
                }
                if case .word(let word) = token.kind,
                   word.hasPrefix("#") || word.hasPrefix("@") || word.hasPrefix("/") { break }
                end = token.characterRange.upperBound
                index += 1
            }
            return try textRange(start: start, end: end)
        }

        func textRange(start: Int, end: Int) throws(TodoFilterError) -> Range<Int> {
            guard end > start else {
                throw TodoFilterError(characterRange: currentRange, reason: .missingOperand)
            }
            return start..<end
        }

        func text(_ range: Range<Int>) -> String { String(characters[range]) }
    }
}
