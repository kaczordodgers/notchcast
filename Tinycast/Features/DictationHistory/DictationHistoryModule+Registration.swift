import Foundation

extension DictationHistoryModule: NotchcastRegistrant {
    static let shared = DictationHistoryModule(
        repository: .init(directory: NotchcastIdentity.supportRoot.appendingPathComponent("DictationHistory"), now: Date.init))

    static func register(_ core: AppCore) -> [NotchcastModuleController.Entry] {
        [.init(requires: [.dictationHistory], module: shared)]
    }
}
