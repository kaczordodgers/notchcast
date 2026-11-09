// notchcast-sources: -parse-as-library Tinycast/Features/Notchcast/Root/RootContract.swift
// notchcast-sources: Tinycast/Features/Battery/Model/*.swift Tinycast/Features/Battery/Service/*.swift
import Foundation

@main
struct RootVerbsTest {
    static func main() {
        let wire = [
            "version", "ping", "clean-system-list", "clean-system-trash",
            "charge-limit-60", "charge-limit-70", "charge-limit-80", "charge-limit-90",
            "charge-limit-off", "charge-limit-read", "spotlight-off", "spotlight-on",
            "sudo-touchid-on", "sudo-touchid-off", "fans-auto", "fans-medium", "fans-max",
            "battery-charging-on", "battery-charging-off", "battery-adapter-on", "battery-adapter-off",
            "battery-sleep-on", "battery-sleep-off", "standby-off", "standby-on",
            "autopoweroff-off", "autopoweroff-on",
        ]
        precondition(RootContract.Command.allCases.map(\.rawValue) == wire, "verb table unchanged")
        for command in RootContract.Command.allCases {
            precondition(RootContract.Command(arguments: command.arguments) == command, "\(command) round trip")
            precondition(RootContract.Reply(command: command, output: command.output) != nil, "\(command) reply")
        }
        precondition(RootContract.Command.version.output == "4\n")
        precondition(RootContract.Reply(command: .version, output: "4\n") == .version("4"))
        precondition(RootContract.Reply(command: .ping, output: "pong\n") == .pong)
        precondition(RootContract.Reply(command: .chargeLimitRead, output: "off\n") == .chargeLimit(nil))
        precondition(RootContract.Reply(command: .chargeLimitRead, output: "80\n") == .chargeLimit(80))
        precondition(Data(RootContract.Command.cleanSystemTrash.output.utf8) == Data("ok\n".utf8))
        for (percent, verb) in [(nil, "charge-limit-off"), (60, "charge-limit-60"), (70, "charge-limit-70"),
                                (80, "charge-limit-80"), (90, "charge-limit-90")] as [(Int?, String)] {
            precondition(RootContract.Command(chargeLimit: percent)?.rawValue == verb, "limit \(String(describing: percent))")
        }
        for percent in [0, 50, 85, 100, -1] {
            precondition(RootContract.Command(chargeLimit: percent) == nil, "no verb for \(percent)")
        }

        var sent: [String] = []
        let plan = ChargePlanService()
        try? plan.apply(.init(charging: true, adapter: true), watchdogReady: false) { sent.append($0.rawValue) }
        precondition(sent == ["battery-adapter-on", "battery-charging-on"], "charging plan verbs")
        sent = []
        try? plan.apply(.init(charging: false, adapter: false), watchdogReady: true) { sent.append($0.rawValue) }
        precondition(sent == ["battery-charging-off", "battery-adapter-off"], "drain plan verbs")
        sent = []
        try? plan.release { sent.append($0.rawValue) }
        precondition(sent == ["battery-adapter-on", "battery-charging-on"], "release verbs")
        precondition(LidClosedPolicy.plan(enabled: true, helperReady: true, keepAwakeHolding: true).rawValue
                     == "battery-sleep-off")
        precondition(LidClosedPolicy.plan(enabled: true, helperReady: true, keepAwakeHolding: false).rawValue
                     == "battery-sleep-on")

        var journal = BatteryOwnershipJournal()
        precondition(journal.limitUndo == "charge-limit-off", "no prior limit restores off")
        journal.captureLimit(70)
        precondition(journal.limitUndo == "charge-limit-70", "prior limit restores itself")
        var unrestorable = BatteryOwnershipJournal()
        unrestorable.captureLimit(85)
        precondition(unrestorable.limitUndo == nil, "a limit with no verb cannot be restored")
        journal.adopt("charge-limit", applied: "charge-limit-80", undo: "charge-limit-70")
        precondition(!journal.userChangedLimit(80), "own limit is not a user change")
        precondition(journal.userChangedLimit(nil) && journal.userChangedLimit(70), "other verbs are user changes")
        precondition(journal.userChangedLimit(85), "a limit with no verb is a user change")
        print("PASS: \(wire.count) root verbs round-trip; Battery sends the same verb strings")
    }
}
