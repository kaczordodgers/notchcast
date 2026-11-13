// notchcast-sources: Tinycast/Features/SmallCommands/Model/NoiseControlEngine.swift
import Foundation

@main
struct NoiseTargetTests {
    static func main() {
        typealias Button = NoiseControlEngine.Button
        let both: [NoiseControlEngine.Mode] = [.off, .transparency, .adaptive, .noiseCancellation]
        func buttons(_ modes: [NoiseControlEngine.Mode], selected: NoiseControlEngine.Mode?) -> [Button] {
            modes.map { mode in Button(mode: mode, selected: selected.map { mode == $0 }) }
        }
        precondition(NoiseControlEngine.target(in: buttons(both, selected: .noiseCancellation)) == .transparency)
        precondition(NoiseControlEngine.target(in: buttons(both, selected: .transparency)) == .noiseCancellation)
        precondition(NoiseControlEngine.target(in: buttons(both, selected: .adaptive)) == .noiseCancellation)
        precondition(NoiseControlEngine.target(in: buttons(both, selected: nil)) == .noiseCancellation,
                     "No selected mode reads as Off and switches to noise cancellation")
        precondition(NoiseControlEngine.target(in: buttons([.off, .transparency], selected: .transparency)) == nil,
                     "Missing noise cancellation target is not pressed")
        precondition(NoiseControlEngine.target(in: buttons([.off, .noiseCancellation], selected: .noiseCancellation)) == nil,
                     "Missing transparency target is not pressed")
        precondition(NoiseControlEngine.target(in: buttons([.off, .adaptive], selected: .off)) == nil,
                     "Without either switchable mode there are no AirPods controls")
        precondition(NoiseControlEngine.target(in: []) == nil)
        print("PASS: noise control target covers selection and missing targets")
    }
}
