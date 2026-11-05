import Foundation
import CryptoKit

struct TodoLinkPacket: Codable, Equatable, Sendable {
    static let maximumBytes = 40_000

    let clock: TodoVectorClock
    let envelopes: [TodoEnvelope]
    let hasMore: Bool
    var chunk: Chunk?
    var receipt: Receipt?

    struct Receipt: Codable, Equatable, Sendable {
        let id: TodoEnvelope.ID
        let offset: Int
    }

    struct Chunk: Codable, Equatable, Sendable {
        let id: TodoEnvelope.ID
        let total: Int
        let digest: Data
        let offset: Int
        let bytes: Data
    }

    enum Failure: Error {
        case tooLarge
        case unavailable
        case noProgress
        case invalidChunk
    }

    static func make(from replication: TodoReplication, after clock: TodoVectorClock,
                     receipt: Receipt? = nil) throws -> Self {
        let missing = replication.envelopes(after: clock)
        let known = replication.vectorClock
        let encoder = JSONEncoder()
        let empty = Self(clock: known, envelopes: [], hasMore: false)
        var bytes = try encoder.encode(empty).count
        guard bytes <= maximumBytes else { throw Failure.tooLarge }
        var selected: [TodoEnvelope] = []
        for envelope in missing {
            let size = try encoder.encode(envelope).count + 1
            guard bytes + size <= maximumBytes else { break }
            selected.append(envelope)
            bytes += size
        }
        if selected.isEmpty, let envelope = missing.first {
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(envelope)
            guard data.count <= TodoLinkAssembly.maximumBytes else { throw Failure.tooLarge }
            let offset = receipt?.id == envelope.id ? receipt!.offset : 0
            guard offset >= 0, offset < data.count else { throw Failure.invalidChunk }
            let packet = Self(clock: known, envelopes: [], hasMore: true,
                        chunk: Chunk(id: envelope.id, total: data.count, digest: Data(SHA256.hash(data: data)),
                                     offset: offset, bytes: data.subdata(in: offset..<min(offset + 20_000, data.count))))
            guard try encoder.encode(packet).count <= maximumBytes else { throw Failure.tooLarge }
            return packet
        }
        return Self(clock: known, envelopes: selected, hasMore: selected.count < missing.count)
    }
}

struct TodoLinkAssembly {
    static let maximumBytes = 8 * 1_024 * 1_024
    private var chunk: TodoLinkPacket.Chunk?
    private var data = Data()
    var receipt: TodoLinkPacket.Receipt? {
        chunk.map { .init(id: $0.id, offset: data.count) }
    }

    mutating func receive(_ incoming: TodoLinkPacket.Chunk) throws -> TodoEnvelope? {
        guard incoming.total > 0, incoming.total <= Self.maximumBytes else { throw TodoLinkPacket.Failure.tooLarge }
        guard incoming.offset >= 0, !incoming.bytes.isEmpty,
              incoming.bytes.count <= incoming.total,
              incoming.offset <= incoming.total - incoming.bytes.count,
              incoming.digest.count == 32 else { throw TodoLinkPacket.Failure.invalidChunk }
        if chunk?.id != incoming.id {
            guard incoming.offset == 0 else { throw TodoLinkPacket.Failure.invalidChunk }
            chunk = incoming
            data = Data()
        }
        guard let chunk, chunk.total == incoming.total, chunk.digest == incoming.digest,
              incoming.offset <= data.count else { throw TodoLinkPacket.Failure.invalidChunk }
        if incoming.offset < data.count {
            guard incoming.offset + incoming.bytes.count <= data.count,
                  data.subdata(in: incoming.offset..<incoming.offset + incoming.bytes.count) == incoming.bytes else {
                throw TodoLinkPacket.Failure.invalidChunk
            }
        } else { data.append(incoming.bytes) }
        guard data.count == incoming.total else { return nil }
        guard Data(SHA256.hash(data: data)) == incoming.digest else { throw TodoLinkPacket.Failure.invalidChunk }
        let envelope = try JSONDecoder().decode(TodoEnvelope.self, from: data)
        guard envelope.id == incoming.id else { throw TodoLinkPacket.Failure.invalidChunk }
        self = Self()
        return envelope
    }
}
