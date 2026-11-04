import Foundation

struct CaptureTrim: Equatable, Sendable {
    enum Handle: Sendable { case start, end }
    enum Format: Sendable { case mp4, gif }

    let duration: Double
    let frame: Double
    private(set) var start: Double = 0
    private(set) var end: Double
    private(set) var playhead: Double = 0
    private(set) var isPlaying = false
    var selected: Handle = .start
    var format: Format = .mp4

    init(duration: Double, framesPerSecond: Double) {
        self.duration = duration.isFinite ? max(0, duration) : 0
        frame = framesPerSecond.isFinite && framesPerSecond > 0 ? 1 / framesPerSecond : 1 / 30
        end = self.duration
    }

    mutating func set(_ handle: Handle, to time: Double) {
        guard time.isFinite else { return }
        isPlaying = false
        selected = handle
        let minimum = min(frame, duration)
        switch handle {
        case .start: start = min(max(0, time), end - minimum)
        case .end: end = min(duration, max(start + minimum, time))
        }
        seek(to: handle == .start ? start : end)
    }

    mutating func seek(to time: Double) {
        guard time.isFinite else { return }
        playhead = min(end, max(start, time))
    }

    mutating func step(direction: Int, bySecond: Bool = false) {
        let time = selected == .start ? start : end
        set(selected, to: time + Double(direction.signum()) * (bySecond ? 1 : frame))
    }

    mutating func markStart() { set(.start, to: playhead) }
    mutating func markEnd() { set(.end, to: playhead) }
    mutating func togglePlayback() {
        if playhead >= end { playhead = start }
        isPlaying.toggle()
    }
}
