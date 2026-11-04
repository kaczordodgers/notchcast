enum ScrollingCaptureCadence {
    static func interval(unchangedFor seconds: Double) -> Double {
        seconds >= 30 ? 1 : 0.2
    }
}
