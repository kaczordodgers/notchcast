import Darwin
import Foundation

guard let command = RootContract.Command(arguments: Array(CommandLine.arguments.dropFirst())) else {
    exit(RootContract.usageExit)
}

guard RootCaller.permits(command, identity: RootCaller.authorized) else {
    exit(RootContract.unauthorizedCallerExit)
}

if command.operation != .read {
    guard geteuid() == 0 else { exit(77) }
    if command == .cleanSystemList || command == .cleanSystemTrash {
        do {
            try FileHandle.standardOutput.write(contentsOf: CleanSystem.run(command))
            exit(0)
        } catch { exit(70) }
    }
    do {
        switch command {
        case .chargeLimit60, .chargeLimit70, .chargeLimit80, .chargeLimit90, .chargeLimitOff:
            try NativeChargeLimit.run(command)
        case .fansAuto, .fansMedium, .fansMax:
            try FanSMC.Controller(smc: FanSMC.Connection()).run(command)
        case .spotlightOff, .spotlightOn:
            try Spotlight.run(command)
        case .sudoTouchIDOn, .sudoTouchIDOff:
            try SudoTouchID.run(enabled: command == .sudoTouchIDOn)
        default:
            try BatterySMC.run(command)
        }
    } catch BatterySMC.Failure.unsupported {
        exit(RootContract.unsupportedExit)
    } catch NativeChargeLimit.Failure.unconfirmed {
        "Charge limit state is unconfirmed after timeout\n".withCString {
            _ = write(2, $0, strlen($0))
        }
        exit(70)
    } catch {
        exit(70)
    }
}

let reply: String
do {
    reply = command == .chargeLimitRead ? try NativeChargeLimit.read() : command.output
} catch {
    exit(70)
}
reply.withCString { output in
    _ = write(1, output, strlen(output))
}
