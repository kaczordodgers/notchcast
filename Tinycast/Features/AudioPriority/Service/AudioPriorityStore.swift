import Foundation

@MainActor
protocol AudioPriorityStore: AnyObject {
    func ranking(for direction: AudioPriorityDevice.Direction) -> AudioPriorityRanking
    func save(_ ranking: AudioPriorityRanking, for direction: AudioPriorityDevice.Direction)
}
