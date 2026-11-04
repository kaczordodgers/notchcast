@MainActor
final class InUseMarksModule: NotchcastModule {
    let model: InUseMarks

    init(model: InUseMarks) { self.model = model }
    func start() { model.setEnabled(true) }
    func stop() { model.setEnabled(false) }
}
