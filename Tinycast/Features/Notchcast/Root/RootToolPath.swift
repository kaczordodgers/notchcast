import Darwin

enum RootToolPath {
    enum Problem: Equatable, Sendable {
        case missing(String)
        case wrongKind(String)
        case wrongOwner(String)
        case writable(String)
        case notExecutable(String)
    }

    static func verify(_ path: String = RootContract.helperPath) -> Problem? {
        let names = path.split(separator: "/", omittingEmptySubsequences: false)
        guard names.first == "", names.count > 1,
              names.dropFirst().allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." })
        else { return .wrongKind(path) }
        if let problem = check("/", directory: true) { return problem }
        var current = ""
        for (index, name) in names.dropFirst().enumerated() {
            current += "/" + name
            if let problem = check(current, directory: index < names.count - 2) {
                return problem
            }
        }
        return nil
    }

    static func check(_ path: String, directory: Bool) -> Problem? {
        var info = stat()
        guard lstat(path, &info) == 0 else { return .missing(path) }
        return problem(path: path, info: info, directory: directory)
    }

    static func problem(path: String, info: stat, directory: Bool) -> Problem? {
        guard info.st_mode & S_IFMT == (directory ? S_IFDIR : S_IFREG) else {
            return .wrongKind(path)
        }
        guard info.st_uid == 0 else { return .wrongOwner(path) }
        guard info.st_mode & (S_IWGRP | S_IWOTH) == 0 else { return .writable(path) }
        guard info.st_mode & S_IXUSR != 0 else { return .notExecutable(path) }
        return nil
    }
}
