import Foundation

nonisolated struct MacSetupReceiptStore {
    struct Entry: Codable, Equatable, Sendable {
        let target: String
        let previous: Data?
        let desired: Data?
    }

    struct Receipt: Codable, Equatable, Sendable {
        let entries: [Entry]
        var pending: Int
    }

    enum Failure: Error {
        case outstandingReceipt
        case duplicateTarget
        case invalidReceipt
    }

    private(set) var receipt: Receipt?
    private let persist: (Receipt?) throws -> Void

    init(file: URL) throws {
        let receipt: Receipt?
        do {
            receipt = try JSONDecoder().decode(Receipt?.self, from: Data(contentsOf: file))
        } catch CocoaError.fileReadNoSuchFile {
            receipt = nil
        }
        try self.init(receipt: receipt) { receipt in
            let data = try JSONEncoder().encode(receipt)
            try data.write(to: file, options: .atomic)
        }
    }

    init(receipt: Receipt?, persist: @escaping (Receipt?) throws -> Void) throws {
        if let receipt {
            guard (0...receipt.entries.count).contains(receipt.pending),
                  Set(receipt.entries.map(\.target)).count == receipt.entries.count else {
                throw Failure.invalidReceipt
            }
        }
        self.receipt = receipt
        self.persist = persist
    }

    mutating func apply(_ desired: [(String, Data?)],
                        read: (String) throws -> Data?,
                        write: (String, Data?) throws -> Void) throws {
        guard receipt == nil else { throw Failure.outstandingReceipt }
        guard Set(desired.map(\.0)).count == desired.count else { throw Failure.duplicateTarget }
        let entries = try desired.map { target, value in
            Entry(target: target, previous: try read(target), desired: value)
        }
        try save(Receipt(entries: entries, pending: 0))
        do {
            for (index, entry) in entries.enumerated() {
                // Journal the attempted write because a transport can fail after mutating its target.
                try save(Receipt(entries: entries, pending: index + 1))
                try write(entry.target, entry.desired)
            }
        } catch {
            let failure = error
            try undo(write: write)
            throw failure
        }
    }

    mutating func undo(write: (String, Data?) throws -> Void) throws {
        while let current = receipt, current.pending > 0 {
            let entry = current.entries[current.pending - 1]
            try write(entry.target, entry.previous)
            try save(Receipt(entries: current.entries, pending: current.pending - 1))
        }
        if receipt != nil { try save(nil) }
    }

    private mutating func save(_ next: Receipt?) throws {
        try persist(next)
        receipt = next
    }
}
