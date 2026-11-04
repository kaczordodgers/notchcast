import Foundation

struct BuildStatsSnapshot: Codable, Sendable, Equatable {
    struct TokenUsage: Codable, Sendable, Equatable {
        let model: String
        let effort: String
        let inputTokens: Int64
        let outputTokens: Int64
    }

    struct DatedEntry: Codable, Sendable, Equatable {
        let date: String
        let summary: String
    }

    enum ValidationError: Error, Equatable {
        case unsupportedVersion(Int)
        case limitExceeded(String)
        case invalidValue(String)
        case invalidDate(String)
        case datesOutOfOrder(String)
    }

    static let currentVersion = 1
    static let maximumBytes = 1_048_576
    static let maximumEntries = 1_000
    static let maximumMetrics = 100
    static let maximumLabelBytes = 80
    static let maximumSummaryBytes = 2_000

    let schemaVersion: Int
    let tokens: [TokenUsage]
    let timeline: [DatedEntry]
    let changelog: [DatedEntry]
    let qualityMetrics: [String: Double]

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, tokens, timeline, changelog, qualityMetrics
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == Self.currentVersion else {
            throw ValidationError.unsupportedVersion(schemaVersion)
        }
        tokens = try container.decode([TokenUsage].self, forKey: .tokens)
        timeline = try container.decode([DatedEntry].self, forKey: .timeline)
        changelog = try container.decode([DatedEntry].self, forKey: .changelog)
        qualityMetrics = try container.decode([String: Double].self, forKey: .qualityMetrics)
        try validate()
    }

    static func decode(_ data: Data) throws -> Self {
        guard data.count <= maximumBytes else { throw ValidationError.limitExceeded("bytes") }
        return try JSONDecoder().decode(Self.self, from: data)
    }

    func validate() throws {
        guard schemaVersion == Self.currentVersion else {
            throw ValidationError.unsupportedVersion(schemaVersion)
        }
        guard tokens.count <= Self.maximumEntries else { throw ValidationError.limitExceeded("tokens") }
        var groups = Set<[String]>()
        for usage in tokens {
            try Self.validateText(usage.model, limit: Self.maximumLabelBytes, field: "model")
            try Self.validateText(usage.effort, limit: Self.maximumLabelBytes, field: "effort")
            guard usage.inputTokens >= 0, usage.outputTokens >= 0 else {
                throw ValidationError.invalidValue("tokens")
            }
            guard groups.insert([usage.model, usage.effort]).inserted else {
                throw ValidationError.invalidValue("duplicate token group")
            }
        }
        try Self.validateEntries(timeline, field: "timeline")
        try Self.validateEntries(changelog, field: "changelog")
        guard qualityMetrics.count <= Self.maximumMetrics else {
            throw ValidationError.limitExceeded("qualityMetrics")
        }
        for (name, value) in qualityMetrics {
            try Self.validateText(name, limit: Self.maximumLabelBytes, field: "metric name")
            guard value.isFinite, value >= 0 else { throw ValidationError.invalidValue("metric value") }
        }
    }

    private static func validateText(_ text: String, limit: Int, field: String) throws {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ValidationError.invalidValue(field)
        }
        guard text.utf8.count <= limit else { throw ValidationError.limitExceeded(field) }
    }

    private static func validateEntries(_ entries: [DatedEntry], field: String) throws {
        guard entries.count <= maximumEntries else { throw ValidationError.limitExceeded(field) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        var previous = ""
        for entry in entries {
            guard entry.date.utf8.count == 10,
                  let date = formatter.date(from: entry.date),
                  formatter.string(from: date) == entry.date else {
                throw ValidationError.invalidDate(field)
            }
            guard entry.date >= previous else { throw ValidationError.datesOutOfOrder(field) }
            previous = entry.date
            try validateText(entry.summary, limit: maximumSummaryBytes, field: "summary")
        }
    }
}
