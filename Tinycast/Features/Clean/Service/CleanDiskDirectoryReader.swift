import Darwin
import Foundation

/// One directory entry as `getattrlistbulk` reports it. The reader follows the design of Petal's `dirlist.rs`
/// (henrydennis/petal, MIT): names and metadata for many entries per syscall instead of one `lstat` each.
struct CleanDiskEntry: Equatable, Sendable {
    enum Kind: Equatable, Sendable { case file, directory, symbolicLink, other }
    var name: String
    var kind: Kind
    var device: UInt64
    var inode: UInt64
    var linkCount: UInt64
    var allocatedSize: UInt64
    var isDataless: Bool
    var isMountPoint: Bool
}

struct CleanDiskListing: Equatable, Sendable {
    var entries: [CleanDiskEntry] = []
    var entryErrors = 0
}

enum CleanDiskDirectoryReader {
    enum Failure: Error, Equatable {
        case system(Int32)
        case malformed
        case cancelled
    }

    struct Opened: Equatable, Sendable {
        var listing: CleanDiskListing
        var device: UInt64
    }

    struct Directory: Equatable, Sendable {
        var path: String
        var device: UInt64
        var ownAllocation: UInt64
        var mountPath: String
        var blockSize: UInt64
        var blocks: UInt64
        var freeBlocks: UInt64
    }

    typealias BulkRead = (Int32, UnsafeMutableRawPointer, UnsafeMutableRawPointer, Int) -> Int32

    static let bufferSize = 32 * 1024

    static func list(_ path: String, device: UInt64? = nil, limit: Int, stop: () -> Bool = { false }) -> Result<Opened, Failure> {
        read(path, device: device, limit: limit, stop: stop) { getattrlistbulk($0, $1, $2, $3, 0) }
    }

    private static func read(
        _ path: String, device expected: UInt64?, limit: Int, stop: () -> Bool, bulk: BulkRead
    ) -> Result<Opened, Failure> {
        if stop() { return .failure(.cancelled) }
        let fd = openDirectory(path)
        guard fd >= 0 else { return .failure(.system(errno)) }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0 else { return .failure(.system(errno)) }
        let device = UInt64(UInt32(bitPattern: info.st_dev))
        if let expected, device != expected { return .failure(.system(EXDEV)) }
        var attributes = requested
        var listing = CleanDiskListing()
        let failure: Failure? = withUnsafeTemporaryAllocation(byteCount: bufferSize, alignment: 8) { buffer in
            while true {
                if stop() { return .cancelled }
                let count = withUnsafeMutableBytes(of: &attributes) {
                    bulk(fd, $0.baseAddress!, buffer.baseAddress!, buffer.count)
                }
                if count < 0 {
                    if errno == EINTR { continue }
                    return .system(errno)
                }
                if count == 0 { return nil }
                if listing.entries.count + Int(count) > limit { return .system(EOVERFLOW) }
                if !parse(UnsafeRawBufferPointer(buffer), count: Int(count), into: &listing) { return .malformed }
            }
        }
        if let failure { return .failure(failure) }
        return .success(Opened(listing: listing, device: device))
    }

    private static func openDirectory(_ path: String) -> Int32 {
        guard path.hasPrefix("/") else {
            errno = EINVAL
            return -1
        }
        while true {
            let fd = open(path, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW_ANY)
            if fd >= 0 || errno != EINTR { return fd }
        }
    }

    static func directory(_ path: String) -> Result<Directory, CleanDiskSystemError> {
        let fd = openDirectory(path)
        guard fd >= 0 else { return .failure(CleanDiskSystemError(errno)) }
        defer { close(fd) }
        var info = stat(), volume = statfs()
        guard fstat(fd, &info) == 0, fstatfs(fd, &volume) == 0 else {
            return .failure(CleanDiskSystemError(errno))
        }
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        guard fcntl(fd, F_GETPATH, &buffer) == 0 else { return .failure(CleanDiskSystemError(errno)) }
        guard let resolved = String(bytes: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, encoding: .utf8),
                    resolved.hasPrefix("/"), let own = ownAllocation(fd) else { return .failure(CleanDiskSystemError(EIO)) }
        let mount = withUnsafeBytes(of: volume.f_mntonname) {
            String(bytes: $0.prefix { $0 != 0 }, encoding: .utf8) ?? ""
        }
        return .success(Directory(path: resolved, device: UInt64(UInt32(bitPattern: info.st_dev)), ownAllocation: own,
                                  mountPath: mount, blockSize: UInt64(volume.f_bsize),
                                  blocks: UInt64(volume.f_blocks), freeBlocks: UInt64(volume.f_bfree)))
    }

