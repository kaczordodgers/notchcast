import Foundation

struct CleanFileTrashTransport: CleanTrashTransport {
    func trash(_ url: URL) throws {
        try FileManager().trashItem(at: url, resultingItemURL: nil)
    }
}
