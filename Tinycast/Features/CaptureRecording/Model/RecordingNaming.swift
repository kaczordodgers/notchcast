import Foundation

enum RecordingNaming {
    static func filename(date: Date, timeZone: TimeZone, collision: Int = 0) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let stem = "Recording \(formatter.string(from: date))"
        return collision == 0 ? "\(stem).mp4" : "\(stem) (\(collision)).mp4"
    }
}
