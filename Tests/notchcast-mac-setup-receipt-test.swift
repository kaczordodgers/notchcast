// notchcast-sources: Tinycast/Features/Tweaks/Service/MacSetupReceiptStore.swift
import Foundation

@main
struct MacSetupReceiptTests {
    static func main() throws {
        enum Failure: Error { case transport, disk }
        let original = ["defaults/existing": Data([0, 1, 255]), "verb/service": Data([1])]
        let desired: [(String, Data?)] = [
            ("defaults/existing", Data([2])), ("defaults/absent", Data([3])), ("verb/service", Data([0]))
        ]
        var values = original
        var disk: Data?
        let persist: (MacSetupReceiptStore.Receipt?) throws -> Void = {
            disk = try $0.map { try JSONEncoder().encode($0) }
        }
        var store = try MacSetupReceiptStore(receipt: nil, persist: persist)
        try store.apply(desired, read: { values[$0] }, write: { values[$0] = $1 })
        precondition(store.receipt?.pending == 3)
        do {
            try store.apply(desired, read: { _ in preconditionFailure() }, write: { _, _ in preconditionFailure() })
            preconditionFailure()
        } catch MacSetupReceiptStore.Failure.outstandingReceipt {}
        var relaunched = try MacSetupReceiptStore(
            receipt: try disk.map { try JSONDecoder().decode(MacSetupReceiptStore.Receipt.self, from: $0) },
            persist: persist
        )
        try relaunched.undo { values[$0] = $1 }
        precondition(values == original && disk == nil)
        try relaunched.undo { _, _ in preconditionFailure() }
        print("PASSED 4: capture, duplicate apply refusal, relaunch undo, idempotent undo")

        var failed = false
        do {
            try relaunched.apply(desired, read: { values[$0] }) { target, value in
                values[target] = value
                if target == "defaults/absent", !failed {
                    failed = true
                    throw Failure.transport
                }
            }
            preconditionFailure()
        } catch Failure.transport {}
        precondition(values == original && disk == nil)
        print("PASSED 1: partial failure restores even the failing write")

        try relaunched.apply(desired, read: { values[$0] }, write: { values[$0] = $1 })
        do {
            try relaunched.undo { _, _ in throw Failure.transport }
            preconditionFailure()
        } catch Failure.transport {}
        precondition(disk != nil)
        try relaunched.undo { values[$0] = $1 }
        precondition(values == original)
        print("PASSED 1: failed undo retains recoverable receipt")

        var refusing = try MacSetupReceiptStore(receipt: nil) { _ in throw Failure.disk }
        do {
            try refusing.apply(desired, read: { values[$0] }, write: { _, _ in preconditionFailure() })
            preconditionFailure()
        } catch Failure.disk {}
        precondition(values == original)
        print("PASSED 1: persistence failure prevents writes")

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("receipt.json")
        var durable = try MacSetupReceiptStore(file: file)
        try durable.apply(desired, read: { values[$0] }, write: { values[$0] = $1 })
        var recovered = try MacSetupReceiptStore(file: file)
        try recovered.undo { values[$0] = $1 }
        precondition(values == original)
        let cleared = try MacSetupReceiptStore(file: file)
        precondition(cleared.receipt == nil)
        print("PASSED 1: atomic file journal survives relaunch")
    }
}
