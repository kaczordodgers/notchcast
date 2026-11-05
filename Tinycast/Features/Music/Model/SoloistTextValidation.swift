import Foundation

enum SoloistTextValidation {
    static func hasControlCharacters(_ text: String) -> Bool {
        // A plain loop avoids Xcode 27.1 miscompiling CharacterSet predicate helpers in Release.
        for scalar in text.unicodeScalars {
            guard !CharacterSet.controlCharacters.contains(scalar) else { return true }
        }
        return false
    }
}
