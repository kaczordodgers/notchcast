import Foundation

enum TodoFilterLexer {
    struct Token: Equatable, Sendable {
        enum Kind: Equatable, Sendable {
            case word(String)
            case and
            case or
            case not
            case leftParenthesis
            case rightParenthesis
            case comma
            case colon
        }

        let kind: Kind
        let characterRange: Range<Int>
    }

    static func tokenize(_ source: String) -> [Token] {
        let characters = Array(source)
        var tokens: [Token] = []
        var index = 0
        while index < characters.count {
            if characters[index].isWhitespace {
                index += 1
                continue
            }
            let start = index
            if let kind = punctuation(characters[index]) {
                index += 1
                tokens.append(Token(kind: kind, characterRange: start..<index))
                continue
            }
            while index < characters.count,
                  !characters[index].isWhitespace, punctuation(characters[index]) == nil {
                index += 1
            }
            tokens.append(Token(kind: .word(String(characters[start..<index])), characterRange: start..<index))
        }
        return tokens
    }

    private static func punctuation(_ character: Character) -> Token.Kind? {
        switch character {
        case "&": .and
        case "|": .or
        case "!": .not
        case "(": .leftParenthesis
        case ")": .rightParenthesis
        case ",": .comma
        case ":": .colon
        default: nil
        }
    }
}
