import Foundation

extension DownloadRunContext {
    func distillSpawn(_ tool: DownloadTool, arguments: [String]) async throws -> String {
        guard let executable = tools.find(tool) else {
            throw NSError(domain: "Distill", code: 1, userInfo: [NSLocalizedDescriptionKey: tool.missingDetail])
        }
        return try await spawn(executable: executable, arguments: arguments).output
    }
}
