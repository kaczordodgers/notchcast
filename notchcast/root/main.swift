import Darwin

guard let command = RootContract.Command(arguments: Array(CommandLine.arguments.dropFirst())) else {
    exit(RootContract.usageExit)
}

if command.operation != .read {
    guard geteuid() == 0 else { exit(77) }
    do {
        switch command {
        case .fansAuto, .fansMedium, .fansMax:
            try FanSMC.Controller(smc: FanSMC.Connection()).run(command)
        case .spotlightOff, .spotlightOn:
            try Spotlight.run(command)
        case .standbyOff, .standbyOn, .autopoweroffOff, .autopoweroffOn:
            try Power.run(command)
        case .sudoTouchIDOn, .sudoTouchIDOff:
            try SudoTouchID.run(enabled: command == .sudoTouchIDOn)
        default:
            try BatterySMC.run(command)
        }
    } catch {
        exit(70)
    }
}

command.output.withCString { output in
    _ = write(1, output, strlen(output))
}
