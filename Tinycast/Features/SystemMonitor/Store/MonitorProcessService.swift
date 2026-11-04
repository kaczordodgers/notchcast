import AppKit
import Darwin

@MainActor
struct MonitorProcessService {
    enum Outcome: Equatable {
        case requested
        case protectedProcess
        case staleIdentity
        case unavailable
        case rejected
    }

    struct Application {
        let quit: () -> Bool
        let forceQuit: () -> Bool
    }

    var uid: UInt32 = getuid()
    var ownPID: Int32 = getpid()
    var lookup: (Int32) -> KillProcessEntry? = { KillProcessService().read(pid: $0) }
    var application: (Int32) -> Application? = { pid in
        guard let app = NSRunningApplication(processIdentifier: pid) else { return nil }
        return Application(quit: { app.terminate() }, forceQuit: { app.forceTerminate() })
    }

    func quit(_ identity: ProcessReading.Identity, force: Bool) -> Outcome {
        guard identity.pid > 1, identity.pid != ownPID else { return .protectedProcess }
        guard let target = lookup(identity.pid) else { return .unavailable }
        guard target.canStop(uid: uid, ownPID: ownPID) else { return .protectedProcess }
        guard target.startSeconds == identity.startSeconds,
              target.startMicroseconds == identity.startMicroseconds else { return .staleIdentity }
        guard let app = application(identity.pid) else { return .unavailable }
        do {
            try KillProcessService().apply(targets: [target], signal: force ? .force : .terminate,
                                           uid: uid, ownPID: ownPID, lookup: lookup) { _, signal in
                guard signal == .force ? app.forceQuit() : app.quit() else { throw Rejected() }
            }
            return .requested
        } catch KillProcessService.Failure.protectedProcess {
            return .protectedProcess
        } catch KillProcessService.Failure.staleIdentity {
            return .staleIdentity
        } catch {
            return .rejected
        }
    }

    private struct Rejected: Error {}
}
