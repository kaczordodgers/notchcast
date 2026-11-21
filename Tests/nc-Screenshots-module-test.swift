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
enum ScreenshotsModuleTests {
    @MainActor
    static func main() async {
        precondition((try? FileManager.default.createDirectory(at: downloadsFolder, withIntermediateDirectories: true)) != nil)
        precondition((try? FileManager.default.createDirectory(at: chosenFolder, withIntermediateDirectories: true)) != nil)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let rig = Rig()
        let presenter = rig.presenter

        precondition(ScreenshotsAddon.switches.map(\.id) == ["screenshot"], "v1 switch id")
        precondition(ScreenshotsAddon.commands.map(\.id) == [area, display, editLast, text, scroll],
                     "frozen command ids")
        precondition(ScreenshotsAddon.commands.map { "hotkey." + $0.id }
                     == ["hotkey.command:nc-screenshot-area", "hotkey.command:nc-screenshot-display",
                         "hotkey.command:nc-edit-last-screenshot", "hotkey.command:nc-capture-text",
                         "hotkey.command:nc-scrolling-capture"],
                     "each stored binding names its command")
        precondition(rig.controller.enabledCommands.map(\.id) == [area, display, editLast, text, scroll],
                     "on by default")
        await settle("the first warm-up", until: { fake.warmCancelled.count == 1 })
        precondition(fake.warmOffMain == [true] && fake.warmCancelled == [false],
                     "the module's start warms the recogniser once, off the main actor")

        fake.holdFreeze = true
        precondition(rig.controller.run(entryID: area), "the area binding resolves")
        await drain()
        precondition(fake.freezes.count == 1 && fake.freezes[0].point == nil, "area freezes every display")
        let exclusion = fake.freezes[0].exclusion
        precondition(exclusion.pid == ProcessInfo.processInfo.processIdentifier, "the exclusion knows our own windows")
        precondition(rig.controller.run(entryID: area) && rig.controller.run(entryID: display),
                     "a second trigger still resolves")
        await drain()
        precondition(fake.freezes.count == 1 && fake.surfaces.isEmpty, "a second trigger while active is ignored")

        let own = exclusion.pid
        fake.windows = [
            ScreenshotWindow(id: 50, ownerPID: own, frame: CGRect(x: 0, y: 0, width: 200, height: 50),
                             isShared: false),
            ScreenshotWindow(id: 51, ownerPID: 9, frame: CGRect(x: 10, y: 10, width: 60, height: 40)),
            ScreenshotWindow(id: 52, ownerPID: 9, frame: CGRect(x: 10, y: 10, width: 60, height: 40), layer: 25),
        ]
        fake.holdFreeze = false
        fake.release()
        await drain()
        precondition(fake.surfaces.count == 1, "one surface after the freeze")
        precondition(fake.surfaces[0].displays == [1, 2] && fake.surfaces[0].windows == [51],
                     "the surface gets every frozen display and only pickable windows")
        precondition(rig.controller.run(entryID: display))
        await drain()
        precondition(fake.freezes.count == 1, "still one session while the surface is up")
        fake.pick(.rect(CGRect(x: 10, y: 10, width: 20, height: 10)))
        await drain()
        precondition(fake.clipboard.count == 1 && isPNG(fake.clipboard.last), "clipboard by default")
        precondition(pngDPI(fake.clipboard.last).map { abs($0 - 144) < 1 } == true,
                     "an unedited Retina capture says 144 dpi, like an edited one")
        precondition(files(in: downloadsFolder).isEmpty && presenter.posts.isEmpty, "no file by default")

        precondition(rig.controller.run(entryID: area))
        await drain()
        precondition(fake.frozenWindows.last == [51], "only pickable windows are frozen, before selection")
        fake.windowWidth = 31
        fake.closedWindows = [51]
        fake.pick(.window(51))
        await drain()
        precondition(fake.clipboard.count == 2 && pngWidth(fake.clipboard.last) == 30,
                     "a click saves the frozen window, even after it changed or closed")
        precondition(pngDPI(fake.clipboard.last).map { abs($0 - 72) < 1 } != false,
                     "a window's scale is its own pixels per point, not its display's")
        fake.windowWidth = 30

        rig.fire(area)
        await drain()
        precondition(fake.surfaces.last?.windows == [], "a window that would not freeze is not offered")
        fake.pick(nil)
        await drain()
        fake.closedWindows = []

        rig.fire(area)
        await drain()
        fake.pick(nil)
        await drain()
        precondition(fake.clipboard.count == 2 && presenter.posts.isEmpty, "cancel writes nothing")

        rig.fire(area)
        await drain()
        fake.pick(.rect(CGRect(x: 10, y: 10, width: 0, height: 10)))
        await drain()
        precondition(presenter.posts.last?.text == "Capture area is unavailable."
                     && presenter.posts.last?.isFailure == true, "an empty rect is refused")
        rig.fire(area)
        await drain()
        fake.pick(.rect(CGRect(x: 90, y: 10, width: 20, height: 10)))
        await drain()
        precondition(presenter.posts.count == 2, "a rect across two displays is refused")

        rig.defaults.set("file", forKey: "notchcast.screenshot.destination")
        rig.fire(display)
        await drain()
        precondition(fake.freezes.last?.point == fake.cursor, "the screen capture freezes the display under the cursor")
        let first = ScreenshotFileName.name(date: fixedDate, timeZone: .current)
        precondition(files(in: downloadsFolder) == [first], "no folder set means Downloads, v1 name")
        precondition(fake.clipboard.count == 2, "file only leaves the clipboard alone")
        rig.defaults.set(chosenFolder.path(percentEncoded: false), forKey: "notchcast.screenshot.folder")
        rig.fire(display)
        await drain()
        rig.fire(display)
        await drain()
        precondition(files(in: chosenFolder) == [first, ScreenshotFileName.name(
            date: fixedDate, timeZone: .current, collision: 1)].sorted(), "chosen folder, v1 collision suffix")

        rig.defaults.set("both", forKey: "notchcast.screenshot.destination")
        fake.clipboardWorks = false
        let posts = presenter.posts.count
        rig.fire(display)
        await drain()
        precondition(files(in: chosenFolder).count == 3 && presenter.posts.count == posts,
                     "a failed clipboard with the file saved is no failure")
        rig.defaults.set("clipboard", forKey: "notchcast.screenshot.destination")
        rig.fire(display)
        await drain()
        precondition(presenter.posts.last?.text == "Could not copy to clipboard.", "clipboard only failure reports")
        fake.clipboardWorks = true

        rig.defaults.set("both", forKey: "notchcast.screenshot.destination")
        let saved = files(in: chosenFolder)
        let images = fake.clipboard.count
        fake.lines = [
            ScreenTextLine(text: "second", box: CGRect(x: 0.1, y: 0.48, width: 0.5, height: 0.1)),
            ScreenTextLine(text: "first", box: CGRect(x: 0.1, y: 0.6, width: 0.5, height: 0.1)),
        ]
        rig.fire(text)
        await drain()
        precondition(fake.freezes.last?.point == nil && fake.surfaces.count == 7, "text reuses the area surface")
        fake.pick(.rect(CGRect(x: 10, y: 10, width: 20, height: 10)))
        await drain()
        precondition(fake.recognizedWidths == [40] && fake.texts == ["first\nsecond"],
                     "the selected pixels' text is copied in reading order")
        precondition(presenter.posts.last?.text == "first" && presenter.posts.last?.isFailure == false,
                     "a notice shows the first line")
        precondition(presenter.posts.suffix(2).map(\.id) == ["screenshot.text", "screenshot.text"]
                     && presenter.posts.suffix(2).first == recognizing && presenter.posts.last?.progress == nil,
                     "the first line replaces the progress notice under its id")
        precondition(files(in: chosenFolder) == saved && fake.clipboard.count == images,
                     "the image is never saved or copied, whatever the screenshot destination")
        rig.defaults.set("clipboard", forKey: "notchcast.screenshot.destination")

        fake.lines = []
        rig.fire(text)
        await drain()
        fake.pick(.window(51))
        await drain()
        precondition(presenter.posts.last?.text == "No text found in the selected area."
                     && fake.texts.count == 1, "no text found leaves the clipboard alone")

        let notices = presenter.posts.count
        rig.fire(text)
        await drain()
        fake.pick(nil)
        await drain()
        precondition(fake.recognizedWidths.count == 2 && presenter.posts.count == notices, "Esc recognises nothing")

        fake.recognizeFails = true
        rig.fire(text)
        await drain()
        fake.pick(.window(51))
        await drain()
        precondition(presenter.posts.last?.text == "Could not read text from the selection."
                     && presenter.posts.last?.isFailure == true, "a recognition error is not a capture error")
        fake.recognizeFails = false

        fake.lines = [ScreenTextLine(text: "kept", box: CGRect(x: 0, y: 0.5, width: 1, height: 0.1))]
        fake.textWorks = false
        rig.fire(text)
        await drain()
        fake.pick(.display(1))
        await drain()
        precondition(presenter.posts.last?.text == "Could not copy to clipboard.", "a failed text copy reports")
        fake.textWorks = true

        fake.granted = false
        let freezes = fake.freezes.count
        rig.fire(area)
        await drain()
        precondition(presenter.posts.last?.text == "Screen Recording access is required." && fake.freezes.count == freezes,
                     "no access, no freeze")
        precondition(fake.settingsOpened == 0, "a screenshot leaves System Settings closed")
        rig.fire(text)
        await drain()
        precondition(presenter.posts.last?.text == "Screen Recording access is required."
                     && fake.freezes.count == freezes && fake.settingsOpened == 1,
                     "text without access opens the Screen Recording pane")
        fake.granted = true

        precondition(fake.warmOffMain.count == 1, "captures never warm again")
        rig.fire(area)
        await drain()
        let shots = fake.clipboard.count
        rig.controller.preferences.set("screenshot", on: false)
        await drain()
        precondition(fake.closes == 1 && fake.answer == nil, "switching off closes the surface")
        precondition(fake.clipboard.count == shots && !rig.controller.run(entryID: area), "and its commands go")

        rig.finish()
        await warmUpCases()
        print("nc-Screenshots-module-test: ok")
    }

