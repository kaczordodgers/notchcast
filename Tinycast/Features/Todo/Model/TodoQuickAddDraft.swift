import Foundation

struct TodoQuickAddDraft: Equatable, Sendable {
    var title: String
    var project: String?
    var section: String?
    var labels: [String] = []
    var priority: Int = 1
    var date: TodoQuickAddDate?
    var tokens: [TodoQuickAddToken] = []
}
