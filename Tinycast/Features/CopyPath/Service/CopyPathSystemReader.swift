import AppKit
import ApplicationServices

enum CopyPathSystemReader {
    private enum Step {
        case first(String)
        case property(String)
    }

    @concurrent
    static func read(_ request: CopyPathService.Request) async throws -> [String] {
        try Task.checkCancellation()
        let result: [String]
        switch request {
        case .finderSelection:
            let selected = try get("com.apple.finder", steps: [.property("sele")])
            result = try selected.flatMap { item in
                try get("com.apple.finder", steps: [.property("pURL")], container: item).compactMap(\.stringValue)
            }.compactMap(filePath)
        case .finderFolder:
            result = try get("com.apple.finder", steps: [.first("brow"), .property("fvtg"), .property("pURL")])
                .compactMap(\.stringValue).compactMap(filePath)
        case .browser(let target):
            guard let bundleID = target.bundleID, let browser = target.browser else { return [] }
            let steps: [Step] = switch browser {
            case .safari: [.first("docu"), .property("pURL")]
            case .chromium: [.first("cwin"), .property("acTa"), .property("URL ")]
            }
            result = try get(bundleID, steps: steps).compactMap(\.stringValue)
        case .document(let target):
            guard AXIsProcessTrusted() else { throw CopyPathService.Failure.needsAccessibility }
            result = try document(processID: target.processID).map { [$0] } ?? []
        }
        try Task.checkCancellation()
        return result
    }

    private static func filePath(_ address: String) -> String? {
        guard let url = URL(string: address), url.isFileURL else { return nil }
        return url.path(percentEncoded: false)
    }

    private static func get(
        _ bundleID: String, steps: [Step], container: NSAppleEventDescriptor = .null()
    ) throws -> [NSAppleEventDescriptor] {
        try Task.checkCancellation()
        var specifier = container
        for step in steps {
            let record = NSAppleEventDescriptor.record()
            record.setDescriptor(specifier, forKeyword: code("from"))
            switch step {
            case .first(let name):
                record.setDescriptor(NSAppleEventDescriptor(typeCode: code(name)), forKeyword: code("want"))
                record.setDescriptor(NSAppleEventDescriptor(enumCode: code("indx")), forKeyword: code("form"))
                record.setDescriptor(NSAppleEventDescriptor(int32: 1), forKeyword: code("seld"))
            case .property(let name):
                record.setDescriptor(NSAppleEventDescriptor(typeCode: code("prop")), forKeyword: code("want"))
                record.setDescriptor(NSAppleEventDescriptor(enumCode: code("prop")), forKeyword: code("form"))
                record.setDescriptor(NSAppleEventDescriptor(typeCode: code(name)), forKeyword: code("seld"))
            }
            guard let object = record.coerce(toDescriptorType: code("obj ")) else {
                throw CopyPathService.Failure.unreadable
            }
            specifier = object
        }
        let event = NSAppleEventDescriptor(
            eventClass: code("core"), eventID: code("getd"),
            targetDescriptor: NSAppleEventDescriptor(bundleIdentifier: bundleID),
            returnID: -1, transactionID: 0)
        event.setParam(specifier, forKeyword: code("----"))
        let reply: NSAppleEventDescriptor
        do {
            reply = try event.sendEvent(options: [.waitForReply, .canInteract], timeout: 5)
        } catch let error as NSError {
            if [-1728, -1719].contains(error.code) { return [] }
            throw CopyPathService.Failure.appleEvent(error.code)
        }
        if let error = reply.paramDescriptor(forKeyword: code("errn")), error.int32Value != 0 {
            if [-1728, -1719].contains(error.int32Value) { return [] }
            throw CopyPathService.Failure.appleEvent(Int(error.int32Value))
        }
        guard let answer = reply.paramDescriptor(forKeyword: code("----")) else { return [] }
        guard answer.descriptorType == code("list") else { return [answer] }
        return answer.numberOfItems > 0 ? (1...answer.numberOfItems).compactMap { answer.atIndex($0) } : []
    }

    private static func code(_ text: String) -> UInt32 {
        text.utf8.reduce(0) { ($0 << 8) | UInt32($1) }
    }

    private static func document(processID: Int32) throws -> String? {
        let app = AXUIElementCreateApplication(processID)
        AXUIElementSetMessagingTimeout(app, 1)
        for attribute in [kAXFocusedWindowAttribute, kAXMainWindowAttribute] {
            var window: CFTypeRef?
            let status = AXUIElementCopyAttributeValue(app, attribute as CFString, &window)
            if status == .apiDisabled { throw CopyPathService.Failure.needsAccessibility }
            guard status == .success, let window, CFGetTypeID(window) == AXUIElementGetTypeID() else { continue }
            var value: CFTypeRef?
            let element = unsafeDowncast(window, to: AXUIElement.self)
            let read = AXUIElementCopyAttributeValue(element, kAXDocumentAttribute as CFString, &value)
            if read == .apiDisabled { throw CopyPathService.Failure.needsAccessibility }
            if let text = value as? String, !text.isEmpty { return text }
        }
        return nil
    }
}
