// notchcast-sources: Tinycast/Features/SpacesOrder/Model/*.swift

@main
struct SpacesOrderTests {
    static func main() {
        for original in SpacesOrderEngine.Value.allCases {
            assert(SpacesOrderEngine.target(enabled: true, original: original) == .disabled)
            assert(SpacesOrderEngine.target(enabled: false, original: original) == original)
            assert(!SpacesOrderEngine.needsWrite(current: original, target: original))
        }
        assert(SpacesOrderEngine.target(enabled: false, original: nil) == nil)
        assert(!SpacesOrderEngine.needsWrite(current: .enabled, target: nil))
        assert(SpacesOrderEngine.needsWrite(current: .enabled, target: .disabled))
        assert(SpacesOrderEngine.needsWrite(current: .disabled, target: .absent))
        print("Spaces order: all checks passed")
    }
}
