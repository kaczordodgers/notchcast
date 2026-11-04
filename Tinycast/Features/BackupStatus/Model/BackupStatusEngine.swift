import Foundation

enum BackupStatusEngine {
    enum Issue: Sendable, Equatable {
        case unavailable, failed, warning, skipped, stale, lowSpace, restoreFailed, remoteUnavailable, remoteStale
    }

    enum InvalidStatus: Error { case unsupportedVersion, invalidValue }

    static func parse(_ data: Data) throws -> BackupStatus {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let status = try decoder.decode(BackupStatus.self, from: data)
        guard status.version == 1 else { throw InvalidStatus.unsupportedVersion }
        let sizes = [status.sourceBytes, status.addedBytes, status.repoBytes, status.targetFreeBytes]
        guard status.snapshotCount >= 0, sizes.compactMap({ $0 }).allSatisfy({ $0 >= 0 }) else {
            throw InvalidStatus.invalidValue
        }
        return status
    }

    static func issues(_ status: BackupStatus?, now: Date, staleAfter: TimeInterval) -> [Issue] {
        guard let status else { return [.unavailable] }
        var issues: [Issue] = []
        switch status.result {
        case .ok: break
        case .failed: issues.append(.failed)
        case .warning: issues.append(.warning)
        case .skipped: issues.append(.skipped)
        }
        if status.lowSpace { issues.append(.lowSpace) }
        if status.restoreTest?.result == .failed { issues.append(.restoreFailed) }
        if status.lastSuccess.map({ now.timeIntervalSince($0) >= staleAfter }) ?? true {
            issues.append(.stale)
        }
        if now.timeIntervalSince(status.lastAttempt) >= staleAfter, !issues.contains(.stale) {
            issues.append(.stale)
        }
        if let remote = status.mbpTimeMachine {
            if remote.error != nil || remote.latest == nil {
                issues.append(.remoteUnavailable)
            } else if let latest = remote.latest, now.timeIntervalSince(latest) >= staleAfter {
                issues.append(.remoteStale)
            }
        }
        return issues
    }
}
