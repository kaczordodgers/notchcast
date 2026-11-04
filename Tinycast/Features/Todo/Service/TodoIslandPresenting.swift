import Foundation

@MainActor
protocol TodoIslandPresenting: AnyObject {
    func update(_ snapshot: TodoIslandSnapshot)
}
