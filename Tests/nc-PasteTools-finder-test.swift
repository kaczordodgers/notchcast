// notchcast-sources: Tinycast/Features/PasteTools/Service/FinderImageService.swift
import Foundation

@main
struct PasteToolsFinderTest {
    static func main() {
        let finder = NSAppleEventDescriptor(bundleIdentifier: "com.apple.finder")
        let file = URL(filePath: "/tmp/clipboard-image-test.png")
        let front = FinderImageService.moveEvent(file, toFrontWindow: true, to: finder)
        let desktop = FinderImageService.moveEvent(file, toFrontWindow: false, to: finder)
        let event = FinderImageService.Event.self
        precondition(front.eventClass == event.core)
        precondition(front.eventID == event.move)
        precondition(front.paramDescriptor(forKeyword: event.directObject) != nil)
        precondition(front.paramDescriptor(forKeyword: event.insertHere) != nil)
        precondition(desktop.paramDescriptor(forKeyword: event.insertHere) != nil)
        precondition(FinderImageService.countEvent(to: finder).eventID == event.count)
        precondition(FinderImageService.selectEvent(.null(), to: finder).eventID == event.select)
        precondition(FinderImageService.result(for: -48) == .nameTaken)
        precondition(FinderImageService.result(for: -1743) == .failed)
        precondition(FinderImageService.insertionLocation.descriptorType == event.objectSpecifier)
        precondition(FinderImageService.Event.insertionLocation == 0x70696e73)
        precondition(FinderImageService.timeout == 30)
        print("✓ PasteTools: Finder event construction and error mapping passed; no events sent")
    }
}
