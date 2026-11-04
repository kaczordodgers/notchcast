import Foundation

struct KeepAwakePlanService: Sendable {
    func acquire(types: [String], create: (String) throws -> UInt32,
                 release: (UInt32) throws -> Void) throws -> [UInt32] {
        var identifiers: [UInt32] = []
        do {
            for type in types { identifiers.append(try create(type)) }
            return identifiers
        } catch {
            let original = error
            let results = identifiers.map { identifier in Result { try release(identifier) } }
            for result in results { try result.get() }
            throw original
        }
    }

    func release(_ identifiers: [UInt32], run: (UInt32) throws -> Void) throws {
        let results = identifiers.map { identifier in Result { try run(identifier) } }
        for result in results { try result.get() }
    }
}
