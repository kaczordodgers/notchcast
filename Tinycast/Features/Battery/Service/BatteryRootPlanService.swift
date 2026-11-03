import Foundation

struct BatteryRootPlanService: Sendable {
    enum Failure: Error { case readbackMismatch }

    func apply(_ verb: BatteryRootVerbs, modern: Bool,
               write: (String, [UInt8]) throws -> Void,
               read: (String) throws -> [UInt8]) throws {
        for operation in verb.writes(modern: modern) {
            try write(operation.key, operation.bytes)
            guard try read(operation.key) == operation.bytes else { throw Failure.readbackMismatch }
        }
    }
}
