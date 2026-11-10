import Foundation

enum EditorTextPolicy {
    static func accepts(_ next: String, after previous: String, brainDump: Bool) -> Bool {
        !brainDump || next.count > previous.count
            || trimmingTrailingWhitespace(next).utf8.elementsEqual(trimmingTrailingWhitespace(previous).utf8)
    }

    static func characterCount(_ source: String) -> Int {
        source.filter { !$0.unicodeScalars.allSatisfy(CharacterSet.newlines.contains) }.count
    }

    static func lineCount(_ source: String) -> Int {
        1 + source.filter { $0.unicodeScalars.allSatisfy(CharacterSet.newlines.contains) }.count
    }

    static func horizontalInset(
        width: Double, pointSize: Double, columnCharacters: Int?, glyphWidth: Double, fullScreen: Bool = false
    ) -> Double {
        let padding = 8 + (fullScreen ? 3 : 1.8) * pointSize
        guard let columnCharacters else { return padding }
        return padding + max(0, (width - 2 * padding - Double(columnCharacters) * glyphWidth) / 2).rounded()
    }

    private static func trimmingTrailingWhitespace(_ source: String) -> Substring {
        source.dropLast(source.reversed().prefix(while: \.isWhitespace).count)
    }
}
