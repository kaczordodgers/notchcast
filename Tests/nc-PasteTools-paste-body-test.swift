// notchcast-sources: Tinycast/Features/PasteTools/Model/*.swift
// notchcast-sources: Tinycast/Features/PasteTools/Service/PasteImageModule.swift
// notchcast-kit: platform input
// notchcast-sources: Tests/Support/EventTapHubFake.swift
import AppKit
import os

@MainActor protocol NotchcastModule { func start(); func stop() }
@MainActor extension Paster {
    static var replays = 0
    static func postCommandV() { replays += 1 }
}
enum FinderImageService { static func save(_ png: Data) -> Bool { fatalError("No Finder writes") } }

@main @MainActor struct PasteBodyTest {
    static func main() async throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let saved = OSAllocatedUnfairLock(initialState: [Data]())
        var accepts = true
        var failures = 0
        let module = PasteImageModule(hub: EventTapHub(), pasteboard: board.name,
            finderIsFrontmost: { true }, acceptsPaste: { accepts }, save: { data in
                saved.withLock { $0.append(data) }
                return false
            })
        module.onFailure = { failures += 1 }
        module.paste()
        precondition(Paster.replays == 0)
        module.start()
        board.setString("text", forType: .string)
        module.paste()
        precondition(Paster.replays == 1)
        board.clearContents()
        let png = Data([0x89, 0x50, 0x4e, 0x47])
        board.setData(png, forType: .png)
        accepts = false
        module.paste()
        precondition(Paster.replays == 2)
        accepts = true
        module.paste()
        for _ in 0..<200 where failures == 0 { try await Task.sleep(for: .milliseconds(10)) }
        precondition(saved.withLock { $0 } == [png], "Paste reads the injected board")
        precondition(module.saveFailed && failures == 1)
        board.clearContents()
        board.setData(Data([0]), forType: .tiff)
        module.paste()
        for _ in 0..<200 where failures == 1 { try await Task.sleep(for: .milliseconds(10)) }
        precondition(failures == 2 && saved.withLock { $0.count } == 1)
        module.stop()
        print("PASS: private-board PNG bytes, text/focus fallback, failed save and invalid TIFF")
    }
}