    @MainActor
    static func warmUpCases() async {
        fake.holdWarm = true
        let rig = Rig()
        let presenter = rig.presenter
        await settle("a held warm-up", until: { fake.warmGate != nil })
        precondition(fake.warmOffMain == [true, true], "a new start warms")
        rig.controller.preferences.set("screenshot", on: false)
        await settle("the switch off", until: { presenter.events == ["end screenshot.text"] })
        fake.releaseWarm()
        await settle("the cancelled warm-up", until: { fake.warmCancelled.count == 2 })
        precondition(fake.warmCancelled.last == true, "switching off cancels a warm-up in flight")
        precondition(presenter.posts.isEmpty, "a warm-up shows nothing")

        rig.controller.preferences.set("screenshot", on: true)
        await settle("the warm-up after switching on", until: { fake.warmGate != nil })
        precondition(fake.warmOffMain.count == 3, "switching on warms again")
        fake.lines = [ScreenTextLine(text: "warm", box: CGRect(x: 0, y: 0.5, width: 1, height: 0.1))]
        let recognized = fake.recognizedWidths.count
        let copied = fake.texts.count
        presenter.events = []
        rig.fire(text)
        await settle("the text surface", until: { fake.answer != nil })
        fake.pick(.display(1))
        await settle("the progress notice", until: { !presenter.posts.isEmpty })
        precondition(presenter.posts == [recognizing], "a capture during the warm-up says it is recognising")
        precondition(fake.recognizedWidths.count == recognized, "and recognises nothing until the warm-up ends")
        fake.holdWarm = false
        fake.releaseWarm()
        await settle("the copied text", until: { fake.texts.count == copied + 1 })
        precondition(fake.recognizedWidths.count == recognized + 1 && fake.warmCancelled.last == false,
                     "the capture recognises once after the warm-up it waited for")
        precondition(presenter.posts.last?.id == "screenshot.text" && presenter.posts.last?.text == "warm"
                     && presenter.posts.last?.progress == nil && !presenter.events.contains("end screenshot.text"),
                     "the first line replaces the progress notice in place")

        fake.holdRecognize = true
        presenter.posts = []
        presenter.events = []
        rig.fire(text)
        await settle("the text surface", until: { fake.answer != nil })
        fake.pick(.display(1))
        await settle("a held recognition", until: { fake.recognizeGate != nil })
        precondition(presenter.posts == [recognizing], "the notice shows while recognition runs")
        rig.controller.preferences.set("screenshot", on: false)
        await settle("the switch off", until: { presenter.events.count == 2 })
        precondition(presenter.events == ["post screenshot.text", "end screenshot.text"],
                     "switching off ends the notice, and nothing else, while recognition runs")
        fake.holdRecognize = false
        fake.releaseRecognize()
        rig.controller.preferences.set("screenshot", on: true)
        await settle("the switch on", until: { rig.controller.enabledCommands.contains { $0.id == text } })
        fake.lines = [ScreenTextLine(text: "fresh", box: CGRect(x: 0, y: 0.5, width: 1, height: 0.1))]
        rig.fire(text)
        await settle("the text surface", until: { fake.answer != nil })
        fake.pick(.display(1))
        await settle("the fresh copy", until: { fake.texts.last == "fresh" })
        precondition(fake.texts.suffix(2) == ["warm", "fresh"] && presenter.posts == [recognizing, recognizing]
                     + [IslandNotice(id: "screenshot.text", symbol: "text.viewfinder", text: "fresh")]
                     && presenter.events.filter({ $0.hasPrefix("end") }).count == 1,
                     "a stopped recognition, released late, writes and posts nothing")

        let failures: [(lines: [ScreenTextLine], works: Bool, message: String)] = [
            ([ScreenTextLine](), true, "No text found in the selected area."),
            ([ScreenTextLine(text: "kept", box: CGRect(x: 0, y: 0.5, width: 1, height: 0.1))], false,
             "Could not copy to clipboard."),
        ]
        for (lines, works, failure) in failures {
            fake.lines = lines
            fake.textWorks = works
            presenter.events = []
            rig.fire(text)
            await settle("the text surface", until: { fake.answer != nil })
            fake.pick(.display(1))
            await settle("the failure", until: { presenter.events.last == "post screenshot.failed" })
            precondition(presenter.events == ["post screenshot.text", "end screenshot.text", "post screenshot.failed"]
                         && presenter.posts.last?.text == failure,
                         "a failure ends the progress notice before it reports: \(failure)")
        }
        fake.textWorks = true
        rig.finish()
    }
}
