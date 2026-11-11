import Foundation

enum CleanSystemPlan {
    enum Reason: Sendable { case agedCache, rotatedLog, diagnosticReport, unifiedLog }
}
