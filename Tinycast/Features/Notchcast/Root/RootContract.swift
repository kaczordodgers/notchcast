enum RootContract {
    static let helperPath = "/Library/PrivilegedHelperTools/app.notchcast.root"
    static let version = "1"
    static let usageExit: Int32 = 64

    enum Operation: Sendable {
        case read
        case change

        var timeout: Duration {
            switch self {
            case .read: .seconds(3)
            case .change: .seconds(12)
            }
        }
    }

    enum Command: String, CaseIterable, Sendable {
        case version
        case ping
        case fansAuto = "fans-auto"
        case fansMedium = "fans-medium"
        case fansMax = "fans-max"

        init?(arguments: [String]) {
            guard arguments.count == 1, let command = Self(rawValue: arguments[0]) else {
                return nil
            }
            self = command
        }

        var arguments: [String] { [rawValue] }

        var output: String {
            switch self {
            case .version: RootContract.version + "\n"
            case .ping: "pong\n"
            case .fansAuto, .fansMedium, .fansMax: "ok\n"
            }
        }

        var operation: Operation {
            switch self {
            case .version, .ping: .read
            case .fansAuto, .fansMedium, .fansMax: .change
            }
        }
    }

    enum Reply: Equatable, Sendable {
        case version(String)
        case pong
        case ok

        init?(command: Command, output: String) {
            guard output == command.output else { return nil }
            switch command {
            case .version: self = .version(RootContract.version)
            case .ping: self = .pong
            case .fansAuto, .fansMedium, .fansMax: self = .ok
            }
        }
    }
}
