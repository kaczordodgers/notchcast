import Foundation

struct CopyPathTarget: Equatable, Sendable {
    enum Browser: Sendable {
        case safari
        case chromium
    }

    let processID: Int32
    let bundleID: String?

    var browser: Browser? {
        switch bundleID {
        case "com.apple.Safari", "com.apple.SafariTechnologyPreview": .safari
        case "com.google.Chrome", "com.google.Chrome.canary", "com.brave.Browser",
             "com.microsoft.edgemac", "company.thebrowser.Browser", "com.vivaldi.Vivaldi",
             "com.operasoftware.Opera", "org.chromium.Chromium": .chromium
        default: nil
        }
    }
}
