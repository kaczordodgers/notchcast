import AppKit

@MainActor
final class TodoReminderTimer {
    private(set) var state: TodoReminderState
    private(set) var nextFireDate: Date?

    private let now: () -> Date
    private let schedule: (Date) -> TodoReminderSchedule
    private let notificationCenter: NotificationCenter
    private let workspaceNotificationCenter: NotificationCenter
    private let onStateChange: (TodoReminderState) -> Void
    private let onFire: (TodoReminderFire) -> Void
    private let makeTimer: (TimeInterval, @escaping @Sendable (Timer) -> Void) -> Timer
    private var observers: [NotificationToken] = []
    private var timer: Timer?
    private var sessionID: UUID?
    private var timerID: UUID?

    init(
        state: TodoReminderState,
        now: @escaping () -> Date = Date.init,
        notificationCenter: NotificationCenter = .default,
        workspaceNotificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        schedule: @escaping (Date) -> TodoReminderSchedule,
        makeTimer: @escaping (TimeInterval, @escaping @Sendable (Timer) -> Void) -> Timer = {
            Timer(timeInterval: $0, repeats: false, block: $1)
        },
        onStateChange: @escaping (TodoReminderState) -> Void,
        onFire: @escaping (TodoReminderFire) -> Void
    ) {
        self.state = state
        self.now = now
        self.notificationCenter = notificationCenter
        self.workspaceNotificationCenter = workspaceNotificationCenter
        self.schedule = schedule
        self.makeTimer = makeTimer
        self.onStateChange = onStateChange
        self.onFire = onFire
    }

    isolated deinit {
        timer?.invalidate()
    }

    func start() {
        guard sessionID == nil else { return }
        let session = UUID()
        sessionID = session
        observe(NSWorkspace.didWakeNotification, center: workspaceNotificationCenter, session: session)
        observe(.NSSystemClockDidChange, center: notificationCenter, session: session)
        observe(.NSSystemTimeZoneDidChange, center: notificationCenter, session: session)
        check()
    }

    func stop() {
        sessionID = nil
        observers.removeAll()
        disarm()
    }

    func rearm(_ reminderID: UUID) {
        onStateChange(state)
        check()
    }

    func check() {
        guard sessionID != nil else { return }
        disarm()
        let current = schedule(now())
        let fire = state.check(current)
        arm(current.nextFireDate(excluding: state.firedIDs), now: current.now)
        onStateChange(state)
        if !fire.isEmpty { onFire(fire) }
    }

    private func disarm() {
        timer?.invalidate()
        timer = nil
        timerID = nil
        nextFireDate = nil
    }

    private func arm(_ date: Date?, now: Date) {
        guard let date else { return }
        nextFireDate = date
        let identity = UUID()
        timerID = identity
        let timer = makeTimer(max(0, date.timeIntervalSince(now))) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.timerID == identity else { return }
                self.check()
            }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func observe(_ name: Notification.Name, center: NotificationCenter, session: UUID) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.sessionID == session else { return }
                self.check()
            }
        }
        observers.append(NotificationToken(token, center: center))
    }
}
