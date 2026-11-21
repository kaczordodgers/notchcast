// notchcast-sources: Tinycast/Features/Notchcast/Core/Model/*.swift Tinycast/Features/Notchcast/Core/Service/*.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandPresentation.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandPresenting.swift
// notchcast-sources: Tinycast/Platform/NotificationToken.swift
// notchcast-sources: Tinycast/Features/Notchcast/Screenshots/ScreenshotsAddon.swift
// notchcast-sources: Tinycast/Features/Notchcast/Screenshots/Model/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Screenshots/Service/ScreenshotSystem.swift
// notchcast-sources: Tinycast/Features/Notchcast/Screenshots/Service/ScreenshotsModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/Screenshots/Service/ScreenshotOutput.swift
// notchcast-sources: Tinycast/Features/Notchcast/Screenshots/Service/ScrollingCaptureRun.swift
// notchcast-sources: Tests/NotchcastDictationFixture.swift Tests/nc-Screenshots-fixture.swift

import CoreGraphics
import Foundation
import ImageIO
import SwiftUI
import Synchronization

@main
enum ScreenshotsScrollingTests {
    @MainActor
    static func main() async {
        precondition((try? FileManager.default.createDirectory(at: downloadsFolder, withIntermediateDirectories: true)) != nil)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let rig = Rig()
        let presenter = rig.presenter
        let area16 = ScreenshotRequest.rect(CGRect(x: 10, y: 10, width: 16, height: 30))
        let finishTitle = "Finish Scrolling Capture"
        func start(_ frames: [CGImage?], pick request: ScreenshotRequest? = area16) async {
            fake.scroll(frames)
            await settle("a scrolling surface", until: {
                if fake.answer == nil { rig.fire(scroll) }
                return fake.answer != nil
            })
            fake.pick(request)
        }
        func copied(after count: Int) async -> Data? {
            // A 20,000 px run stitches about 200 frames while this yields, so it gets more tries.
            await settle("the copy", tries: 5_000_000, until: { fake.clipboard.count == count + 1 })
            return fake.clipboard.last
        }
        func yieldALot() async { for _ in 0..<2_000 { await Task.yield() } }
        let joined = [page(offset: 0), page(offset: 42)]

        fake.granted = false
        let surfaces = fake.surfaces.count
        rig.fire(scroll)
        precondition(presenter.posts.last?.text == "Screen Recording access is required."
                     && fake.surfaces.count == surfaces && presenter.status == nil,
                     "without access it posts the failure and opens no surface")
        fake.granted = true

        await start(joined, pick: nil)
        await start(joined, pick: nil)
        precondition(fake.surfaces.count == surfaces + 2 && presenter.status == nil && fake.guides == 0,
                     "a cancelled selection goes back to idle, so the command starts again")

        rig.defaults.set(true, forKey: ScreenshotsModule.editAfterCaptureKey)
        var clips = fake.clipboard.count
        await start(joined)
        await settle("the stitched height", until: { presenter.status?.text == "162" })
        precondition(fake.regions.last == ScrollingCaptureRegion(area16, displays: fake.displays, windows: []),
                     "the run opens the picked area on its display")
        precondition(fake.guides == 1 && presenter.status?.symbol == "stop.circle"
                     && presenter.status?.label == finishTitle && presenter.statusTap != nil
                     && presenter.rows.map(\.title) == [finishTitle, "Cancel Scrolling Capture"],
                     "a run shows the guide, the stop with its height, and Finish and Cancel")
        let freezes = fake.freezes.count
        for other in [area, display, text, editLast] { rig.fire(other) }
        await yieldALot()
        precondition(fake.freezes.count == freezes && fake.edited.isEmpty && fake.surfaces.count == surfaces + 3,
                     "every other Screenshots command is ignored during a run")
        rig.fire(scroll)
        precondition(presenter.rows.isEmpty && presenter.statusTap == nil && presenter.status?.text == "162",
                     "once Finish is asked the menu goes and the stop keeps its height but takes no press")
        rig.fire(scroll)
        presenter.statusTap?()
        precondition(fake.surfaces.count == surfaces + 3, "the command while finishing is ignored")
        fake.releaseFrames()
        let first = await copied(after: clips)
        await settle("the notice", until: { presenter.posts.last?.id == "screenshot.copied" })
        precondition(pngHeight(first) == 162 && pngDPI(first).map { abs($0 - 144) < 1 } == true,
                     "the command again copies one tall Retina image")
        precondition(presenter.posts.last == IslandNotice(id: "screenshot.copied", symbol: "camera", text: "Copied"),
                     "it says Copied, as the editor does")
        precondition(presenter.status == nil && presenter.rows.isEmpty && fake.hiddenGuides == fake.guides,
                     "the result clears the stop, the menu and the guide")
        await yieldALot()
        precondition(fake.clipboard.count == clips + 1 && fake.edited.isEmpty,
                     "it ends once, and Edit after capture opens no editor for it")
        rig.defaults.removeObject(forKey: ScreenshotsModule.editAfterCaptureKey)

        for finish in ["the stop", "the Finish row"] {
            clips = fake.clipboard.count
            await start(joined)
            await settle("the stitched height", until: { presenter.status?.text == "162" })
            if finish == "the stop" { presenter.statusTap?() } else { presenter.select?("finish") }
            precondition(presenter.rows.isEmpty && presenter.statusTap == nil, "\(finish) asks Finish once")
            fake.releaseFrames()
            let data = await copied(after: clips)
            precondition(pngHeight(data) == 162, "\(finish) finishes and copies")
            await settle("the run's end", until: { presenter.status == nil })
        }

        for stop in ["Cancel", "switching off"] {
            clips = fake.clipboard.count
            let posts = presenter.posts.count
            await start(joined)
            await settle("the stitched height", until: { presenter.status?.text == "162" })
            if stop == "Cancel" {
                presenter.select?("cancel")
            } else {
                rig.controller.preferences.set("screenshot", on: false)
            }
            await settle("\(stop) clears the run", until: { presenter.status == nil })
            precondition(presenter.rows.isEmpty && fake.hiddenGuides == fake.guides, "\(stop) clears guide and menu")
            fake.releaseFrames()
            await yieldALot()
            precondition(fake.clipboard.count == clips && presenter.posts.count == posts,
                         "\(stop) copies and posts nothing, even when the stopped run's frame comes late")
            if stop == "switching off" {
                precondition(!rig.controller.run(entryID: scroll), "the command goes with the switch")
                rig.controller.preferences.set("screenshot", on: true)
                await settle("the switch on", until: { rig.controller.enabledCommands.contains { $0.id == scroll } })
            }
        }

        for (destination, folder) in [("file", "Downloads"), ("both", "Downloads")] {
            rig.defaults.set(destination, forKey: "notchcast.screenshot.destination")
            let saved = files(in: downloadsFolder).count
            clips = fake.clipboard.count
            await start(joined)
            await settle("the stitched height", until: { presenter.status?.text == "162" })
            rig.fire(scroll)
            fake.releaseFrames()
            await settle("the saved notice", until: {
                presenter.posts.last?.id == "screenshot.saved" && presenter.status == nil
            })
            precondition(presenter.posts.last?.text == "Saved to \(folder)"
                         && files(in: downloadsFolder).count == saved + 1
                         && fake.clipboard.count == clips + (destination == "both" ? 1 : 0),
                         "\(destination): saved to the screenshot folder, and says where")
            presenter.posts = []
        }
        rig.defaults.set("clipboard", forKey: "notchcast.screenshot.destination")

        // A still page with slow frames runs into the two-minute guard in about 120 of them.
        let endings: [(frames: [CGImage?], holds: Bool, seconds: Double, text: String, height: Int)] = [
            ([page(offset: 0), page(offset: 0, seed: 91)], true, 0.01,
             "Kept the part before the page changed.", 120),
            ([page(offset: 0)], false, 1, "Scrolling capture stopped at its limit.", 120),
            ((0..<250).map { page(offset: $0 * 100) }, false, 0.01,
             "Scrolling capture reached the 20,000 pixel limit.", 20_000),
        ]
        for ending in endings {
            clips = fake.clipboard.count
            fake.frameSeconds = ending.seconds
            await start(ending.frames)
            if ending.holds {
                await settle("the held run", until: { fake.frameGate != nil })
                rig.fire(scroll)
            }
            fake.releaseFrames()
            let data = await copied(after: clips)
            await settle("the notice", until: { presenter.posts.last?.id == "screenshot.copied" })
            precondition(presenter.posts.last == IslandNotice(
                            id: "screenshot.copied", symbol: "camera", text: ending.text, seconds: 4),
                         "the picture is kept and the notice says why: \(ending.text)")
            precondition(pngHeight(data) == ending.height, "\(ending.text): \(pngHeight(data) ?? -1) rows")
            await settle("the run's end", until: { presenter.status == nil })
        }
        fake.frameSeconds = 0.01

        fake.clipboardWorks = false
        await start(joined)
        await settle("the stitched height", until: { presenter.status?.text == "162" })
        rig.fire(scroll)
        fake.releaseFrames()
        await settle("the failure", until: { presenter.posts.last?.id == "screenshot.failed" })
        precondition(presenter.posts.last?.text == "Could not copy to clipboard." && presenter.status == nil,
                     "a failed clipboard write reports and clears the run")
        fake.clipboardWorks = true

        let guides = fake.guides
        await start(joined, pick: .rect(CGRect(x: 90, y: 10, width: 20, height: 10)))
        await settle("the refusal", until: { presenter.posts.last?.text == "Capture area is unavailable." })
        precondition(fake.guides == guides, "an area across two displays is refused before any run")
        presenter.posts = []
        fake.regionFails = true
        await start(joined)
        await settle("the failure", until: { presenter.posts.last?.text == "Capture area is unavailable." })
        await settle("the cleared run", until: { presenter.status == nil })
        precondition(fake.hiddenGuides == fake.guides && presenter.rows.isEmpty, "an area that will not open clears up")
        fake.regionFails = false

        rig.fire(editLast)
        await settle("the editor", until: { fake.edited.count == 1 })
        precondition(fake.edited[0].height == 162, "Edit Last Screenshot opens the last scrolling result")
        let busy = fake.surfaces.count
        rig.fire(scroll)
        await yieldALot()
        precondition(fake.surfaces.count == busy, "Scrolling Capture is ignored while the editor is open")
        rig.finish()
        print("nc-Screenshots-scrolling-test: ok")
    }
}
