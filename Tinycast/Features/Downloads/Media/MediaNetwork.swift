import Foundation

nonisolated enum MediaNetwork {
    static func expectedSize(_ json: String) -> Int64? {
        guard let start = json.split(whereSeparator: \.isNewline).first(where: { $0.hasPrefix("{") }),
              let data = String(json[start.startIndex...]).data(using: .utf8),
              let info = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let formats = info["requested_formats"] as? [[String: Any]] ?? [info]
        guard !formats.isEmpty else { return nil }
        var total: Int64 = 0
        for format in formats {
            guard let number = (format["filesize"] ?? format["filesize_approx"]) as? NSNumber,
                  number.doubleValue.isFinite, number.doubleValue > 0,
                  number.doubleValue < Double(Int64.max) else { return nil }
            let (sum, overflow) = total.addingReportingOverflow(number.int64Value)
            guard !overflow else { return nil }
            total = sum
        }
        return total
    }
}
