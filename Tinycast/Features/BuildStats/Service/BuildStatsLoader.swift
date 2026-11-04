import Foundation

enum BuildStatsLoader {
    struct Totals: Sendable, Equatable {
        var input: Int64 = 0
        var output: Int64 = 0

        mutating func add(_ usage: BuildStatsSnapshot.TokenUsage) throws {
            let inputSum = input.addingReportingOverflow(usage.inputTokens)
            let outputSum = output.addingReportingOverflow(usage.outputTokens)
            guard !inputSum.overflow, !outputSum.overflow else { throw Failure.overflow }
            input = inputSum.partialValue
            output = outputSum.partialValue
        }
    }

    struct ReadModel: Sendable, Equatable {
        let byModel: [String: Totals]
        let byEffort: [String: Totals]
        let timeline: [BuildStatsSnapshot.DatedEntry]
        let latestChangelog: [BuildStatsSnapshot.DatedEntry]
        let metrics: [String: Double]
        let entryCount: Int
        let modificationDate: Date

        init(_ snapshot: BuildStatsSnapshot, modificationDate: Date) throws {
            self.modificationDate = modificationDate
            var models: [String: Totals] = [:]
            var efforts: [String: Totals] = [:]
            for usage in snapshot.tokens {
                try models[usage.model, default: Totals()].add(usage)
                try efforts[usage.effort, default: Totals()].add(usage)
            }
            byModel = models
            byEffort = efforts
            timeline = snapshot.timeline
            latestChangelog = snapshot.changelog.reversed()
            metrics = snapshot.qualityMetrics
            entryCount = snapshot.tokens.count + snapshot.timeline.count + snapshot.changelog.count
        }
    }

    enum Failure: Error, Sendable, Equatable {
        case missing, unreadable, tooLarge, invalid, overflow
    }

    enum State: Sendable, Equatable {
        case unconfigured
        case loaded(ReadModel)
        case failed(Failure)
    }

    @concurrent static func load(path: String) async -> State {
        guard !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .unconfigured
        }
        do {
            let url = URL(filePath: (path as NSString).expandingTildeInPath)
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey])
            guard values.isRegularFile == true, let modificationDate = values.contentModificationDate else {
                return .failed(.unreadable)
            }
            guard (values.fileSize ?? 0) <= BuildStatsSnapshot.maximumBytes else {
                return .failed(.tooLarge)
            }
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            let data = try handle.read(upToCount: BuildStatsSnapshot.maximumBytes + 1) ?? Data()
            guard data.count <= BuildStatsSnapshot.maximumBytes else { return .failed(.tooLarge) }
            try Task.checkCancellation()
            let snapshot: BuildStatsSnapshot
            do { snapshot = try BuildStatsSnapshot.decode(data) }
            catch is CancellationError { return .unconfigured }
            catch { return .failed(.invalid) }
            return try .loaded(ReadModel(snapshot, modificationDate: modificationDate))
        } catch is CancellationError {
            return .unconfigured
        } catch let failure as Failure {
            return .failed(failure)
        } catch {
            let error = error as NSError
            return .failed(error.domain == NSCocoaErrorDomain &&
                [NSFileNoSuchFileError, NSFileReadNoSuchFileError].contains(error.code) ? .missing : .unreadable)
        }
    }
}
