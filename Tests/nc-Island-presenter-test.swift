// notchcast-linux-ok
// notchcast-sources: Tinycast/Features/Island/Model/IslandPresentation.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandPresenting.swift
import Foundation

@main
struct IslandPresenterTest {
    @MainActor static func main() {
        let island = RecordingIslandPresenter()
        let volume = IslandLevel(source: "volume", symbol: "speaker.wave.2.fill", label: "Volume", value: 0.5)
        let sync = IslandNotice(id: "sync", symbol: nil, text: "Syncing", progress: IslandProgress(fraction: 0.2))
        let timer = IslandStatus(id: "timer", symbol: "timer", text: "4:59", label: "Timer")
        let focus = [IslandMenuRow(id: "25", title: "25 minutes", isChecked: false)]
        let music = [IslandMenuRow(id: "pause", title: "Pause")]
        var taps = 0
        var selected: [String] = []

        precondition(volume.range == 0...1 && !sync.isFailure, "Defaults are the standard track and no failure")
        island.showLevel(volume)
        island.post(sync, onTap: { taps += 1 })
        island.setStatus(timer, for: timer.id, onTap: nil)
        island.setMenuRows(focus, owner: "focus") { selected.append($0) }
        island.setMenuRows(music, owner: "music") { selected.append($0) }
        precondition(island.calls == [
            .showLevel(volume), .post(sync, tappable: true), .setStatus(timer, id: "timer"),
            .setMenuRows(focus, owner: "focus"), .setMenuRows(music, owner: "music"),
        ], "Every call is recorded in order")

        island.tapNotice()
        precondition(taps == 1, "A notice's tap reaches its caller")
        var synced = sync
        synced.progress?.fraction = 0.6
        island.post(synced, onTap: nil)
        precondition(island.notice == synced && island.calls.last == .post(synced, tappable: false))

        island.select("25", owner: "focus")
        precondition(selected == ["25"], "Selecting a row reaches its owner")
        let replaced = [IslandMenuRow(id: "50", title: "50 min")]
        island.setMenuRows(replaced, owner: "focus") { selected.append("new " + $0) }
        island.select("50", owner: "focus")
        precondition(island.menuOwners == ["focus", "music"] && selected == ["25", "new 50"]
                     && island.calls.last == .setMenuRows(replaced, owner: "focus"),
                     "Same owner replaces its rows and handler in place")
        island.setMenuRows([], owner: "focus") { _ in }
        precondition(island.menuOwners == ["music"], "setMenuRows([]) removes the owner")

        island.setStatus(nil, for: timer.id, onTap: nil)
        precondition(island.statuses.isEmpty && island.calls.last == .setStatus(nil, id: "timer"),
                     "setStatus(nil) clears")
        island.end(notice: "other")
        precondition(island.notice == synced, "Ending another id leaves the notice")
        island.end(notice: "sync")
        precondition(island.notice == nil && island.calls.last == .end(notice: "sync"), "end(notice:) removes")
        precondition(island.calls.count == 11)

        var held: [IslandHeldKey] = []
        island.holdKeys(for: sync.id, onFocus: { precondition($0) }) { held.append($0) }
        island.press(.accept)
        island.press(.cancel)
        island.releaseKeys()
        island.press(.accept)
        precondition(island.calls.suffix(2) == [.holdKeys(true), .holdKeys(false)] && held == [.accept, .cancel],
                     "holdKeys is recorded, its handler hears the keys, and nil lets them go")
        precondition(IslandHeldKey(keyCode: 36) == .accept && IslandHeldKey(keyCode: 76) == .accept
                     && IslandHeldKey(keyCode: 53) == .cancel && IslandHeldKey(keyCode: 49) == nil,
                     "Return and keypad Enter accept, Escape cancels, any other key is not held")
        island.place(notice: sync.id, on: 2)
        island.post(sync, onTap: nil)
        island.place(notice: sync.id, on: 3)
        precondition(island.calls.suffix(3) == [
            .place(notice: sync.id, on: 2), .post(sync, tappable: false), .place(notice: sync.id, on: 3),
        ], "Placement works before the notice is posted and can change afterward")
        island.end(notice: sync.id)
        island.post(sync, onTap: nil)
        precondition(island.displays[sync.id] == nil, "Ending a notice clears its placement")
        let silent: any IslandPresenting = SilentIslandPresenter()
        silent.holdKeys(for: sync.id, onFocus: { precondition(!$0) }) { _ in }
        silent.releaseKeys()
        print("Island presenter: the fake records calls in order and clears status, menu rows, notices and held keys")
    }
}

