import Darwin

guard let command = RootContract.Command(arguments: Array(CommandLine.arguments.dropFirst())) else {
    exit(RootContract.usageExit)
}

if command.operation == .change {
    guard geteuid() == 0 else { exit(77) }
    do {
        try FanSMC.Controller(smc: FanSMC.Connection()).run(command)
    } catch {
        exit(70)
    }
}

command.output.withCString { output in
    _ = write(1, output, strlen(output))
}
