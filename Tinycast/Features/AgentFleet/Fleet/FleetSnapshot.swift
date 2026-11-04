import Foundation

struct FleetSnapshot: Sendable {
    struct Destination: Equatable, Sendable {
        enum Route: Sendable { case local, linked }
        let machine: String
        let environmentID: String
        let workspacePath: String?
        let route: Route
    }

    enum State: Int, Codable, Sendable { case waiting, working, finished }

    struct Thread: Sendable {
        let id: String
        let title: String
        let project: String
        let engine: String
        let state: State
        let began: Date
        let ended: Date?
        let parentID: String?
        let workspacePath: String?
    }

    enum Failure: Error, Equatable { case linkExpired, unavailable }

    struct GuardReport: Decodable, Sendable {
        struct Lead: Decodable, Sendable {
            let id: String
            let children: Int?
            let venture: String?
            let weight: String
        }

        struct Use: Decodable, Sendable {
            let running: Int?
            let max: Int
        }

        let machine: String
        let running: Int?
        let max: Int
        let heavy: Use
        let light: Use
        let ventures: [String: Int]?
        let leads: [Lead]
    }

    struct Limits: Decodable, Sendable {
        let leads: [String: Int]
        let childCap: Int
        let ventureChildCaps: [String: Int]?
        let ventureCaps: [String: Int]?
    }

    let threads: [Thread]
    let report: GuardReport?
    let limits: Limits?
}
