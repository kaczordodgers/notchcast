import CoreGraphics

enum ScreenRecordingAccess {
    static func isGranted() -> Bool { CGPreflightScreenCaptureAccess() }

    static func request() -> Bool { CGRequestScreenCaptureAccess() }

    static func isGrantedOrRequest() -> Bool { isGranted() || request() }
}
