import Foundation

nonisolated struct AIOffModelService {
    enum Failure: Error { case unknownFeature, invalidSize, downloadsNotBlocked }

    func read(bytes: (String) throws -> Int64) throws -> [String: Int64] {
        var result: [String: Int64] = [:]
        for model in AIOffCatalog.assetTypes.keys.sorted() {
            let count = try bytes(model)
            guard count >= 0 else { throw Failure.invalidSize }
            result[model] = count
        }
        return result
    }

    func removalPlan(keeping: Set<String>, blockedAssets: Set<String>) throws -> [String] {
        guard keeping.isSubset(of: Set(AIOffCatalog.features.map(\.id))) else { throw Failure.unknownFeature }
        let models = AIOffCatalog.removableModels(keeping: keeping)
        guard models.allSatisfy({ model in
            AIOffCatalog.assetTypes[model].map { blockedAssets.contains($0) } ?? false
        }) else { throw Failure.downloadsNotBlocked }
        return models
    }
}
