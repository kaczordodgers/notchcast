import SwiftUI

struct NotchcastSettingRowsC: View {
    let setting: NotchcastSetting

    @ViewBuilder var body: some View {
        switch setting {
        case .downloadsFolder:
            DownloadsFolderSettingRow()
        case .downloadsDistillFolder:
            DistillFolderSettingRow()
        case .downloadsTorrents:
            TorrentToolSettingRow(module: NotchcastCore.torrents)
            TorrentJobsSettingRow(module: NotchcastCore.torrents)
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
            ScreenshotDestinationSettingRow(module: NotchcastCore.screenshot)
            ScreenshotFolderSettingRow(module: NotchcastCore.screenshot)
        case .captureScreenTextLineBreaks:
            ScreenTextLineBreaksSettingRow(module: NotchcastCore.screenText)
        case .captureColorFormat:
            ColorFormatSettingRow(module: NotchcastCore.colorPicker)
        case .captureRecordingOptions:
            RecordingFolderSettingRow(module: NotchcastCore.recording)
        case .dictationCleanup:
            DictationCleanupEndpointSettingRow(module: NotchcastCore.dictationCleanup)
            DictationCleanupEffortSettingRow(module: NotchcastCore.dictationCleanup)
            DictationCleanupPromptSettingRow(module: NotchcastCore.dictationCleanup)
            DictationCleanupVocabularySettingRow(module: NotchcastCore.dictationCleanup)
            DictationCleanupAPIKeySettingRow(module: NotchcastCore.dictationCleanup)
        default:
            EmptyView()
        }
    }
}
