import Foundation
import ObjectiveC
import Darwin

nonisolated struct AIOffNativeModelService {
    enum Failure: Error { case unavailable, unknownModel, assetTypeChanged, invalidPlan }

    struct Removal: Equatable, Sendable {
        let models: [String]
        let timeout: TimeInterval
        let retryDelays: [TimeInterval]

        var configuration: [String: Any] {
            ["Operation": "ResetAssetSets", "AssetSets": models]
        }
    }

    func read() throws -> [String: Int64] {
        let framework = try load()
        defer { dlclose(framework) }
        return try AIOffModelService().read { model in
            guard let asset = assetType(model), asset == AIOffCatalog.assetTypes[model] else {
                throw Failure.assetTypeChanged
            }
            guard let manager = NSClassFromString("UAFAutoAssetManager"),
                  let method = class_getClassMethod(manager, NSSelectorFromString("latestStatusForClients:error:"))
            else { throw Failure.unavailable }
            typealias Read = @convention(c) (AnyClass, Selector, NSString, UnsafeMutablePointer<NSError?>?) -> AnyObject?
            let call = unsafeBitCast(method_getImplementation(method), to: Read.self)
            var error: NSError?
            guard let status = call(manager, NSSelectorFromString("latestStatusForClients:error:"), model as NSString,
                                    &error) else { throw error ?? Failure.unavailable as any Error }
            if let error { throw error }
            let selector = NSSelectorFromString("downloadedFilesystemBytes")
            guard let method = class_getInstanceMethod(type(of: status), selector) else {
                throw Failure.unavailable
            }
            typealias Bytes = @convention(c) (AnyObject, Selector) -> Int64
            return unsafeBitCast(method_getImplementation(method), to: Bytes.self)(status, selector)
        }
    }

    func removalPlan(keeping: Set<String>, blockedAssets: Set<String>) throws -> Removal {
        let models = try AIOffModelService().removalPlan(keeping: keeping, blockedAssets: blockedAssets)
        return Removal(models: models, timeout: 120, retryDelays: [5, 15])
    }

    func remove(_ plan: Removal, runner: (Removal) throws -> Void) throws {
        guard !plan.models.isEmpty, Set(plan.models).count == plan.models.count,
              plan.models.allSatisfy({ AIOffCatalog.assetTypes[$0] != nil }),
              plan.timeout == 120, plan.retryDelays == [5, 15] else { throw Failure.invalidPlan }
        try runner(plan)
    }

    private func load() throws -> UnsafeMutableRawPointer {
        let path = "/System/Library/PrivateFrameworks/UnifiedAssetFramework.framework/UnifiedAssetFramework"
        guard let framework = dlopen(path, RTLD_NOW) else { throw Failure.unavailable }
        return framework
    }

    private func assetType(_ model: String) -> String? {
        guard let manager = NSClassFromString("UAFConfigurationManager") as? NSObject.Type,
              manager.responds(to: NSSelectorFromString("defaultManager")),
              let instance = manager.perform(NSSelectorFromString("defaultManager"))?.takeUnretainedValue()
                as? NSObject,
              instance.responds(to: NSSelectorFromString("getAssetSet:")),
              let set = instance.perform(NSSelectorFromString("getAssetSet:"), with: model)?.takeUnretainedValue()
                as? NSObject,
              set.responds(to: NSSelectorFromString("autoAssetType")) else { return nil }
        return set.perform(NSSelectorFromString("autoAssetType"))?.takeUnretainedValue() as? String
    }
}
