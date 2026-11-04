import Foundation

protocol CleanTrashTransport: Sendable {
    func trash(_ url: URL) throws
}
