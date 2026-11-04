#if DEBUG
import AppKit
import SwiftUI

extension GalleryPages {
    static func island(_ core: AppCore) -> [GalleryPage] {
        [true, false].flatMap { mba in
            let display = CGRect(x: 0, y: 0, width: mba ? 1470 : 1920, height: mba ? 956 : 1080)
            let notch = mba ? CGRect(x: display.midX - 92, y: display.maxY - 32, width: 184, height: 32) : nil
            let suffix = mba ? "mba" : "ext"
            let closed = ["idle", "timer", "transfer", "status"].map { state in
                islandPage(core, name: "island-closed-\(state)-\(suffix)",
                           display: display, notch: notch, state: state, open: false)
            }
            let opened = ["home-empty", "home-entries", "day-calendar"].map { state in
                islandPage(core, name: "island-open-\(state)-\(suffix)",
                           display: display, notch: notch, state: state, open: true)
            }
            return closed + opened
        }
    }

    private static func islandPage(
        _ core: AppCore, name: String, display: CGRect, notch: CGRect?, state: String, open: Bool
    ) -> GalleryPage {
        GalleryPage(name: name, types: ["IslandPanel", "IslandSurfaceView", "IslandClosedView",
                                       "IslandContentView", "IslandHeaderView"]
                    + (state == "day-calendar" ? ["ScheduleList"] : (open ? ["IslandHomeView"] : [])),
                    hardwareNotch: notch.map {
                        CGRect(x: $0.minX - (display.midX - NotchcastTheme.openMinimumWidth / 2),
                               y: NotchcastTheme.maximumHeight - $0.height, width: $0.width, height: $0.height)
                    }, silhouette: { window in
                        (window.contentView?.layer?.mask as? CAShapeLayer)?.path ?? CGMutablePath()
                    }, makeWindow: {
            for activity in IslandActivityCenter.shared.activities { IslandActivityCenter.shared.finish(activity.id) }
            let activity = IslandActivity(kind: state == "timer" ? .timer : .transfer,
                                          title: state == "timer" ? "Tea timer" : "Sample transfer",
                                          progress: state == "timer" ? nil : 0.64,
                                          endDate: state == "timer" ? Date().addingTimeInterval(300) : nil)
            let panel = IslandPanel(screenFrame: display, hardwareNotch: notch)
            let island = IslandController()
            let pages = IslandPagesCoordinator(core: core, island: island)
            let header = IslandHeaderView(cameraWidth: notch?.width ?? 0, height: panel.headerHeight)
                .environment(island).environment(pages)
            var compact = IslandController.ClosedContent()
            if state == "timer" || state == "transfer" {
                compact = IslandController.ClosedContent(leading: AnyView(IslandActivityGlyph(activity: activity)),
                                                         trailing: AnyView(IslandActivityValue(activity: activity)))
            }
            if state == "home-entries" {
                NotchcastPreferences.shared.set(.islandLiveActivities, true)
                IslandActivityCenter.shared.begin(activity)
                IslandActivityCenter.shared.begin(IslandActivity(kind: .status, title: "Sample export complete"))
            }
            let content: AnyView
            if state == "day-calendar" {
                let now = Date()
                let events = ["Design review", "Project planning"].enumerated().map { index, title in
                    MeetingEvent(id: "sample-\(index)", title: title,
                                 start: now.addingTimeInterval(Double(index + 1) * 3600),
                                 end: now.addingTimeInterval(Double(index + 1) * 3600 + 1800),
                                 isAllDay: false, isDeclined: false, calendarID: "sample",
                                 calendarName: "Sample calendar", calendarColor: .init(red: 0.4, green: 0.6, blue: 1),
                                 calendarItemID: "sample-\(index)", link: nil)
                }
                content = AnyView(ScheduleList(results: events, selectedID: events.first?.id, now: now,
                                               scroll: ScrollIntent(kind: .top), onActivate: { _ in }, onActions: { _ in })
                    .frame(height: 200))
            } else { content = AnyView(IslandHomeView()) }
            panel.setContent(open: AnyView(content.paletteEnvironment(core)), closed: compact,
                             header: AnyView(header.paletteEnvironment(core)))
            if state == "status" {
                panel.setMessage(IslandMessage(id: UUID(), tone: .success, text: "Sample export complete",
                                              isProgress: false, onCancel: nil))
            }
            panel.setOpen(open, animated: false)
            return panel
        }, prepare: { window in (window as? IslandPanel)?.setOpen(open, animated: false) })
    }
}
#endif
