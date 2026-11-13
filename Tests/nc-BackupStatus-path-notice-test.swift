// notchcast-sources: Tinycast/Features/BackupStatus/Model/*.swift
// notchcast-sources: Tinycast/Features/BackupStatus/Service/BackupStatusModule.swift
import Foundation

@MainActor protocol NotchcastModule { func start(); func stop() }

@main enum PathNoticeTest {
    @MainActor static func main() {
        var notice: String?
        var posts: [String] = []
        var restart: (@MainActor () -> Void)?
        let module = BackupStatusModule(read: { Data() }, watch: { _ in {} },
            schedule: { _, action in restart = action; return {} },
            configurationNotice: { notice }, post: { posts.append($0) })
        module.start()
        notice = "unset"
        module.pathChanged()
        restart?()
        precondition(posts == ["unset"], "clearing a configured path must post its notice")
        notice = "invalid"
        module.pathChanged()
        restart?()
        precondition(posts == ["unset", "invalid"], "editing an invalid path must post its notice")
        module.stop()
        print("PASS: cleared and edited paths post configuration notices")
    }
}
