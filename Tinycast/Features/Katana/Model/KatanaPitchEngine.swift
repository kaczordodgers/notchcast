import Foundation

enum KatanaPitchEngine {
    struct Reading: Equatable, Sendable {
        let frequency: Double
        let clarity: Double
        var midi: Int { Int((69 + 12 * log2(frequency / 440)).rounded()) }
        var cents: Double { (69 + 12 * log2(frequency / 440) - Double(midi)) * 100 }
        var note: String { ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"][midi % 12] }
        var octave: Int { midi / 12 - 1 }
    }

    static func detect(_ samples: [Float], sampleRate: Double) -> Reading? {
        guard sampleRate.isFinite, (8_000...192_000).contains(sampleRate),
              samples.allSatisfy(\.isFinite) else { return nil }
        let window = sampleRate > 50_000 ? 8192 : 4096
        guard samples.count >= window else { return nil }
        let signal = Array(samples.suffix(window))
        let minimumLag = max(2, Int(sampleRate / 1400))
        let maximumLag = Int((sampleRate / 50).rounded(.up))
        let overlap = window - maximumLag
        guard overlap >= 2 * maximumLag else { return nil }
        var squares = [Double](repeating: 0, count: window + 1)
        for index in signal.indices { squares[index + 1] = squares[index] + Double(signal[index]) * Double(signal[index]) }
        let head = squares[overlap]
        guard head / Double(overlap) >= 0.000001 else { return nil }
        var difference = [Double](repeating: 0, count: maximumLag + 1)
        for lag in 0...maximumLag {
            var correlation = 0.0
            for index in 0..<overlap { correlation += Double(signal[index]) * Double(signal[index + lag]) }
            let energy = head + squares[lag + overlap] - squares[lag]
            difference[lag] = energy > 0 ? 2 * correlation / energy : 0
        }
        var maxima: [Int] = []
        var lag = 1
        while lag < maximumLag, difference[lag] > 0 { lag += 1 }
        var peak: Int?
        while lag < maximumLag {
            if difference[lag] > 0 {
                if peak == nil || difference[lag] > difference[peak!] { peak = lag }
            } else if let found = peak {
                maxima.append(found)
                peak = nil
            }
            lag += 1
        }
        if let peak, peak < maximumLag - 1 { maxima.append(peak) }
        let candidates = maxima.filter { $0 >= minimumLag && $0 < maximumLag }
        guard let highest = candidates.map({ difference[$0] }).max(), highest >= 0.85,
              let chosen = candidates.first(where: { difference[$0] >= 0.9 * highest }) else { return nil }
        let before = difference[chosen - 1], here = difference[chosen], after = difference[chosen + 1]
        let curve = before - 2 * here + after
        let shift = curve < 0 ? 0.5 * (before - after) / curve : 0
        let frequency = sampleRate / (Double(chosen) + shift)
        guard (50...1400).contains(frequency) else { return nil }
        return Reading(frequency: frequency, clarity: min(1, here - 0.25 * (before - after) * shift))
    }
}
