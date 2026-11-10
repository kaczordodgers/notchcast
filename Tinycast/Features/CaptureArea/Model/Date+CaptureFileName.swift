import Foundation

extension Date {
    func captureFileName(kind: String, extension fileExtension: String, timeZone: TimeZone, collision: Int = 0) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let stem = "\(kind) \(formatter.string(from: self))"
        return collision == 0 ? "\(stem).\(fileExtension)" : "\(stem) (\(collision)).\(fileExtension)"
    }
}
