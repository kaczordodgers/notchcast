import Foundation

extension AppUpdatesModule {
    static func live() -> AppUpdatesModule {
        let transport = AppUpdateTransport()
        return AppUpdatesModule {
            let brew = await ExecutableLocator.locate("brew")
            let checker = AppUpdatesChecker(fetch: { try await transport.fetch($0) },
                                            outdated: { try await AppUpdateBrewRunner(brew: brew).outdated() })
            let casks = await AppUpdateBrewRunner(
                brew: brew, arguments: ["info", "--cask", "--json=v2", "--installed"]
            ).installedCasks { _ in
                Task { @MainActor in
                    IslandHUDRouter.post(String(localized: "Homebrew apps could not be checked.", table: "Notchcast"),
                                         tone: .danger, symbol: "shippingbox")
                }
            }
            let apps = await installedApps(casks: casks)
            return try await checker.check(apps: apps, now: Date()).results
        }
    }

    @concurrent private static func installedApps(casks: [String: String]) async -> [AppUpdate.App] {
        let roots = [URL(filePath: "/Applications"),
                     FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")]
        return roots.flatMap { root -> [AppUpdate.App] in
            let urls = (try? FileManager.default.contentsOfDirectory(
                at: root, includingPropertiesForKeys: nil)) ?? []
            return urls.compactMap { url in
                guard url.pathExtension == "app", let bundle = Bundle(url: url),
                      let id = bundle.bundleIdentifier else { return nil }
                return AppUpdate.App(
                    id: id, version: bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "",
                    build: bundle.infoDictionary?["CFBundleVersion"] as? String ?? "",
                    appStore: FileManager.default.fileExists(atPath: url.path + "/Contents/_MASReceipt/receipt"),
                    feed: (bundle.infoDictionary?["SUFeedURL"] as? String).flatMap(URL.init(string:)),
                    cask: casks[url.lastPathComponent])
            }
        }
    }
}
