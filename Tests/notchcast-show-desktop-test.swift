// notchcast-sources: Tinycast/Features/ShowDesktop/Model/*.swift
@main
struct ShowDesktopTests {
    static func main() {
        var engine = ShowDesktopEngine()
        func decide(_ down: Bool, _ code: Int64 = 160, modifiers: Bool = false,
                    repeatKey: Bool = false) -> ShowDesktopEngine.Decision {
            engine.decide(isKeyDown: down, keyCode: code, hasModifiers: modifiers, isRepeat: repeatKey)
        }
        precondition(decide(false) == .pass)
        precondition(decide(true, 42) == .pass)
        precondition(decide(true, modifiers: true) == .pass)
        precondition(decide(true, repeatKey: true) == .pass)
        precondition(decide(false) == .pass)
        for _ in 0..<2 {
            precondition(decide(true) == .toggle)
            precondition(decide(true, modifiers: true, repeatKey: true) == .swallow)
            precondition(decide(false, 42) == .pass)
            precondition(decide(false, modifiers: true) == .swallow)
            precondition(decide(false) == .pass)
        }
        print("Show desktop: all checks passed")
    }
}
