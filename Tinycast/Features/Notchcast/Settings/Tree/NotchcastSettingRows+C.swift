import SwiftUI

struct NotchcastSettingRowsC: View {
    let setting: NotchcastSetting

    @ViewBuilder var body: some View {
        switch setting {
        case .dictationHistory: DictationHistorySettingRow()
        case .downloadsFolder:
            DownloadsFolderSettingRow()
        case .downloadsDistillFolder:
            DistillFolderSettingRow()
        case .downloadsTorrents:
            TorrentToolSettingRow(module: TorrentModule.shared)
            TorrentJobsSettingRow(module: TorrentModule.shared)
        case .filesAndClipboardCutPasteShortcut:
            FinderCutPasteSettingRow()
        case .filesAndClipboardRenameShortcut:
            FinderRenameSettingRow()
        case .filesAndClipboardArchives:
            ArchiveToolSettingRow()
            ArchiveJobsSettingRow()
        case .filesAndClipboardURLCleaner:
            URLCleanerCustomParametersSettingRow(module: NotchcastCore.urlCleaner)
            URLCleanerDisabledParametersSettingRow(module: NotchcastCore.urlCleaner)
            URLCleanerSiteParametersSettingRow(module: NotchcastCore.urlCleaner)
            URLCleanerLastRemovedSettingRow(module: NotchcastCore.urlCleaner)
        case .captureScreenshotDestination:
            ScreenshotDestinationSettingRow(module: ScreenshotModule.shared)
            ScreenshotFolderSettingRow(module: ScreenshotModule.shared)
        case .captureScreenTextLineBreaks:
            ScreenTextLineBreaksSettingRow(module: ScreenTextModule.shared)
        case .captureColorFormat:
            ColorFormatSettingRow(module: ColorPickerModule.shared)
        case .captureRecordingOptions:
            RecordingFolderSettingRow(module: RecordingModule.shared)
        case .dictationCleanup:
            DictationCleanupEndpointSettingRow(module: DictationCleanupModule.shared)
            DictationCleanupEffortSettingRow(module: DictationCleanupModule.shared)
            DictationCleanupPromptSettingRow(module: DictationCleanupModule.shared)
            DictationCleanupVocabularySettingRow(module: DictationCleanupModule.shared)
            DictationCleanupAPIKeySettingRow(module: DictationCleanupModule.shared)
        default:
            EmptyView()
        }
    }
}