    static func ownAllocation(_ path: String) -> UInt64? {
        guard case .success(let directory) = directory(path) else { return nil }
        return directory.ownAllocation
    }

    private static func ownAllocation(_ fd: Int32) -> UInt64? {
        var attributes = attrlist()
        attributes.bitmapcount = UInt16(ATTR_BIT_MAP_COUNT)
        attributes.dirattr = attrgroup_t(ATTR_DIR_ALLOCSIZE)
        var reply = (UInt64(0), UInt64(0))
        let size = MemoryLayout<UInt32>.size + MemoryLayout<Int64>.size
        return withUnsafeMutableBytes(of: &reply) { bytes -> UInt64? in
            guard fgetattrlist(fd, &attributes, bytes.baseAddress, size, 0) == 0,
                        bytes.loadUnaligned(fromByteOffset: 0, as: UInt32.self) >= UInt32(size) else { return nil }
            return UInt64(max(0, bytes.loadUnaligned(fromByteOffset: 4, as: Int64.self)))
        }
    }

    static func refuseCloudDownloadsOnThisThread() -> Int32? {
        let previous = getiopolicy_np(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, IOPOL_SCOPE_THREAD)
        guard previous >= 0 else { return nil }
        guard setiopolicy_np(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, IOPOL_SCOPE_THREAD,
                                                  IOPOL_MATERIALIZE_DATALESS_FILES_OFF) == 0,
                    cloudDownloadsDisabledOnThisThread() else {
            restoreCloudDownloadsOnThisThread(previous)
            return nil
        }
        return previous
    }

    static func restoreCloudDownloadsOnThisThread(_ previous: Int32) {
        _ = setiopolicy_np(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, IOPOL_SCOPE_THREAD, previous)
    }

    static func cloudDownloadsDisabledOnThisThread() -> Bool {
        getiopolicy_np(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, IOPOL_SCOPE_THREAD) == IOPOL_MATERIALIZE_DATALESS_FILES_OFF
    }

    static var requested: attrlist {
        var attributes = attrlist()
        attributes.bitmapcount = UInt16(ATTR_BIT_MAP_COUNT)
        attributes.commonattr = attrgroup_t(ATTR_CMN_RETURNED_ATTRS)
            | attrgroup_t(ATTR_CMN_ERROR) | attrgroup_t(ATTR_CMN_NAME)
            | attrgroup_t(ATTR_CMN_DEVID) | attrgroup_t(ATTR_CMN_OBJTYPE)
            | attrgroup_t(ATTR_CMN_FLAGS) | attrgroup_t(ATTR_CMN_FILEID)
        attributes.dirattr = attrgroup_t(ATTR_DIR_MOUNTSTATUS) | attrgroup_t(ATTR_DIR_ALLOCSIZE)
        attributes.fileattr = attrgroup_t(ATTR_FILE_LINKCOUNT) | attrgroup_t(ATTR_FILE_ALLOCSIZE)
        return attributes
    }

    static func parse(_ buffer: UnsafeRawBufferPointer, count: Int, into listing: inout CleanDiskListing) -> Bool {
        var parsed = CleanDiskListing()
        var offset = 0
        for _ in 0..<count {
            guard offset + 4 <= buffer.count else { return false }
            let length = Int(buffer.loadUnaligned(fromByteOffset: offset, as: UInt32.self))
            guard length >= 4 + MemoryLayout<attribute_set_t>.size, offset + length <= buffer.count else { return false }
            var record = Record(buffer: buffer, start: offset, end: offset + length, at: offset + 4)
            switch record.entry() {
            case .entry(let entry)?: parsed.entries.append(entry)
            case .unreadable?: parsed.entryErrors += 1
            case nil: return false
            }
            offset += length
        }
        listing.entries += parsed.entries
        listing.entryErrors += parsed.entryErrors
        return true
    }

    private enum Parsed { case entry(CleanDiskEntry), unreadable }

