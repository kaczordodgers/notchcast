// notchcast-sources: Tinycast/Features/Tweaks/Model/AppleAppsPolicy.swift
// notchcast-sources: Tinycast/Features/Tweaks/Model/TypingPreferencePlan.swift
// notchcast-sources: Tinycast/Features/Tweaks/Service/AppleAppsUndoStore.swift
// notchcast-sources: Tinycast/Features/Tweaks/Service/AppleAppsService.swift
import Foundation

@main
struct AppleAppsUndoTests {
    @MainActor
    static func main() throws {
        var checks = 0
        func expect(_ condition: Bool) {
            precondition(condition)
            checks += 1
        }
        func tile(_ id: String, _ guid: Int) -> [String: Any] {
            ["GUID": guid, "tile-data": ["bundle-identifier": id, "label": id]]
        }
        func encode(_ tiles: [[String: Any]]) throws -> Data {
            try PropertyListSerialization.data(fromPropertyList: tiles, format: .binary, options: 0)
        }
        let music = tile("com.apple.Music", 1)
        let keep = tile("example.keep", 2)
        let books = tile("com.apple.iBooksX", 3)
        let added = tile("example.added", 4)
        let original = try encode([music, keep, books])
        var dock = original
        var service = Data([0, 1, 2])
        let priorService = service
        var journal = Data()
        var receipt = AppleAppsUndoStore.Receipt()
        var refuseSave = false
        enum Failure: Error { case refused }
        func store() -> AppleAppsUndoStore {
            AppleAppsUndoStore(receipt: receipt, readDock: { dock }, writeDock: {
                expect(receipt.dock != nil)
                dock = $0
            }, readMusic: { service }, disableMusic: {
                expect(receipt.music != nil)
                service = Data([9])
            }, restoreMusic: { service = $0 }, save: {
                if refuseSave { throw Failure.refused }
                journal = try JSONEncoder().encode($0)
                receipt = $0
            })
        }
        let first = store()
        try first.setDock(true)
        try first.setMusic(true)
        try first.stop()
        expect(dock == original && service == priorService)
        expect(receipt == .init())
        try first.setDock(true)
        try first.setMusic(true)
        dock = try encode([added, keep])
        receipt = try JSONDecoder().decode(AppleAppsUndoStore.Receipt.self, from: journal)
        let relaunched = store()
        try relaunched.stop()
        guard let restored = try PropertyListSerialization.propertyList(from: dock, format: nil)
            as? [[String: Any]] else { preconditionFailure() }
        expect(restored.compactMap { $0["GUID"] as? Int } == [4, 1, 2, 3])
        expect(service == priorService)
        expect(receipt == .init())
        try relaunched.setDock(true)
        dock = try encode([keep, music, added])
        try relaunched.setDock(false)
        guard let edited = try PropertyListSerialization.propertyList(from: dock, format: nil)
            as? [[String: Any]] else { preconditionFailure() }
        expect(edited.compactMap { $0["GUID"] as? Int } == [2, 3, 1, 4])
        refuseSave = true
        let before = dock
        do { try relaunched.setDock(true); preconditionFailure() } catch Failure.refused {}
        expect(dock == before && relaunched.receipt.dock == nil)
        print("\(checks) passed, 0 failed")
    }
}
