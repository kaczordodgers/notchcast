import Darwin

guard let command = RootContract.Command(arguments: Array(CommandLine.arguments.dropFirst())) else {
    exit(RootContract.usageExit)
}

command.output.withCString { output in
    _ = write(1, output, strlen(output))
}
