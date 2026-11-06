import Darwin
import Foundation

nonisolated enum ArchiveRawStream {
    @concurrent static func read(
        _ archive: URL, output: URL? = nil, maximumBytes: Int64,
        progress: @escaping @Sendable (Int64) async -> Void = { _ in }
    ) async throws -> Int64 {
        guard let library = dlopen("/usr/lib/libarchive.2.dylib", RTLD_NOW | RTLD_LOCAL) else {
            throw ArchiveFailure.filesystem("libarchive unavailable")
        }
        defer { dlclose(library) }
        func symbol<Function>(_ name: String, as type: Function.Type) throws -> Function {
            guard let address = dlsym(library, name) else { throw ArchiveFailure.filesystem(name) }
            return unsafeBitCast(address, to: type)
        }
        typealias Configure = @convention(c) (OpaquePointer) -> Int32
        let create = try symbol("archive_read_new", as: (@convention(c) () -> OpaquePointer?).self)
        let free = try symbol("archive_read_free", as: Configure.self)
        let raw = try symbol("archive_read_support_format_raw", as: Configure.self)
        let empty = try symbol("archive_read_support_format_empty", as: Configure.self)
        let compression = archive.pathExtension.lowercased()
        let filterName = compression == "gz" ? "gzip" : compression == "bz2" ? "bzip2" : "xz"
        let filter = try symbol("archive_read_support_filter_" + filterName, as: Configure.self)
        let open = try symbol("archive_read_open_filename",
                              as: (@convention(c) (OpaquePointer, UnsafePointer<CChar>, Int) -> Int32).self)
        let header = try symbol("archive_read_next_header",
                                as: (@convention(c) (OpaquePointer, UnsafeMutablePointer<OpaquePointer?>) -> Int32).self)
        let read = try symbol("archive_read_data",
                              as: (@convention(c) (OpaquePointer, UnsafeMutableRawPointer, Int) -> Int).self)
        let filterCode = try symbol("archive_filter_code", as: (@convention(c) (OpaquePointer, Int32) -> Int32).self)
        guard let reader = create() else { throw ArchiveFailure.filesystem("archive_read_new") }
        defer { _ = free(reader) }
        guard raw(reader) == 0, empty(reader) == 0, filter(reader) == 0,
              open(reader, archive.path, 65_536) == 0,
              filterCode(reader, 0) == (compression == "gz" ? 1 : compression == "bz2" ? 2 : 6) else {
            throw ArchiveFailure.damagedArchive
        }
        var entry: OpaquePointer?
        let status = header(reader, &entry)
        guard status == 0 || status == 1 else { throw ArchiveFailure.damagedArchive }
        let destination: FileHandle?
        if let output {
            try Data().write(to: output, options: .withoutOverwriting)
            destination = try FileHandle(forWritingTo: output)
        } else {
            destination = nil
        }
        defer { try? destination?.close() }
        var buffer = [UInt8](repeating: 0, count: 65_536)
        var total: Int64 = 0
        var updated = ContinuousClock.now
        while status == 0 {
            try Task.checkCancellation()
            let count = read(reader, &buffer, buffer.count)
            guard count >= 0 else { throw ArchiveFailure.damagedArchive }
            if count == 0 { break }
            guard Int64(count) <= maximumBytes - total else { throw ArchiveFailure.expansionLimit }
            total += Int64(count)
            if let output { try ArchiveFallbackSpace.check(output.deletingLastPathComponent(), additionalBytes: Int64(count)) }
            try destination?.write(contentsOf: Data(buffer.prefix(count)))
            if updated.duration(to: .now) >= .milliseconds(250) {
                await progress(total)
                updated = .now
            }
        }
        try Task.checkCancellation()
        return total
    }
}
