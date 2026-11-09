import Foundation

@MainActor
final class MusicSharpCoversModule: NotchcastModule {
    private let finder: BrowserCoverFinder
    private let model: MusicModel

    init(model: MusicModel, finder: BrowserCoverFinder = BrowserCoverFinder()) {
        self.model = model
        self.finder = finder
        finder.onFound = { [weak model] in model?.present() }
    }

    func start() {
        model.nowPlayingCover = { [weak finder] in finder?.cover(for: $0) ?? $0 }
        model.present()
    }

    func stop() {
        model.nowPlayingCover = { $0 }
        finder.reset()
        model.present()
    }
}
