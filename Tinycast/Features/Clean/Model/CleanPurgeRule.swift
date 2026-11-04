import Foundation

// Purge rules: Copyright (c) 2026 Jithin Sabu, MIT; see notchcast/licenses/Purge-MIT.txt.
enum CleanPurgeRule: String, CaseIterable, Sendable {
    case nodeModules, pods, vendor, deps, target

    var folder: String {
        switch self {
        case .nodeModules: "node_modules"
        case .pods: "Pods"
        case .vendor: "vendor"
        case .deps: "deps"
        case .target: "target"
        }
    }

    var marker: String {
        switch self {
        case .nodeModules: "package.json"
        case .pods: "Podfile"
        case .vendor: "composer.json"
        case .deps: "mix.exs"
        case .target: "Cargo.toml"
        }
    }

    var lockfiles: [String] {
        switch self {
        case .nodeModules: ["package-lock.json", "npm-shrinkwrap.json", "yarn.lock", "pnpm-lock.yaml"]
        case .pods: ["Podfile.lock"]
        case .vendor: ["composer.lock"]
        case .deps: ["mix.lock"]
        case .target: ["Cargo.lock"]
        }
    }
}
