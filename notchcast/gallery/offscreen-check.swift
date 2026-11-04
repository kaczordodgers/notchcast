#if DEBUG
import AppKit
import Darwin

let arguments = Array(CommandLine.arguments.dropFirst().drop { $0 == "--" })
guard !arguments.isEmpty else {
    FileHandle.standardError.write(Data("usage: offscreen-check -- <command> [arguments]\n".utf8))
    exit(2)
}

var cleanup: (() -> Void)?

func fail(_ message: String) -> Never {
    cleanup?()
    FileHandle.standardError.write(Data("offscreen-check: \(message)\n".utf8))
    exit(2)
}

/// A process by pid and start time: a recycled pid has another start time.
struct Proc: Hashable {
    let pid: pid_t
    let started: Int  // microseconds
}

struct TableEntry {
    let process: Proc
    let parent: pid_t
    let session: pid_t
    let isZombie: Bool
}

/// Every process now running. A table that grows between the size query and the read is retried; no table is an error, never "no processes".
func processTable() -> [TableEntry] {
    var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
    let stride = MemoryLayout<kinfo_proc>.stride
    for _ in 0..<8 {
        var size = 0
        guard sysctl(&mib, 4, nil, &size, nil, 0) == 0 else { fail("sysctl could not size the process table (errno \(errno))") }
        var procs = [kinfo_proc](repeating: kinfo_proc(), count: size / stride + 128)
        size = procs.count * stride
        if sysctl(&mib, 4, &procs, &size, nil, 0) == 0 {
            return procs.prefix(size / stride).map { proc in
                let time = proc.kp_proc.p_starttime
                let pid = proc.kp_proc.p_pid
                return TableEntry(process: Proc(pid: pid, started: Int(time.tv_sec) * 1_000_000 + Int(time.tv_usec)),
                                  parent: proc.kp_eproc.e_ppid, session: getsid(pid), isZombie: proc.kp_proc.p_stat == 5)
            }
        }
        guard errno == ENOMEM else { fail("sysctl could not read the process table (errno \(errno))") }
    }
    fail("the process table kept growing while it was read")
}

func describe(_ app: NSRunningApplication?) -> String {
    guard let app else { return "none" }
    return "\(app.localizedName ?? "?") (\(app.bundleIdentifier ?? "no bundle id"), pid \(app.processIdentifier))"
}

var attributes: posix_spawnattr_t?
guard posix_spawnattr_init(&attributes) == 0 else { fail("posix_spawnattr_init failed") }
guard posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETSID)) == 0 else { fail("POSIX_SPAWN_SETSID could not be set: the run would not be tracked") }
let argv: [UnsafeMutablePointer<CChar>?] = (["/usr/bin/env"] + arguments).map { strdup($0) } + [nil]
let startFront = NSWorkspace.shared.frontmostApplication
let started = Date()
/// Earliest start time (microseconds, as p_starttime) of a run process, with 1 s of slack between the two clocks.
let startedMicros = Int(started.timeIntervalSince1970 * 1_000_000) - 1_000_000
/// Sessions the run never owns: none (-1, an exited process), launchd's and this check's own.
let foreignSessions: Set<pid_t> = [-1, 0, 1, getsid(0)]
/// Seconds since the command started, to match a window to the test or page that showed it.
func elapsed() -> String { String(format: "+%.1fs", Date().timeIntervalSince(started)) }
var leader: pid_t = 0
// A build-queue job identical to one already queued would join that other caller's run, which this check never tracks.
setenv("BUILD_QUEUE_DEDUPE", "0", 1)
let spawned = posix_spawn(&leader, "/usr/bin/env", nil, &attributes, argv, environ)
guard spawned == 0 else { fail("cannot start \(arguments[0]): error \(spawned)") }

/// The run's processes and the sessions they own, grown at every sample (never shrunk: an exited process just stops being in the table).
var tracked: Set<Proc> = []
var sessions: Set<pid_t> = [leader]

/// Adds what the table shows to `tracked`, and returns the run's processes that are alive now.
@discardableResult
func track() -> [Proc] {
    let table = processTable().filter { $0.process.started >= startedMicros && !foreignSessions.contains($0.session) }
    var grew = true
    while grew {
        grew = false
        let parents = Set(table.filter { tracked.contains($0.process) }.map(\.process.pid))
        for entry in table where !tracked.contains(entry.process) {
            guard sessions.contains(entry.session) || entry.process.pid == leader || parents.contains(entry.parent) else { continue }
            tracked.insert(entry.process)
            sessions.insert(entry.session)
            grew = true
        }
    }
    return table.filter { tracked.contains($0.process) && !$0.isZombie }.map(\.process)
}

