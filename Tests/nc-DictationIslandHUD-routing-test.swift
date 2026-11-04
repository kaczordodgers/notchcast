// notchcast-sources: Tinycast/Features/DictationIslandHUD/Model/*.swift
@main
struct DictationIslandHUDTest {
    static func main() {
        for phase in [DictationIslandHUDPolicy.Phase.listening, .transcribing] {
            for enabled in [true, false] {
                for available in [true, false] {
                    let result = DictationIslandHUDPolicy.presentation(
                        phase: phase, enabled: enabled, islandAvailable: available)
                    let expected: DictationIslandHUDPolicy.Presentation = enabled && available
                        ? (phase == .listening ? .listening : .transcribing) : .capsule
                    precondition(result == expected)
                }
            }
        }
        print("Dictation island routing: both phases and capsule fallback passed")
    }
}
