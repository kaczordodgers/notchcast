import Foundation

struct RaycastTheme: Codable, Hashable, Identifiable, Sendable {
    enum Appearance: String, Codable, Sendable, CaseIterable {
        case light, dark
    }

    enum ValidationError: Error {
        case invalidTheme, wrongAppearance
    }

    let name: String
    let author: String
    let appearance: Appearance
    let colors: [String]

    var id: String { "\(appearance.rawValue):\(name) · \(author)" }

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && colors.count == 12 && colors.allSatisfy { Self.hex6($0) != nil }
    }

    init(name: String, author: String, appearance: Appearance, colors: [String]) {
        self.name = name
        self.author = author
        self.appearance = appearance
        self.colors = colors.map { Self.hex6($0) ?? $0 }
    }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            name: try values.decode(String.self, forKey: .name),
            author: try values.decode(String.self, forKey: .author),
            appearance: try values.decode(Appearance.self, forKey: .appearance),
            colors: try values.decode([String].self, forKey: .colors))
        guard isValid else { throw ValidationError.invalidTheme }
    }

    // Theme Studio's optional alpha pair must never override Tinycast's token alphas.
    static func hex6(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("#") else { return nil }
        let digits = trimmed.dropFirst()
        guard digits.count == 6 || digits.count == 8,
            digits.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) })
        else { return nil }
        return "#" + digits.prefix(6).uppercased()
    }
}
