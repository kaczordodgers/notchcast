import Foundation

struct DownloadsActivity: Equatable, Sendable {
    let runningCount: Int
    let currentTitle: String?
    let fraction: Double?
    let stage: String?

    init(jobs: [DownloadJob]) {
        let running = jobs.filter { $0.state == .running }
        runningCount = running.count
        let current = running.min { $0.created < $1.created }
        currentTitle = current?.title
        fraction = current?.progress?.fraction
        stage = current?.progress?.stage
    }
}
