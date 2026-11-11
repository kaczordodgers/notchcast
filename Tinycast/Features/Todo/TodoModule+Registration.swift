import Foundation

extension TodoModule: NotchcastRegistrant {
    static private(set) var shared: TodoModule?

    static func register(_ core: AppCore) -> [NotchcastModuleController.Entry] {
        let tasks = TodoModule(directory: NotchcastIdentity.supportRoot.appending(path: "Todo"),
                               islandEnabled: { NotchcastPreferences.shared.isOn(.todoIsland) },
                               showFailure: { NotchcastHost.current.showMessage($0, .danger) })
        shared = tasks
        return [.init(requires: [.tasks], module: tasks)]
    }
}