func send(_ signal: Int32) { for process in track() { kill(process.pid, signal) } }

cleanup = { send(SIGKILL) }

// A stopped check (Ctrl-C, a timeout) stops everything the run started, in whatever session.
let signalSources = [SIGINT, SIGTERM, SIGHUP].map { sig in
    signal(sig, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
    source.setEventHandler { send(sig) }
    source.resume()
    return source
}

var windows: [Int: String] = [:]
var focus: [String] = []
var notes: [String] = []
var lastFront = startFront?.processIdentifier
var sawAnyWindow = false
var reportedApp = Set<pid_t>()

func owns(_ pid: pid_t) -> Bool { tracked.contains { $0.pid == pid } }

func sample() {
    track()
    guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
        fail("no WindowServer session: the window list is unavailable, so a shown window could not be seen (run it in the logged-in user's session)")
    }
    if !list.isEmpty { sawAnyWindow = true }
    for info in list {
        guard let pid = info[kCGWindowOwnerPID as String] as? pid_t, owns(pid),
              info[kCGWindowIsOnscreen as String] as? Bool == true,
              let alpha = info[kCGWindowAlpha as String] as? Double, alpha > 0,
              let boundsInfo = info[kCGWindowBounds as String] as? NSDictionary,
              let bounds = CGRect(dictionaryRepresentation: boundsInfo), bounds.width > 0, bounds.height > 0,
              let number = info[kCGWindowNumber as String] as? Int, windows[number] == nil else { continue }
        let owner = info[kCGWindowOwnerName as String] as? String ?? "?"
        let title = info[kCGWindowName as String] as? String ?? ""
        let layer = info[kCGWindowLayer as String] as? Int ?? 0
        windows[number] = "\(elapsed()) window \(number) of \(owner) (pid \(pid)) \"\(title)\" layer \(layer) alpha \(alpha) at \(bounds)"
    }
    let front = NSWorkspace.shared.frontmostApplication
    if front?.processIdentifier != lastFront {
        lastFront = front?.processIdentifier
        if let front, owns(front.processIdentifier) {
            focus.append("\(elapsed()) the command took focus: frontmost app became \(describe(front))")
        } else if let front, let launched = front.launchDate, launched > started {
            focus.append("\(elapsed()) an app started during the run took focus: frontmost app became \(describe(front)), launched \(String(format: "%.1f", launched.timeIntervalSince(started))) s after the start")
        } else {
            notes.append("\(elapsed()) frontmost app became \(describe(front)) (already running, not the command's)")
        }
    }
    for app in NSWorkspace.shared.runningApplications where app.bundleIdentifier == ProcessInfo.processInfo.environment["NOTCHCAST_GALLERY_BUNDLE_ID"] && !owns(app.processIdentifier) {
        if let launched = app.launchDate, launched > started, reportedApp.insert(app.processIdentifier).inserted {
            focus.append("\(elapsed()) a new instance of the gallery bundle started outside the run: \(describe(app)) (a relaunch through LaunchServices)")
        }
    }
}

var status: Int32 = 0
var leaderEnded: Date?
while true {
    if Date().timeIntervalSince(started) > 600 {
        send(SIGKILL)
        fail("run exceeded the 600 second limit; tracked processes stopped")
    }
    if leaderEnded == nil, waitpid(leader, &status, WNOHANG) == leader { leaderEnded = Date() }
    sample()
    if let ended = leaderEnded {
        let alive = track()
        if alive.isEmpty { break }
        if Date().timeIntervalSince(ended) > 60 {
            notes.append("\(elapsed()) processes left behind 60 s after the command exited were stopped: \(alive.map(\.pid))")
            send(SIGKILL)
            break
        }
    }
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
}
sample()

let exited = status & 0x7f == 0
let commandStatus: Int32 = exited ? (status >> 8) & 0xff : 128 + (status & 0x7f)
if windows.isEmpty, focus.isEmpty {
    guard sawAnyWindow else {
        var displayCount: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &displayCount)
        fail("no window of any app was ever listed (active displays: \(displayCount)): with no display or a display asleep a shown window cannot be seen, so this is not a PASS")
    }
    print("offscreen-check: PASS (no window of the run on screen, no focus taken by the run or by an app it started; frontmost app at start: \(describe(startFront)))")
    for line in notes { print("  note: \(line)") }
    exit(commandStatus)
}
var report = "offscreen-check: FAIL (command exit \(commandStatus))\n"
for line in windows.sorted(by: { $0.key < $1.key }).map(\.value) { report += "  \(line)\n" }
for line in focus { report += "  \(line)\n" }
for line in notes { report += "  note: \(line)\n" }
FileHandle.standardError.write(Data(report.utf8))
exit(1)

#endif

