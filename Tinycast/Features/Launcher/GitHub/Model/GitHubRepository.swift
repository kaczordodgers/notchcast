import Foundation

struct GitHubRepository: Decodable, Sendable, Equatable, Identifiable {
    let fullName: String
    let description: String?
    let stars: Int
    var isStarred = false

    var id: String { fullName.lowercased() }
    var name: String { String(fullName.split(separator: "/").last ?? "") }
    var owner: String { String(fullName.split(separator: "/").first ?? "") }
    var url: URL { URL(string: "https://github.com/\(fullName)")! }

    enum CodingKeys: String, CodingKey {
        case fullName = "full_name", description, stars = "stargazers_count"
    }

    init(fullName: String, description: String?, stars: Int) throws {
        let parts = fullName.split(separator: "/", omittingEmptySubsequences: false)
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        guard parts.count == 2, parts.allSatisfy({ part in
            !part.isEmpty && part != "." && part != ".."
                && part.unicodeScalars.allSatisfy(allowed.contains)
        }), stars >= 0 else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Invalid repository"))
        }
        self.fullName = fullName
        self.description = description
        self.stars = stars
    }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(fullName: values.decode(String.self, forKey: .fullName),
                      description: values.decodeIfPresent(String.self, forKey: .description),
                      stars: values.decode(Int.self, forKey: .stars))
    }
}
