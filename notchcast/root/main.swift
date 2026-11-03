import Darwin
import Foundation

guard let command = RootContract.Command(arguments: Array(CommandLine.arguments.dropFirst())) else {
    exit(RootContract.usageExit)
}

FileHandle.standardOutput.write(Data(command.output.utf8))
