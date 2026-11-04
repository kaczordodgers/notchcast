import AppKit
import Quartz

@MainActor
final class QuickLookSystemPresenter: NSObject, @MainActor QLPreviewPanelDataSource {
    private var item: URL?

    func close() {
        guard item != nil else { return }
        QLPreviewPanel.shared()?.orderOut(nil)
        item = nil
    }

    func show(_ request: QuickLookRequest) {
        guard let panel = QLPreviewPanel.shared() else { return }
        item = request.fileURL
        panel.dataSource = self
        panel.reloadData()
        panel.makeKeyAndOrderFront(nil)
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel?) -> Int { item == nil ? 0 : 1 }

    func previewPanel(_ panel: QLPreviewPanel?, previewItemAt index: Int) -> (any QLPreviewItem)? {
        item as NSURL?
    }
}
