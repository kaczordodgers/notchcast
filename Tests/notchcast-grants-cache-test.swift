// notchcast-sources: -parse-as-library
// notchcast-reads: Tinycast/Features/Notchcast/Settings/Tree/NotchcastGrantsSection.swift
// notchcast-reads: Tinycast/Features/Notchcast/Settings/NotchcastGrant+Settings.swift
import Foundation

@main
enum GrantsCacheTest {
    static func main() throws {
        let section = try String(contentsOfFile: ProcessInfo.processInfo.environment["GRANTS_SECTION"] ??
            "Tinycast/Features/Notchcast/Settings/Tree/NotchcastGrantsSection.swift", encoding: .utf8)
        guard !section.contains("grant.isGranted"), section.contains("grantStatuses.values[grant]") else {
            print("FAIL: grant rows synchronously query authorization instead of cached state")
            exit(1)
        }
        let reader = try String(contentsOfFile:
            "Tinycast/Features/Notchcast/Settings/NotchcastGrant+Settings.swift", encoding: .utf8)
        guard reader.contains("@concurrent"), reader.contains("func readIsGranted() async -> Bool") else {
            print("FAIL: authorization reader must leave the main actor")
            exit(1)
        }
        print("PASS: rows render cached values; authorization reads use @concurrent")
    }
}