    private struct Record {
        let buffer: UnsafeRawBufferPointer
        let start: Int, end: Int
        var at: Int

        mutating func read<T>(_: T.Type) -> T? {
            guard at + MemoryLayout<T>.size <= end else { return nil }
            defer { at += MemoryLayout<T>.size }
            return buffer.loadUnaligned(fromByteOffset: at, as: T.self)
        }

        mutating func entry() -> Parsed? {
            guard let returned = read(attribute_set_t.self) else { return nil }
            if returned.commonattr & attrgroup_t(ATTR_CMN_ERROR) != 0 {
                guard let error = read(UInt32.self) else { return nil }
                if error != 0 { return .unreadable }
            }
            guard returned.commonattr & attrgroup_t(ATTR_CMN_NAME) != 0 else { return .unreadable }
            let referenceAt = at
            guard let reference = read(attrreference_t.self) else { return nil }
            var device: UInt64?, type: UInt32?, flags: UInt32 = 0, inode: UInt64?
            if returned.commonattr & attrgroup_t(ATTR_CMN_DEVID) != 0 {
                guard let value = read(Int32.self) else { return nil }
                device = UInt64(UInt32(bitPattern: value))
            }
            if returned.commonattr & attrgroup_t(ATTR_CMN_OBJTYPE) != 0 {
                guard let value = read(UInt32.self) else { return nil }
                type = value
            }
            if returned.commonattr & attrgroup_t(ATTR_CMN_FLAGS) != 0 {
                guard let value = read(UInt32.self) else { return nil }
                flags = value
            }
            if returned.commonattr & attrgroup_t(ATTR_CMN_FILEID) != 0 {
                guard let value = read(UInt64.self) else { return nil }
                inode = value
            }
            var mountPoint = false, size: Int64 = 0, links: UInt32 = 1
            if returned.dirattr & attrgroup_t(ATTR_DIR_MOUNTSTATUS) != 0 {
                guard let value = read(UInt32.self) else { return nil }
                mountPoint = value & UInt32(DIR_MNTSTATUS_MNTPOINT) != 0
            }
            if returned.dirattr & attrgroup_t(ATTR_DIR_ALLOCSIZE) != 0 {
                guard let value = read(Int64.self) else { return nil }
                size = value
            }
            if returned.fileattr & attrgroup_t(ATTR_FILE_LINKCOUNT) != 0 {
                guard let value = read(UInt32.self) else { return nil }
                links = value
            }
            if returned.fileattr & attrgroup_t(ATTR_FILE_ALLOCSIZE) != 0 {
                guard let value = read(Int64.self) else { return nil }
                size = value
            }
            let nameStart = referenceAt + Int(reference.attr_dataoffset), nameLength = Int(reference.attr_length)
            guard nameLength >= 1, nameStart >= at, nameStart <= end - nameLength,
                        buffer[nameStart + nameLength - 1] == 0 else { return nil }
            let bytes = UnsafeRawBufferPointer(rebasing: buffer[nameStart..<nameStart + nameLength - 1])
            guard let device, let type, let inode, let name = Self.component(bytes) else { return .unreadable }
            let kind: CleanDiskEntry.Kind = switch type {
            case UInt32(VREG.rawValue): .file
            case UInt32(VDIR.rawValue): .directory
            case UInt32(VLNK.rawValue): .symbolicLink
            default: .other
            }
            return .entry(CleanDiskEntry(name: name, kind: kind, device: device,
                                        inode: inode, linkCount: UInt64(max(links, 1)),
                                        allocatedSize: UInt64(max(size, 0)),
                                        isDataless: flags & UInt32(SF_DATALESS) != 0,
                                        isMountPoint: kind == .directory && mountPoint))
        }

        static func component(_ bytes: UnsafeRawBufferPointer) -> String? {
            guard !bytes.isEmpty, !bytes.contains(0), !bytes.contains(UInt8(ascii: "/")),
                        let name = String(bytes: bytes, encoding: .utf8), name.utf8.elementsEqual(bytes),
                        name != ".", name != ".." else { return nil }
            return name
        }
    }
}

struct CleanDiskSystemError: Error, Equatable, Sendable {
    let code: Int32
    init(_ code: Int32) { self.code = code }
}
