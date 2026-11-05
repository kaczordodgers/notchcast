import Foundation

struct FinderImageService {
    enum PlaceResult { case placed, nameTaken, failed }

    static func save(_ png: Data) -> Bool {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for attempt in 1...10 {
                try Task.checkCancellation()
                let file = folder.appendingPathComponent("Pasted Image \(Int(Date().timeIntervalSince1970)) \(attempt).png")
                try png.write(to: file)
                switch Self().place(file) {
                case .placed: return true
                case .failed: return false
                case .nameTaken: try FileManager.default.removeItem(at: file)
                }
            }
        } catch { return false }
        return false
    }

    static let nameTaken = -48
    static let timeout: TimeInterval = 30

    func place(_ file: URL) -> PlaceResult {
        let finder = NSAppleEventDescriptor(bundleIdentifier: "com.apple.finder")
        let move = Self.moveEvent(file, to: finder)
        move.setParam(Self.insertionLocation, forKeyword: Event.insertHere)
        switch Self.send(move) {
        case .failure(let failure):
            return Self.result(for: failure)
        case .success(let reply):
            if let moved = reply?.paramDescriptor(forKeyword: Event.directObject) {
                _ = Self.send(Self.selectEvent(moved, to: finder))
            }
            return .placed
        }
    }

    static func result(for code: Int) -> PlaceResult { code == nameTaken ? .nameTaken : .failed }

    private static func send(_ event: NSAppleEventDescriptor) -> Result<NSAppleEventDescriptor?, Failure> {
        do {
            let reply = try event.sendEvent(options: [.waitForReply, .canInteract], timeout: timeout)
            let code = Int(reply.paramDescriptor(forKeyword: Event.errorNumber)?.int32Value ?? 0)
            return code == 0 ? .success(reply) : .failure(Failure(code: code))
        } catch {
            return .failure(Failure(code: (error as NSError).code))
        }
    }

    static func moveEvent(_ file: URL, to finder: NSAppleEventDescriptor) -> NSAppleEventDescriptor {
        let event = NSAppleEventDescriptor(eventClass: Event.core, eventID: Event.move, targetDescriptor: finder,
            returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID))
        event.setParam(NSAppleEventDescriptor(fileURL: file), forKeyword: Event.directObject)
        return event
    }

    static func selectEvent(_ item: NSAppleEventDescriptor, to finder: NSAppleEventDescriptor) -> NSAppleEventDescriptor {
        let event = NSAppleEventDescriptor(eventClass: Event.misc, eventID: Event.select, targetDescriptor: finder,
            returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID))
        event.setParam(item, forKeyword: Event.directObject)
        return event
    }

    static var insertionLocation: NSAppleEventDescriptor {
        specifier(Event.propertyClass, in: .null(), form: Event.propertyForm,
                  data: NSAppleEventDescriptor(typeCode: Event.insertionLocation))
    }

    private static func specifier(_ wanted: OSType, in container: NSAppleEventDescriptor, form: OSType,
                                  data: NSAppleEventDescriptor) -> NSAppleEventDescriptor {
        let record = NSAppleEventDescriptor.record()
        record.setDescriptor(NSAppleEventDescriptor(typeCode: wanted), forKeyword: Event.want)
        record.setDescriptor(container, forKeyword: Event.container)
        record.setDescriptor(NSAppleEventDescriptor(enumCode: form), forKeyword: Event.form)
        record.setDescriptor(data, forKeyword: Event.data)
        return record.coerce(toDescriptorType: Event.objectSpecifier) ?? record
    }

    private struct Failure: Error, Equatable {
        let code: Int
    }

    private static func result(for failure: Failure) -> PlaceResult { result(for: failure.code) }

    nonisolated enum Event {
        static let core = code("core"), misc = code("misc")
        static let move = code("move"), select = code("slct")
        static let directObject = code("----"), insertHere = code("insh"), errorNumber = code("errn")
        static let propertyClass = code("prop"), insertionLocation = code("pins")
        static let want = code("want"), container = code("from"), form = code("form"), data = code("seld")
        static let propertyForm = code("prop"), objectSpecifier = code("obj ")

        static func code(_ text: String) -> OSType {
            text.utf8.reduce(0) { $0 << 8 | OSType($1) }
        }
    }
}
