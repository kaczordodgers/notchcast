import Foundation

enum RootContract {
    static let helperPath = "/Library/PrivilegedHelperTools/app.notchcast.root"
    static let version = "3"
    static let usageExit: Int32 = 64
    static let unauthorizedCallerExit: Int32 = 78

    enum Operation: Sendable {
        case read
        case change
        case spotlight

        var timeout: Duration {
            switch self {
            case .read: .seconds(3)
            case .change: .seconds(12)
            case .spotlight: .seconds(60)
            }
        }
    }

    enum Command: String, CaseIterable, Sendable {
        case version
        case ping
        case chargeLimit60 = "charge-limit-60"
        case chargeLimit70 = "charge-limit-70"
        case chargeLimit80 = "charge-limit-80"
        case chargeLimit90 = "charge-limit-90"
        case chargeLimitOff = "charge-limit-off"
        case chargeLimitRead = "charge-limit-read"
        case spotlightOff = "spotlight-off"
        case spotlightOn = "spotlight-on"
        case sudoTouchIDOn = "sudo-touchid-on"
        case sudoTouchIDOff = "sudo-touchid-off"
        case fansAuto = "fans-auto"
        case fansMedium = "fans-medium"
        case fansMax = "fans-max"
        case batteryChargingOn = "battery-charging-on"
        case batteryChargingOff = "battery-charging-off"
        case batteryAdapterOn = "battery-adapter-on"
        case batteryAdapterOff = "battery-adapter-off"
        case batterySleepOn = "battery-sleep-on"
        case batterySleepOff = "battery-sleep-off"
        case standbyOff = "standby-off"
        case standbyOn = "standby-on"
        case autopoweroffOff = "autopoweroff-off"
        case autopoweroffOn = "autopoweroff-on"

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
            case .chargeLimitRead: "off\n"
            case .chargeLimit60, .chargeLimit70, .chargeLimit80, .chargeLimit90, .chargeLimitOff: "ok\n"
            case .spotlightOff, .spotlightOn, .sudoTouchIDOn, .sudoTouchIDOff: "ok\n"
            case .fansAuto, .fansMedium, .fansMax: "ok\n"
            case .standbyOff, .standbyOn, .autopoweroffOff, .autopoweroffOn: "ok\n"
            case .batteryChargingOn, .batteryChargingOff, .batteryAdapterOn, .batteryAdapterOff,
                 .batterySleepOn, .batterySleepOff: "ok\n"
            }
        }

        var operation: Operation {
            switch self {
            case .version, .ping, .chargeLimitRead: .read
            case .chargeLimit60, .chargeLimit70, .chargeLimit80, .chargeLimit90, .chargeLimitOff: .change
            case .spotlightOff, .spotlightOn: .spotlight
            case .sudoTouchIDOn, .sudoTouchIDOff: .change
            case .fansAuto, .fansMedium, .fansMax: .change
            case .standbyOff, .standbyOn, .autopoweroffOff, .autopoweroffOn: .change
            case .batteryChargingOn, .batteryChargingOff, .batteryAdapterOn, .batteryAdapterOff,
                 .batterySleepOn, .batterySleepOff: .change
            }
        }
    }

    enum Reply: Equatable, Sendable {
        case version(String)
        case pong
        case ok
        case chargeLimit(Int?)

        init?(command: Command, output: String) {
            if command == .chargeLimitRead {
                if output == "off\n" { self = .chargeLimit(nil); return }
                guard let value = Int(output.dropLast()), (1...100).contains(value),
                      output == "\(value)\n" else { return nil }
                self = .chargeLimit(value)
                return
            }
            if command == .version {
                guard let version = Int(output.dropLast()), output == "\(version)\n" else { return nil }
                self = .version(String(version))
                return
            }
            guard output == command.output else { return nil }
            switch command {
            case .version: self = .version(RootContract.version)
            case .ping: self = .pong
            case .chargeLimitRead: return nil
            case .chargeLimit60, .chargeLimit70, .chargeLimit80, .chargeLimit90, .chargeLimitOff: self = .ok
            case .spotlightOff, .spotlightOn, .sudoTouchIDOn, .sudoTouchIDOff: self = .ok
            case .fansAuto, .fansMedium, .fansMax: self = .ok
            case .standbyOff, .standbyOn, .autopoweroffOff, .autopoweroffOn: self = .ok
            case .batteryChargingOn, .batteryChargingOff, .batteryAdapterOn, .batteryAdapterOff,
                 .batterySleepOn, .batterySleepOff: self = .ok
            }
        }
    }
}
