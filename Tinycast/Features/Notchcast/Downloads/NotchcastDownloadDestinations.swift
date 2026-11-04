import Foundation

enum NotchcastDownloadDestinations {
    static let downloads = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Downloads")
    static let distill = downloads.appending(path: "Distill/Raw")
}
