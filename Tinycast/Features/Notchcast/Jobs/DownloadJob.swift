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

    /// Nil when the job carries none, as one queued by a build that stored options differently does.
    func options<Options: Decodable>(_ type: Options.Type = Options.self) throws -> Options? {
        try encodedOptions.map { try JSONDecoder().decode(type, from: $0) }
    }
}
