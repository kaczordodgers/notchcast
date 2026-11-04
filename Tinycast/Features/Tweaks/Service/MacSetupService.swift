import Foundation
import CoreFoundation

nonisolated struct MacSetupService: Sendable {
    let store: MacSetupRollbackStore
    let write: @Sendable (TweakPreference, TweakValue) throws -> Void

    @concurrent func apply(_ plan: MacSetupPlan) async -> TweakPlanRunner.Receipt {
        store.apply(plan, read: read, write: write)
    }

    @concurrent func rollback() async throws {
        try store.rollback(read: read, write: write)
    }

    private func read(_ preference: TweakPreference) throws -> TweakValue {
        let domain = preference.domain == ".GlobalPreferences"
            ? kCFPreferencesAnyApplication : preference.domain as CFString
        let host = preference.currentHost ? kCFPreferencesCurrentHost : kCFPreferencesAnyHost
        guard CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, host) else {
            throw MacSetupPlan.Failure.missingReading
        }
        guard let value = CFPreferencesCopyValue(preference.key as CFString, domain,
                                                kCFPreferencesCurrentUser, host) else { return .absent }
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return .bool(number.boolValue) }
            guard !CFNumberIsFloatType(number) else { throw MacSetupPlan.Failure.missingReading }
            return .integer(number.intValue)
        }
        if let string = value as? String { return .string(string) }
        throw MacSetupPlan.Failure.missingReading
    }

}
