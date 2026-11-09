import Foundation

@MainActor
struct MachLinkFanTransport: RemoteFanTransport {
    let channel: MachLinkChannel

    func exchange(_ request: MachLinkMessage) async throws -> MachLinkMessage {
        let verb = try request.value(as: RemoteFanRequest.self)
        let report = try await channel.request(verb, method: request.method, as: RemoteFanReport.self)
        return try MachLinkMessage(id: request.id, method: request.method, value: report)
    }
}

extension MonitorModule {
    func registerRemoteFanRoute(on channel: MachLinkChannel, preferences: NotchcastPreferences = .shared) {
        channel.manager.register("mbp-fans") { [weak self] request in
            guard let self else { throw RemoteFanReport.Failure.unavailable }
            let verb = try request.value(as: RemoteFanRequest.self)
            let report = try await remoteFanReport(verb, preferences: preferences)
            return try MachLinkMessage(id: request.id, method: request.method, value: report)
        }
    }

    func remoteFanReport(_ request: RemoteFanRequest,
                         preferences: NotchcastPreferences = .shared) async throws -> RemoteFanReport {
        func enabled() -> Bool {
            [.machLink, .systemMonitor, .fanControl].allSatisfy { preferences.isOn($0) }
        }
        guard enabled() else { throw RemoteFanReport.Failure.unavailable }
        let current = fans.mode.remoteMode
        let desired = request == .cycle ? current.next : RemoteFanReport.Mode(rawValue: request.rawValue)
        if let desired {
            let requested: FanControl.Mode = switch desired {
            case .auto: .auto
            case .mid: .medium
            case .max: .max
            }
            _ = try await fans.applyAndWait(requested)
        } else { await fans.waitUntilIdle() }
        try Task.checkCancellation()
        guard enabled() else { throw RemoteFanReport.Failure.unavailable }
        let mode = fans.mode.remoteMode
        let readings: [RemoteFanReport.Reading] = try await withCheckedThrowingContinuation { continuation in
            Thread.detachNewThread {
                continuation.resume(with: Result {
                    guard let client = SMCClient(), let count = client.value("FNum"),
                          (1...9).contains(count), count.rounded() == count else {
                        throw RemoteFanReport.Failure.unavailable
                    }
                    return try (0..<Int(count)).map { index -> RemoteFanReport.Reading in
                        guard let actual = client.value("F\(index)Ac"),
                              let target = client.value("F\(index)Tg"),
                              let minimum = client.value("F\(index)Mn"),
                              let maximum = client.value("F\(index)Mx") else {
                            throw RemoteFanReport.Failure.unavailable
                        }
                        return .init(actual: actual, target: target, minimum: minimum, maximum: maximum)
                    }
                })
            }
        }
        try Task.checkCancellation()
        guard enabled() else { throw RemoteFanReport.Failure.unavailable }
        guard fans.mode.remoteMode == mode else {
            throw RemoteFanReport.Failure.busy
        }
        let report = RemoteFanReport(mode: mode, fans: readings)
        try report.validate(for: request)
        return report
    }
}

extension FanControl.Mode {
    var remoteMode: RemoteFanReport.Mode {
        switch self {
        case .auto: .auto
        case .medium: .mid
        case .max: .max
        }
    }
}
