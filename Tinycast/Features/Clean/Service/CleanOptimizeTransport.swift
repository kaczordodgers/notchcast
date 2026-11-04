import Foundation

protocol CleanOptimizeProcessTransport: Sendable {
    func run(_ request: CleanOptimizeRequest) async throws -> CleanOptimizeRequest.Result
}

protocol CleanOptimizeDatabaseTransport: Sendable {
    // A missing database returns zero; counting must never create it.
    func count(at database: URL, timeout: TimeInterval) async throws -> Int
    // Delete only LSQuarantineEvent rows, then return the remaining count; never vacuum.
    func clear(at database: URL, timeout: TimeInterval) async throws -> Int
}
