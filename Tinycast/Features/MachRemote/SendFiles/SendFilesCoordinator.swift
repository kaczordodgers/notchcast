import Foundation
import Observation

@MainActor @Observable
final class SendFilesCoordinator {
    enum Outcome: Equatable {
        case recent
        case needsAttention
        case cancelled
    }

    struct Report: Equatable {
        var sent = 0
        var failed = 0
        var outcome: Outcome = .recent
    }

    private(set) var progress = 0
    private(set) var report: Report?
    var isRunning: Bool { task != nil }
    @ObservationIgnored private let shell: any RemoteShellRunning
    @ObservationIgnored private let post: @MainActor (String) -> Void
    @ObservationIgnored private var task: Task<Void, Never>?

    init(shell: any RemoteShellRunning, post: @escaping @MainActor (String) -> Void) {
        self.shell = shell
        self.post = post
    }

    func sendFinderSelection(_ urls: [URL]) {
        guard task == nil else { return }
        progress = 0
        report = nil
        task = Task { [weak self] in
            guard let self else { return }
            await transfer(urls)
            task = nil
        }
    }

    func cancel() { task?.cancel() }
    func stop() { cancel() }

    func waitForCompletion() async { await task?.value }

    private func ssh(_ command: String) async throws -> SendFilesProcessResult {
        try await shell.run("/usr/bin/ssh", arguments: ["-o", "BatchMode=yes", "--", shell.sshAlias, command],
                            output: { _ in })
    }

    private func transfer(_ urls: [URL]) async {
        guard MachSSH.isValid(shell.sshAlias) else {
            post(MachSSH.ConfigurationError.address.localizedDescription)
            report = Report(sent: 0, failed: urls.count, outcome: .needsAttention)
            return
        }
        var result = Report()
        let staging = "Downloads/.notchcast-upload-" + UUID().uuidString
        guard !urls.isEmpty, urls.allSatisfy({ $0.isFileURL && $0.path.hasPrefix("/") }),
              MachSSH.isValid(shell.sshAlias) else {
            report = Report(sent: 0, failed: urls.count, outcome: .needsAttention)
            post(String(localized: "Select files in Finder and configure the remote Mac.", table: "SendFiles"))
            return
        }
        do {
            try Task.checkCancellation()
            let prepared = try await ssh(SendFilesPlan.prepare(staging: staging))
            guard prepared.status == 0 else { throw TransferFailure(status: prepared.status) }
            for (index, url) in urls.enumerated() {
                try Task.checkCancellation()
                let itemStaging = staging + "/" + String(index)
                let preparedItem = try await ssh("mkdir -- " + SendFilesPlan.quote(itemStaging))
                guard preparedItem.status == 0 else { throw TransferFailure(status: preparedItem.status) }
                var pending = ""
                let copied = try await shell.run("/usr/bin/rsync", arguments: SendFilesPlan.arguments(
                    source: url, alias: shell.sshAlias, staging: itemStaging
                )) { [weak self] chunk in
                    pending += chunk
                    while let boundary = pending.firstIndex(where: { $0 == "\r" || $0 == "\n" }) {
                        let record = String(pending[..<boundary])
                        pending.removeSubrange(...boundary)
                        if let percent = SendFilesPlan.percent(in: record) {
                            self?.progress = (index * 100 + percent) / urls.count
                        }
                    }
                }
                try Task.checkCancellation()
                if copied.status == 0 {
                    let claimed = try await ssh(SendFilesPlan.commit(staging: itemStaging, name: url.lastPathComponent))
                    try Task.checkCancellation()
                    if claimed.status == 0 { result.sent += 1 } else { result.failed += 1 }
                } else {
                    result.failed += 1
                }
                progress = (index + 1) * 100 / urls.count
            }
        } catch is CancellationError {
            result.outcome = .cancelled
        } catch {
            if Task.isCancelled { result.outcome = .cancelled } else { result.failed = urls.count - result.sent }
        }
        let cleanup = await Task { try? await self.ssh("rm -rf -- " + SendFilesPlan.quote(staging)) }.value
        if cleanup?.status != 0 { result.failed = max(1, result.failed) }
        if result.outcome != .cancelled { result.outcome = result.failed == 0 ? .recent : .needsAttention }
        report = result
        switch result.outcome {
        case .recent: post(String(localized: "Files sent to the remote Mac.", table: "SendFiles"))
        case .needsAttention:
            post(String(localized:
                "Unable to send all files. Nothing from the failed folder was kept on the remote Mac.", table: "SendFiles"))
        case .cancelled:
            post(String(localized: "Send cancelled. Completed files were kept on the remote Mac.", table: "SendFiles"))
        }
    }

    private struct TransferFailure: Error { let status: Int32 }
}
