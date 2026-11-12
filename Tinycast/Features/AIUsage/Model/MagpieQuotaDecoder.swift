import Foundation

nonisolated enum MagpieQuotaDecoder {
    private struct Response: Decodable {
        let object: String
        let data: [Account]
    }

    private struct Account: Decodable {
        let provider: String
        let name: String
        let alias: String?
        let plan: String?
        let windows: [WindowEntry]
        let readAt: Date
        let asOf: Date?
    }

    private struct Window: Decodable {
        let name: String
        let used: Double
        let resetsAt: Date?
    }

    private struct WindowEntry: Decodable {
        let value: Window?

        init(from decoder: any Decoder) {
            value = try? Window(from: decoder)
        }
    }

    static func decode(_ data: Data, now: Date) throws -> [AIUsageSnapshot] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            for fractional in [false, true] {
                let format = Date.ISO8601FormatStyle().year().month().day()
                    .time(includingFractionalSeconds: fractional).timeZone(separator: .colon)
                if let date = try? Date(value, strategy: format) { return date }
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid quota timestamp")
        }
        let response = try decoder.decode(Response.self, from: data)
        guard response.object == "list" else { throw CocoaError(.coderReadCorrupt) }
        return response.data.enumerated().map { index, account in
            let windows = account.windows.enumerated().compactMap { windowIndex, entry -> AIUsageSnapshot.Window? in
                guard let window = entry.value, window.used.isFinite else { return nil }
                return AIUsageSnapshot.Window(
                    id: String(windowIndex), label: window.name, used: window.used, limit: 100,
                    resetsAt: window.resetsAt)
            }
            return AIUsageSnapshot(
                providerID: account.provider, plan: account.plan, checkedAt: account.readAt,
                status: account.asOf != nil || now.timeIntervalSince(account.readAt) > 15 * 60 ? .stale : .available,
                windows: windows, accountID: "\(account.provider)-\(index)",
                accountName: account.alias.flatMap { $0.isEmpty ? nil : $0 } ?? account.name, asOf: account.asOf)
        }
    }
}
