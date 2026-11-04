import Foundation

nonisolated struct KillProcessEntry: Sendable, Equatable {
    let pid: Int32
    let parentPID: Int32
    let uid: UInt32
    let startSeconds: UInt64
    let startMicroseconds: UInt64
    let path: String

    func canStop(uid: UInt32, ownPID: Int32) -> Bool {
        let name = URL(filePath: path).lastPathComponent
        return pid > 1 && pid != ownPID && self.uid != 0 && self.uid == uid
            && startSeconds > 0 && startMicroseconds < 1_000_000
            && !["launchd", "kernel_task", "WindowServer", "loginwindow"].contains(name)
            && !path.hasPrefix("/System/") && !path.hasPrefix("/usr/libexec/")
    }

    func sameIdentity(as other: Self) -> Bool {
        pid == other.pid && uid == other.uid && startSeconds == other.startSeconds
            && startMicroseconds == other.startMicroseconds && path == other.path
    }

    func tree(in table: [Self]) -> [Self] {
        var result = [self]
        var seen: Set<Int32> = [pid]
        var index = 0
        while index < result.count {
            let parent = result[index]
            for child in table where child.parentPID == parent.pid && !seen.contains(child.pid) {
                guard child.startSeconds > parent.startSeconds
                    || (child.startSeconds == parent.startSeconds
                        && child.startMicroseconds >= parent.startMicroseconds) else { continue }
                seen.insert(child.pid)
                result.append(child)
            }
            index += 1
        }
        return result.reversed()
    }
}
