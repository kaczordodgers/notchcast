// notchcast-sources: Tinycast/Features/Notchcast/Island/IslandController+CommandAvailability.swift
// notchcast-kit: host
import Foundation

enum DialogTone { case neutral, success, danger }

@MainActor final class IslandController {
    var commandsAvailable = false
}

@main @MainActor struct IslandCommandAvailabilityTests {
    static func main() {
        let island = IslandController()
        var refreshedAvailability: [Bool] = []
        NotchcastHost.current.refreshNotchcastCommands = {
            refreshedAvailability.append(island.commandsAvailable)
        }
        island.setCommandAvailable(false)
        precondition(refreshedAvailability.isEmpty, "Initial unavailability needs no command refresh")
        island.setCommandAvailable(true)
        precondition(refreshedAvailability == [true], "Starting publishes availability before refreshing")
        for _ in 0..<100 { island.setCommandAvailable(true) }
        precondition(refreshedAvailability == [true], "Progress ticks must not rebuild unchanged commands")
        island.setCommandAvailable(false)
        precondition(refreshedAvailability == [true, false], "Stopping refreshes unavailable commands")
        island.setCommandAvailable(false)
        precondition(refreshedAvailability == [true, false], "Repeated stopping needs no command refresh")
        island.setCommandAvailable(true)
        precondition(refreshedAvailability == [true, false, true], "Restarting refreshes available commands")
        print("PASS: island command refreshes occur only when availability changes")
    }
}
