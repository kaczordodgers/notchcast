import Foundation

enum NotchcastToolsLauncherCommands {
    @MainActor static weak var controller: NotchcastToolsCommands?

    static let convertFiles = all[0]
    static let compressVideo = all[1]
    static let makeGIF = all[2]
    static let compressImage = all[3]
    static let resizeImage = all[4]
    static let extractText = all[5]
    static let runHostCommand = all[6]
    static let listCommands = all[7]

    static let all = NotchcastToolsCommands.Action.allCases.map { action in
        NotchcastCommand(slug: action.rawValue, name: action.name, sfSymbol: "wrench.and.screwdriver",
            isEnabled: { controller?.isEnabled(action) ?? false },
            run: { controller?.perform(action) })
    }
}
