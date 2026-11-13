// notchcast-sources: Tinycast/Features/Music/Model/NowPlaying.swift
// notchcast-sources: Tinycast/Features/Music/Model/SoloistProtocol.swift
import Foundation

@main
struct UnusedQueueTest {
    static func main() throws {
        let message = try SoloistProtocol.parse(
            #"{"type":"queue_changed","upcoming":[{"item":{"uri":"spotify:track:fixture"}}]}"#, now: .now)
        precondition(message == .other, "Queue payloads without a consumer must be ignored")
        print("PASS: unused queue data is ignored")
    }
}
