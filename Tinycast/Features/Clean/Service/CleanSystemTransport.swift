import Foundation

protocol CleanSystemTransport {
    func list(roots: [CleanSystemPolicy.Root]) throws -> [CleanSystemEntry]
    func snapshots() throws -> [String]
    // Metadata must inspect every ancestor and the leaf without following symlinks.
    func inspect(path: String) throws -> CleanSystemEntry?
    // The transport must atomically validate the reviewed entry before moving it to Trash.
    func trash(_ entry: CleanSystemEntry) throws
}
