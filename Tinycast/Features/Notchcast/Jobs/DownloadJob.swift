import Foundation

struct DownloadJob: Codable, Sendable, Identifiable, Equatable {
    var id: String
    var kind: String
    var source: String
    var title: String
    var group: String?
    var state: DownloadState = .waiting
    var progress: DownloadProgress?
    var output: String?
    var detail: String?
    var created: Date
    var finished: Date?
    /// The runner's own `Options` type as JSON, so a producer and its runner share one set of fields.
    var encodedOptions: Data?

    static func encode(_ options: some Encodable) throws -> Data { try JSONEncoder().encode(options) }

    /// A job queued without options decodes as one whose every option is unset.
    func options<Options: Decodable>(_ type: Options.Type = Options.self) throws -> Options {
        try JSONDecoder().decode(type, from: encodedOptions ?? Data("{}".utf8))
    }
}