/// Records every presenter call in order and keeps the state a caller can observe.
@MainActor
final class RecordingIslandPresenter: IslandPresenting {
    enum Call: Equatable {
        case showLevel(IslandLevel)
        case post(IslandNotice, tappable: Bool)
        case place(notice: String, on: UInt32?)
        case end(notice: String)
        case setStatus(IslandStatus?, id: String)
        case setMenuRows([IslandMenuRow], owner: String)
        case holdKeys(Bool)
    }

    private(set) var calls: [Call] = []
    private(set) var notice: IslandNotice?
    private(set) var displays: [String: UInt32] = [:]
    private(set) var statuses: [String: IslandStatus] = [:]
    private var onTap: (@MainActor () -> Void)?
    private var onKey: (@MainActor (IslandHeldKey) -> Void)?
    private var menus: [(owner: String, onSelect: @MainActor (String) -> Void)] = []
    var menuOwners: [String] { menus.map(\.owner) }

    func showLevel(_ level: IslandLevel) { calls.append(.showLevel(level)) }

    func post(_ notice: IslandNotice, onTap: (@MainActor () -> Void)?) {
        calls.append(.post(notice, tappable: onTap != nil))
        self.notice = notice
        self.onTap = onTap
    }

    func place(notice id: String, on display: UInt32?) {
        calls.append(.place(notice: id, on: display))
        displays[id] = display
    }

    func end(notice id: String) {
        calls.append(.end(notice: id))
        displays[id] = nil
        if notice?.id == id { notice = nil; onTap = nil }
    }

    func setStatus(_ status: IslandStatus?, for id: String, onTap: (@MainActor () -> Void)?) {
        calls.append(.setStatus(status, id: id))
        statuses[id] = status
    }

    func setMenuRows(_ rows: [IslandMenuRow], owner: String, onSelect: @escaping @MainActor (String) -> Void) {
        calls.append(.setMenuRows(rows, owner: owner))
        let index = menus.firstIndex { $0.owner == owner }
        if rows.isEmpty {
            if let index { menus.remove(at: index) }
        } else if let index {
            menus[index].onSelect = onSelect
        } else {
            menus.append((owner, onSelect))
        }
    }

    func holdKeys(for notice: String, onFocus: @escaping @MainActor (Bool) -> Void,
                  onKey: @escaping @MainActor (IslandHeldKey) -> Void) {
        calls.append(.holdKeys(true))
        self.onKey = onKey
        onFocus(true)
    }

    func releaseKeys() {
        calls.append(.holdKeys(false))
        onKey = nil
    }

    func tapNotice() { onTap?() }
    func press(_ key: IslandHeldKey) { onKey?(key) }
    func select(_ rowID: String, owner: String) { menus.first { $0.owner == owner }?.onSelect(rowID) }
}

/// Implements only the required calls, so `holdKeys` falls to the protocol's empty default.
@MainActor
final class SilentIslandPresenter: IslandPresenting {
    func showLevel(_ level: IslandLevel) {}
    func post(_ notice: IslandNotice, onTap: (@MainActor () -> Void)?) {}
    func end(notice id: String) {}
    func setStatus(_ status: IslandStatus?, for id: String, onTap: (@MainActor () -> Void)?) {}
    func setMenuRows(_ rows: [IslandMenuRow], owner: String, onSelect: @escaping @MainActor (String) -> Void) {}
}
