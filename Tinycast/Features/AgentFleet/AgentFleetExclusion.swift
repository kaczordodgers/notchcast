enum AgentFleetExclusion {
    static let folderName = "agent-2784f2ac"

    static func containsFolder(in path: String) -> Bool {
        path.split(separator: "/").contains(Substring(folderName))
    }
}
