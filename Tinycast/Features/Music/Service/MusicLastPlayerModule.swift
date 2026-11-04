@MainActor
final class MusicLastPlayerModule: NotchcastModule {
    private let model: MusicModel

    init(model: MusicModel) { self.model = model }
    func start() { model.lastPlayer.setEnabled(true) }
    func stop() { model.lastPlayer.setEnabled(false) }
}
