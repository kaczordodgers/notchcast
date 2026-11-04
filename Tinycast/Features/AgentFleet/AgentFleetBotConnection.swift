import Foundation

extension NotchcastCore {
    static func configureBotHost() {
        let tokenAccount = fleetSettings.tokenAccount
        botHost.configure(client: OpenBotBridge(transport: BotHostTransport(connection: {
            let defaults = UserDefaults(
                suiteName: (Bundle.main.bundleIdentifier ?? "app.notchcast.dev") + ".notchcast.fleet")!
            guard let url = defaults.string(forKey: "botHostURL").flatMap(URL.init(string:)),
                  let token = try KeychainSecretStore(scope: "bot-host").secret(for: tokenAccount)
            else { throw BotHostTransport.Failure.invalidConnection }
            return .init(url: url, token: token)
        })))
    }
}
