// notchcast-sources: Tinycast/Features/CopyPath/Model/*.swift
// notchcast-sources: Tinycast/Features/CopyPath/Service/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastLink.swift
import Foundation

@main
struct CopyPathTest {
    @MainActor
    final class Reader {
        var requests: [CopyPathService.Request] = []
        var selection: [String] = []
        var folder = ["/Users/test/Documents/"]
        var browser = ["https://example.com/?utm_source=test&q=a%2Bb#section"]
        var document = ["file:///Users/test/My%20File.txt"]

        func read(_ request: CopyPathService.Request) -> [String] {
            requests.append(request)
            return switch request {
            case .finderSelection: selection
            case .finderFolder: folder
            case .browser: browser
            case .document: document
            }
        }
    }

    @MainActor
    static func main() async throws {
        let home = "/Users/test"
        let reader = Reader()
        let service = CopyPathService { await reader.read($0) }
        let finder = CopyPathTarget(processID: 1, bundleID: "com.apple.finder")
        var result = try await service.resolve(target: finder, home: home)
        precondition(result == .path("~/Documents"))
        precondition(reader.requests == [.finderSelection, .finderFolder])
        reader.requests = []
        reader.selection = ["/Users/test/a", "/Users/test2/b", "/"]
        result = try await service.resolve(target: finder, home: home)
        precondition(result == .path("~/a\n/Users/test2/b\n/"))
        precondition(reader.requests == [.finderSelection])
        let chrome = CopyPathTarget(processID: 2, bundleID: "com.google.Chrome")
        result = try await service.resolve(target: chrome, home: home)
        precondition(result == .link("https://example.com/?q=a%2Bb#section"))
        let editor = CopyPathTarget(processID: 3, bundleID: "com.apple.TextEdit")
        result = try await service.resolve(target: editor, home: home)
        precondition(result == .path("~/My File.txt"))
        result = try await service.resolve(target: nil, home: home)
        precondition(result == .nothing)
        precondition(CopyPathEngine.paths([home + "/"], home: home + "/") == .path("~"))
        precondition(CopyPathEngine.document("file://server/a", home: home) == .nothing)
        precondition(CopyPathEngine.document("untitled", home: home) == .nothing)
        precondition(NotchcastLink.clean("javascript:alert(1)") == nil)
        precondition(NotchcastLink.clean("https:///a") == nil)
        precondition(NotchcastLink.clean("https://example.com/?%75tm_source=x&FBCLID=y") == "https://example.com/")
        precondition(NotchcastLink.clean("https://example.com/?q=x&q=y#z") == "https://example.com/?q=x&q=y#z")
        precondition(CopyPathService.Failure.appleEvent(-1743) == .needsAutomation)
        precondition(CopyPathService.Failure.appleEvent(-1712) == .timedOut)
        do {
            _ = try await CopyPathService { _ in throw CopyPathService.Failure.needsAutomation }
                .resolve(target: finder, home: home)
            preconditionFailure("Permission refusal swallowed")
        } catch CopyPathService.Failure.needsAutomation {}
        let task = Task {
            try await CopyPathService { _ in
                withUnsafeCurrentTask { $0?.cancel() }
                return ["/late"]
            }.resolve(target: finder, home: home)
        }
        do {
            _ = try await task.value
            preconditionFailure("Cancelled result applied")
        } catch is CancellationError {}
        print("Verified files-copy-path: Finder selection/folder, browser tracking, document, permissions, cancellation")
    }
}
