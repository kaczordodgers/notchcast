extension NotchcastDownloadCommands {
    enum Action: CaseIterable {
        case video, audio, transcript, webpage, addDistill, runDistill, convert, openDownloads, openDistill

        var requiredFeature: NotchcastFeature {
            switch self {
            case .video, .audio, .transcript, .webpage, .openDownloads: .downloads
            case .addDistill, .runDistill, .openDistill: .distill
            case .convert: .distillConvert
            }
        }

        var usesDistill: Bool {
            switch self {
            case .addDistill, .runDistill, .convert, .openDistill: true
            default: false
            }
        }
    }
}
