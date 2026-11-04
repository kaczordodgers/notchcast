import Foundation

enum KatanaPresetImporter {
    private struct Field {
        let offset: Int
        let minimum: Int
        let maximum: Int
        let bias: Int
        let width: Int
    }

    static func read(_ data: Data) throws -> KatanaTone {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let name = object["name"] as? String, !name.isEmpty,
              let raw = object["raw"] as? [String: [String]], !raw.isEmpty else { throw KatanaError.invalidData }
        if let steps = object["extra_steps"] {
            guard let steps = steps as? [String: String], steps.isEmpty else { throw KatanaError.unsupportedFormat }
        }
        var image: [UInt8: [UInt8]] = [:]
        for (key, values) in raw {
            guard key.count == 2, let region = UInt8(key, radix: 16) else { throw KatanaError.invalidData }
            guard let known = KatanaPatchRegion.all.first(where: { $0.region == region }) else {
                guard region >= 0x68, region <= 0x7E, region.isMultiple(of: 2) else { throw KatanaError.invalidData }
                continue
            }
            let bytes = try hex(values)
            guard bytes.count >= known.length else { throw KatanaError.invalidData }
            image[region] = Array(bytes.prefix(known.length))
        }
        let nameBytes = name.prefix(16).utf8.map { (0x20...0x7E).contains($0) ? $0 : 0x20 }
        image[0] = Array(nameBytes.prefix(16)) + Array(repeating: 0x20, count: max(0, 16 - nameBytes.count))
        if let value = object["set"] {
            guard let sections = value as? [String: [String: Any]] else { throw KatanaError.invalidData }
            for (section, values) in sections { try apply(section, values, image: &image) }
        }
        return try KatanaTone(regions: image.map { .init(region: $0.key, bytes: $0.value) },
                              knob: hex(object["knob"] as? [String] ?? ["00", "00", "00", "00", "00"]),
                              knobSolo: hex(object["knob_solo"] as? [String] ?? ["00"]),
                              comment: object["comment"] as? String ?? "")
    }

    private static let colors = ["green": 0, "red": 1, "yellow": 2]
    private static let ampTypes: [String: Int] = [
        "acoustic": 0, "clean": 1, "pushed": 2, "crunch": 3,
        "lead": 4, "brown": 5,
    ]
    private static let boosterTypes: [String: Int] = [
        "mid-boost": 0, "clean-boost": 1, "treble-boost": 2, "crunch-od": 3,
        "natural-od": 4, "warm-od": 5, "fat-ds": 6, "metal-ds": 7,
        "oct-fuzz": 8, "blues-drive": 9, "overdrive": 10, "t-scream": 11,
        "turbo-od": 12, "distortion": 13, "rat": 14, "guv-ds": 15,
        "dst+": 16, "metal-zone": 17, "60s-fuzz": 18, "muff-fuzz": 19,
        "hm-2": 20, "metal-core": 21, "centa-od": 22,
    ]
    private static let delayTypes: [String: Int] = [
        "digital": 0, "pan": 1, "stereo": 2, "analog": 3,
        "tape": 4, "reverse": 5, "modulate": 6, "sde-3000": 7,
    ]
    private static let reverbTypes: [String: Int] = [
        "plate": 0, "room": 1, "hall": 2, "spring": 3,
        "modulate": 4,
    ]
    private static let effectTypes: [String: Int] = [
        "t-wah": 0, "auto-wah": 1, "pedal-wah": 2, "comp": 3,
        "limiter": 4, "graphic-eq": 5, "param-eq": 6, "guitar-sim": 7,
        "slow-gear": 8, "wave-synth": 9, "octave": 10, "pitch-shifter": 11,
        "harmonist": 12, "ac-processor": 13, "phaser": 14, "flanger": 15,
        "tremolo": 16, "rotary": 17, "uni-v": 18, "slicer": 19,
        "vibrato": 20, "ring-mod": 21, "humanizer": 22, "chorus": 23,
        "ac-guitar-sim": 24, "phaser-90e": 25, "flanger-117e": 26, "wah-95e": 27,
        "dc-30": 28, "heavy-octave": 29, "pedal-bend": 30,
    ]
    private static let ampFields: [String: Int] = [
        "gain": 0, "volume": 1, "bass": 2, "mid": 3, "treble": 4,
        "presence": 5, "bloom": 6, "poweramp_variation": 6, "type": 7, "resonance": 8,
        "variation": 9,
    ]
    private static let boosterFields: [String: Int] = [
        "type": 0, "drive": 1, "bottom": 2, "tone": 3, "solo": 4,
        "solo_level": 5, "level": 6, "direct": 7,
    ]
    private static let delayFields: [String: Int] = [
        "type": 0, "feedback": 5, "highcut": 6, "level": 7, "direct": 8,
        "tap": 9, "mod_rate": 10, "mod_depth": 11, "lpf": 12, "filter": 13,
        "feedback_phase": 14, "delay_phase": 15, "mod_sw": 16,
    ]
    private static let reverbFields: [String: Int] = [
        "type": 0, "layer": 1, "time": 2, "lowcut": 7, "highcut": 8,
        "density": 9, "level": 10, "direct": 11, "spring_color": 12,
    ]
    private static let noiseFields: [String: Int] = [
        "sw": 0, "threshold": 1, "release": 2,
    ]
    private static let soloFields: [String: Int] = [
        "sw": 0, "level": 1,
    ]
    private static let otherFields: [String: Int] = [
        "chain": 0, "cab": 1, "cab_resonance": 1, "key": 2,
    ]
    private static let effectFields: [String: Field] = [
        "twah_mode": Field(offset: 0, minimum: 0, maximum: 1, bias: 0, width: 1),
        "twah_polarity": Field(offset: 1, minimum: 0, maximum: 1, bias: 0, width: 1),
        "twah_sens": Field(offset: 2, minimum: 0, maximum: 100, bias: 0, width: 1),
        "twah_freq": Field(offset: 3, minimum: 0, maximum: 100, bias: 0, width: 1),
        "twah_peak": Field(offset: 4, minimum: 0, maximum: 100, bias: 0, width: 1),
        "twah_direct_mix": Field(offset: 5, minimum: 0, maximum: 100, bias: 0, width: 1),
        "twah_effect_level": Field(offset: 6, minimum: 0, maximum: 100, bias: 0, width: 1),
        "awah_mode": Field(offset: 7, minimum: 0, maximum: 1, bias: 0, width: 1),
        "awah_freq": Field(offset: 8, minimum: 0, maximum: 100, bias: 0, width: 1),
        "awah_peak": Field(offset: 9, minimum: 0, maximum: 100, bias: 0, width: 1),
        "awah_rate": Field(offset: 10, minimum: 0, maximum: 100, bias: 0, width: 1),
        "awah_depth": Field(offset: 11, minimum: 0, maximum: 100, bias: 0, width: 1),
        "awah_direct_mix": Field(offset: 12, minimum: 0, maximum: 100, bias: 0, width: 1),
        "awah_effect_level": Field(offset: 13, minimum: 0, maximum: 100, bias: 0, width: 1),
        "pedalwah_wah_type": Field(offset: 14, minimum: 0, maximum: 5, bias: 0, width: 1),
        "pedalwah_pedal_position": Field(offset: 15, minimum: 0, maximum: 100, bias: 0, width: 1),
        "pedalwah_pedal_min": Field(offset: 16, minimum: 0, maximum: 100, bias: 0, width: 1),
        "pedalwah_pedal_max": Field(offset: 17, minimum: 0, maximum: 100, bias: 0, width: 1),
        "pedalwah_effect_level": Field(offset: 18, minimum: 0, maximum: 100, bias: 0, width: 1),
        "pedalwah_direct_mix": Field(offset: 19, minimum: 0, maximum: 100, bias: 0, width: 1),
        "comp_type": Field(offset: 20, minimum: 0, maximum: 6, bias: 0, width: 1),
        "comp_sustain": Field(offset: 21, minimum: 0, maximum: 100, bias: 0, width: 1),
        "comp_attack": Field(offset: 22, minimum: 0, maximum: 100, bias: 0, width: 1),
        "comp_tone": Field(offset: 23, minimum: -50, maximum: 50, bias: 50, width: 1),
        "comp_level": Field(offset: 24, minimum: 0, maximum: 100, bias: 0, width: 1),
        "limiter_type": Field(offset: 25, minimum: 0, maximum: 2, bias: 0, width: 1),
        "limiter_attack": Field(offset: 26, minimum: 0, maximum: 100, bias: 0, width: 1),
        "limiter_threshold": Field(offset: 27, minimum: 0, maximum: 100, bias: 0, width: 1),
        "limiter_ratio": Field(offset: 28, minimum: 0, maximum: 17, bias: 0, width: 1),
        "limiter_release": Field(offset: 29, minimum: 0, maximum: 100, bias: 0, width: 1),
        "limiter_level": Field(offset: 30, minimum: 0, maximum: 100, bias: 0, width: 1),
        "geq_31hz": Field(offset: 31, minimum: -20, maximum: 20, bias: 20, width: 1),
        "geq_62hz": Field(offset: 32, minimum: -20, maximum: 20, bias: 20, width: 1),
        "geq_125hz": Field(offset: 33, minimum: -20, maximum: 20, bias: 20, width: 1),
        "geq_250hz": Field(offset: 34, minimum: -20, maximum: 20, bias: 20, width: 1),
        "geq_500hz": Field(offset: 35, minimum: -20, maximum: 20, bias: 20, width: 1),
        "geq_1khz": Field(offset: 36, minimum: -20, maximum: 20, bias: 20, width: 1),
        "geq_2khz": Field(offset: 37, minimum: -20, maximum: 20, bias: 20, width: 1),
        "geq_4khz": Field(offset: 38, minimum: -20, maximum: 20, bias: 20, width: 1),
        "geq_8khz": Field(offset: 39, minimum: -20, maximum: 20, bias: 20, width: 1),
        "geq_16khz": Field(offset: 40, minimum: -20, maximum: 20, bias: 20, width: 1),
        "geq_level": Field(offset: 41, minimum: -20, maximum: 20, bias: 20, width: 1),
        "peq_low_cut": Field(offset: 42, minimum: 0, maximum: 17, bias: 0, width: 1),
        "peq_low_gain": Field(offset: 43, minimum: -20, maximum: 20, bias: 20, width: 1),
        "peq_lowmid_freq": Field(offset: 44, minimum: 0, maximum: 27, bias: 0, width: 1),
        "peq_lowmid_q": Field(offset: 45, minimum: 0, maximum: 5, bias: 0, width: 1),
        "peq_lowmid_gain": Field(offset: 46, minimum: -20, maximum: 20, bias: 20, width: 1),
        "peq_highmid_freq": Field(offset: 47, minimum: 0, maximum: 27, bias: 0, width: 1),
        "peq_highmid_q": Field(offset: 48, minimum: 0, maximum: 5, bias: 0, width: 1),
        "peq_highmid_gain": Field(offset: 49, minimum: -20, maximum: 20, bias: 20, width: 1),
        "peq_high_gain": Field(offset: 50, minimum: -20, maximum: 20, bias: 20, width: 1),
        "peq_high_cut": Field(offset: 51, minimum: 0, maximum: 14, bias: 0, width: 1),
        "peq_level": Field(offset: 52, minimum: -20, maximum: 20, bias: 20, width: 1),
        "guitarsim_type": Field(offset: 53, minimum: 0, maximum: 7, bias: 0, width: 1),
        "guitarsim_low": Field(offset: 54, minimum: -50, maximum: 50, bias: 50, width: 1),
        "guitarsim_high": Field(offset: 55, minimum: -50, maximum: 50, bias: 50, width: 1),
        "guitarsim_level": Field(offset: 56, minimum: 0, maximum: 100, bias: 0, width: 1),
        "guitarsim_body": Field(offset: 57, minimum: 0, maximum: 100, bias: 0, width: 1),
        "slowgear_sens": Field(offset: 58, minimum: 0, maximum: 100, bias: 0, width: 1),
        "slowgear_rise_time": Field(offset: 59, minimum: 0, maximum: 100, bias: 0, width: 1),
        "slowgear_level": Field(offset: 60, minimum: 0, maximum: 100, bias: 0, width: 1),
        "wavesynth_wave": Field(offset: 61, minimum: 0, maximum: 1, bias: 0, width: 1),
        "wavesynth_cutoff": Field(offset: 62, minimum: 0, maximum: 100, bias: 0, width: 1),
        "wavesynth_resonance": Field(offset: 63, minimum: 0, maximum: 100, bias: 0, width: 1),
        "wavesynth_filter_sens": Field(offset: 64, minimum: 0, maximum: 100, bias: 0, width: 1),
        "wavesynth_filter_decay": Field(offset: 65, minimum: 0, maximum: 100, bias: 0, width: 1),
        "wavesynth_filter_depth": Field(offset: 66, minimum: 0, maximum: 100, bias: 0, width: 1),
        "wavesynth_synth_level": Field(offset: 67, minimum: 0, maximum: 100, bias: 0, width: 1),
        "wavesynth_direct_mix": Field(offset: 68, minimum: 0, maximum: 100, bias: 0, width: 1),
        "octave_range": Field(offset: 69, minimum: 0, maximum: 3, bias: 0, width: 1),
        "octave_effect_level": Field(offset: 70, minimum: 0, maximum: 100, bias: 0, width: 1),
        "octave_direct_mix": Field(offset: 71, minimum: 0, maximum: 100, bias: 0, width: 1),
        "pitchshift_voice": Field(offset: 72, minimum: 0, maximum: 1, bias: 0, width: 1),
        "pitchshift_mode1": Field(offset: 73, minimum: 0, maximum: 3, bias: 0, width: 1),
        "pitchshift_pitch1": Field(offset: 74, minimum: -24, maximum: 24, bias: 24, width: 1),
        "pitchshift_fine1": Field(offset: 75, minimum: -50, maximum: 50, bias: 50, width: 1),
        "pitchshift_pre_delay1": Field(offset: 76, minimum: 0, maximum: 300, bias: 0, width: 4),
        "pitchshift_level1": Field(offset: 80, minimum: 0, maximum: 100, bias: 0, width: 1),
        "pitchshift_mode2": Field(offset: 81, minimum: 0, maximum: 3, bias: 0, width: 1),
        "pitchshift_pitch2": Field(offset: 82, minimum: -24, maximum: 24, bias: 24, width: 1),
        "pitchshift_fine2": Field(offset: 83, minimum: -50, maximum: 50, bias: 50, width: 1),
        "pitchshift_pre_delay2": Field(offset: 84, minimum: 0, maximum: 300, bias: 0, width: 4),
        "pitchshift_level2": Field(offset: 88, minimum: 0, maximum: 100, bias: 0, width: 1),
        "pitchshift_feedback1": Field(offset: 89, minimum: 0, maximum: 100, bias: 0, width: 1),
        "pitchshift_direct_mix": Field(offset: 90, minimum: 0, maximum: 100, bias: 0, width: 1),
        "harmonist_voice": Field(offset: 91, minimum: 0, maximum: 1, bias: 0, width: 1),
        "harmonist_harmony1": Field(offset: 92, minimum: 0, maximum: 29, bias: 0, width: 1),
        "harmonist_pre_delay1": Field(offset: 93, minimum: 0, maximum: 300, bias: 0, width: 4),
        "harmonist_level1": Field(offset: 97, minimum: 0, maximum: 100, bias: 0, width: 1),
        "harmonist_harmony2": Field(offset: 98, minimum: 0, maximum: 29, bias: 0, width: 1),
        "harmonist_pre_delay2": Field(offset: 99, minimum: 0, maximum: 300, bias: 0, width: 4),
        "harmonist_level2": Field(offset: 103, minimum: 0, maximum: 100, bias: 0, width: 1),
        "harmonist_feedback1": Field(offset: 104, minimum: 0, maximum: 100, bias: 0, width: 1),
        "harmonist_direct_mix": Field(offset: 105, minimum: 0, maximum: 100, bias: 0, width: 1),
        "harmonist_c1": Field(offset: 106, minimum: -24, maximum: 24, bias: 24, width: 1),
        "harmonist_db1": Field(offset: 107, minimum: -24, maximum: 24, bias: 24, width: 1),
        "harmonist_d1": Field(offset: 108, minimum: -24, maximum: 24, bias: 24, width: 1),
        "harmonist_eb1": Field(offset: 109, minimum: -24, maximum: 24, bias: 24, width: 1),
        "harmonist_e1": Field(offset: 110, minimum: -24, maximum: 24, bias: 24, width: 1),
        "harmonist_f1": Field(offset: 111, minimum: -24, maximum: 24, bias: 24, width: 1),
        "harmonist_fs1": Field(offset: 112, minimum: -24, maximum: 24, bias: 24, width: 1),
        "harmonist_g1": Field(offset: 113, minimum: -24, maximum: 24, bias: 24, width: 1),
        "harmonist_ab1": Field(offset: 114, minimum: -24, maximum: 24, bias: 24, width: 1),
        "harmonist_a1": Field(offset: 115, minimum: -24, maximum: 24, bias: 24, width: 1),
        "harmonist_bb1": Field(offset: 116, minimum: -24, maximum: 24, bias: 24, width: 1),
        "harmonist_b1": Field(offset: 117, minimum: -24, maximum: 24, bias: 24, width: 1),
        "harmonist_c2": Field(offset: 118, minimum: -24, maximum: 24, bias: 24, width: 1),
        "harmonist_db2": Field(offset: 119, minimum: -24, maximum: 24, bias: 24, width: 1),
        "harmonist_d2": Field(offset: 120, minimum: -24, maximum: 24, bias: 24, width: 1),
        "harmonist_eb2": Field(offset: 121, minimum: -24, maximum: 24, bias: 24, width: 1),
        "harmonist_e2": Field(offset: 122, minimum: -24, maximum: 24, bias: 24, width: 1),
        "harmonist_f2": Field(offset: 123, minimum: -24, maximum: 24, bias: 24, width: 1),
        "harmonist_fs2": Field(offset: 124, minimum: -24, maximum: 24, bias: 24, width: 1),
        "harmonist_g2": Field(offset: 125, minimum: -24, maximum: 24, bias: 24, width: 1),
        "harmonist_ab2": Field(offset: 126, minimum: -24, maximum: 24, bias: 24, width: 1),
        "harmonist_a2": Field(offset: 127, minimum: -24, maximum: 24, bias: 24, width: 1),
        "harmonist_bb2": Field(offset: 128, minimum: -24, maximum: 24, bias: 24, width: 1),
        "harmonist_b2": Field(offset: 129, minimum: -24, maximum: 24, bias: 24, width: 1),
        "acprocess_type": Field(offset: 130, minimum: 0, maximum: 3, bias: 0, width: 1),
        "acprocess_bass": Field(offset: 131, minimum: -50, maximum: 50, bias: 50, width: 1),
        "acprocess_middle": Field(offset: 132, minimum: -50, maximum: 50, bias: 50, width: 1),
        "acprocess_middle_freq": Field(offset: 133, minimum: 0, maximum: 27, bias: 0, width: 1),
        "acprocess_treble": Field(offset: 134, minimum: -50, maximum: 50, bias: 50, width: 1),
        "acprocess_presence": Field(offset: 135, minimum: -50, maximum: 50, bias: 50, width: 1),
        "acprocess_level": Field(offset: 136, minimum: 0, maximum: 100, bias: 0, width: 1),
        "phaser_type": Field(offset: 137, minimum: 0, maximum: 3, bias: 0, width: 1),
        "phaser_rate": Field(offset: 138, minimum: 0, maximum: 100, bias: 0, width: 1),
        "phaser_depth": Field(offset: 139, minimum: 0, maximum: 100, bias: 0, width: 1),
        "phaser_manual": Field(offset: 140, minimum: 0, maximum: 100, bias: 0, width: 1),
        "phaser_resonance": Field(offset: 141, minimum: 0, maximum: 100, bias: 0, width: 1),
        "phaser_step_rate": Field(offset: 142, minimum: -1, maximum: 100, bias: 1, width: 1),
        "phaser_effect_level": Field(offset: 143, minimum: 0, maximum: 100, bias: 0, width: 1),
        "phaser_direct_mix": Field(offset: 144, minimum: 0, maximum: 100, bias: 0, width: 1),
        "flanger_rate": Field(offset: 145, minimum: 0, maximum: 100, bias: 0, width: 1),
        "flanger_depth": Field(offset: 146, minimum: 0, maximum: 100, bias: 0, width: 1),
        "flanger_manual": Field(offset: 147, minimum: 0, maximum: 100, bias: 0, width: 1),
        "flanger_resonance": Field(offset: 148, minimum: 0, maximum: 100, bias: 0, width: 1),
        "flanger_low_cut": Field(offset: 149, minimum: 0, maximum: 10, bias: 0, width: 1),
        "flanger_effect_level": Field(offset: 150, minimum: 0, maximum: 100, bias: 0, width: 1),
        "flanger_direct_mix": Field(offset: 151, minimum: 0, maximum: 100, bias: 0, width: 1),
        "tremolo_wave_shape": Field(offset: 152, minimum: 0, maximum: 100, bias: 0, width: 1),
        "tremolo_rate": Field(offset: 153, minimum: 0, maximum: 100, bias: 0, width: 1),
        "tremolo_depth": Field(offset: 154, minimum: 0, maximum: 100, bias: 0, width: 1),
        "tremolo_level": Field(offset: 155, minimum: 0, maximum: 100, bias: 0, width: 1),
        "rotary_rate": Field(offset: 156, minimum: 0, maximum: 100, bias: 0, width: 1),
        "rotary_depth": Field(offset: 157, minimum: 0, maximum: 100, bias: 0, width: 1),
        "rotary_level": Field(offset: 158, minimum: 0, maximum: 100, bias: 0, width: 1),
        "univ_rate": Field(offset: 159, minimum: 0, maximum: 100, bias: 0, width: 1),
        "univ_depth": Field(offset: 160, minimum: 0, maximum: 100, bias: 0, width: 1),
        "univ_level": Field(offset: 161, minimum: 0, maximum: 100, bias: 0, width: 1),
        "slicer_pattern": Field(offset: 162, minimum: 0, maximum: 19, bias: 0, width: 1),
        "slicer_rate": Field(offset: 163, minimum: 0, maximum: 100, bias: 0, width: 1),
        "slicer_trigger_sens": Field(offset: 164, minimum: 0, maximum: 100, bias: 0, width: 1),
        "slicer_effect_level": Field(offset: 165, minimum: 0, maximum: 100, bias: 0, width: 1),
        "slicer_direct_mix": Field(offset: 166, minimum: 0, maximum: 100, bias: 0, width: 1),
        "vibrato_rate": Field(offset: 167, minimum: 0, maximum: 100, bias: 0, width: 1),
        "vibrato_depth": Field(offset: 168, minimum: 0, maximum: 100, bias: 0, width: 1),
        "vibrato_level": Field(offset: 169, minimum: 0, maximum: 100, bias: 0, width: 1),
        "ringmod_mode": Field(offset: 170, minimum: 0, maximum: 1, bias: 0, width: 1),
        "ringmod_frequency": Field(offset: 171, minimum: 0, maximum: 100, bias: 0, width: 1),
        "ringmod_effect_level": Field(offset: 172, minimum: 0, maximum: 100, bias: 0, width: 1),
        "ringmod_direct_mix": Field(offset: 173, minimum: 0, maximum: 100, bias: 0, width: 1),
        "humanizer_mode": Field(offset: 174, minimum: 0, maximum: 1, bias: 0, width: 1),
        "humanizer_vowel1": Field(offset: 175, minimum: 0, maximum: 4, bias: 0, width: 1),
        "humanizer_vowel2": Field(offset: 176, minimum: 0, maximum: 4, bias: 0, width: 1),
        "humanizer_sens": Field(offset: 177, minimum: 0, maximum: 100, bias: 0, width: 1),
        "humanizer_rate": Field(offset: 178, minimum: 0, maximum: 100, bias: 0, width: 1),
        "humanizer_depth": Field(offset: 179, minimum: 0, maximum: 100, bias: 0, width: 1),
        "humanizer_manual": Field(offset: 180, minimum: 0, maximum: 100, bias: 0, width: 1),
        "humanizer_level": Field(offset: 181, minimum: 0, maximum: 100, bias: 0, width: 1),
        "2x2chorus_xover_frequency": Field(offset: 182, minimum: 0, maximum: 16, bias: 0, width: 1),
        "2x2chorus_low_rate": Field(offset: 183, minimum: 0, maximum: 100, bias: 0, width: 1),
        "2x2chorus_low_depth": Field(offset: 184, minimum: 0, maximum: 100, bias: 0, width: 1),
        "2x2chorus_low_pre_delay": Field(offset: 185, minimum: 0, maximum: 80, bias: 0, width: 1),
        "2x2chorus_low_level": Field(offset: 186, minimum: 0, maximum: 100, bias: 0, width: 1),
        "2x2chorus_high_rate": Field(offset: 187, minimum: 0, maximum: 100, bias: 0, width: 1),
        "2x2chorus_high_depth": Field(offset: 188, minimum: 0, maximum: 100, bias: 0, width: 1),
        "2x2chorus_high_pre_delay": Field(offset: 189, minimum: 0, maximum: 80, bias: 0, width: 1),
        "2x2chorus_high_level": Field(offset: 190, minimum: 0, maximum: 100, bias: 0, width: 1),
        "2x2chorus_direct_mix": Field(offset: 191, minimum: 0, maximum: 100, bias: 0, width: 1),
        "acsim_high": Field(offset: 192, minimum: -50, maximum: 50, bias: 50, width: 1),
        "acsim_body": Field(offset: 193, minimum: 0, maximum: 100, bias: 0, width: 1),
        "acsim_low": Field(offset: 194, minimum: -50, maximum: 50, bias: 50, width: 1),
        "acsim_level": Field(offset: 195, minimum: 0, maximum: 100, bias: 0, width: 1),
        "ephaser_script": Field(offset: 196, minimum: 0, maximum: 1, bias: 0, width: 1),
        "ephaser_speed": Field(offset: 197, minimum: 0, maximum: 100, bias: 0, width: 1),
        "eflanger_manual": Field(offset: 198, minimum: 0, maximum: 100, bias: 0, width: 1),
        "eflanger_width": Field(offset: 199, minimum: 0, maximum: 100, bias: 0, width: 1),
        "eflanger_speed": Field(offset: 200, minimum: 0, maximum: 100, bias: 0, width: 1),
        "eflanger_regen": Field(offset: 201, minimum: 0, maximum: 100, bias: 0, width: 1),
        "ewah_pedal_pos": Field(offset: 202, minimum: 0, maximum: 100, bias: 0, width: 1),
        "ewah_pedal_min": Field(offset: 203, minimum: 0, maximum: 100, bias: 0, width: 1),
        "ewah_pedal_max": Field(offset: 204, minimum: 0, maximum: 100, bias: 0, width: 1),
        "ewah_effect_level": Field(offset: 205, minimum: 0, maximum: 100, bias: 0, width: 1),
        "ewah_direct_mix": Field(offset: 206, minimum: 0, maximum: 100, bias: 0, width: 1),
        "dc30_select": Field(offset: 207, minimum: 0, maximum: 1, bias: 0, width: 1),
        "dc30_input_volume": Field(offset: 208, minimum: 0, maximum: 100, bias: 0, width: 1),
        "dc30_chorus_intensity": Field(offset: 209, minimum: 0, maximum: 100, bias: 0, width: 1),
        "dc30_echo_repeat_rate": Field(offset: 210, minimum: 40, maximum: 600, bias: 0, width: 4),
        "dc30_echo_intensisty": Field(offset: 214, minimum: 0, maximum: 100, bias: 0, width: 1),
        "dc30_echo_volume": Field(offset: 215, minimum: 0, maximum: 100, bias: 0, width: 1),
        "dc30_tone": Field(offset: 216, minimum: 0, maximum: 100, bias: 0, width: 1),
        "dc30_output": Field(offset: 217, minimum: 0, maximum: 1, bias: 0, width: 1),
        "heavyoctave_1oct_level": Field(offset: 218, minimum: 0, maximum: 100, bias: 0, width: 1),
        "heavyoctave_2oct_level": Field(offset: 219, minimum: 0, maximum: 100, bias: 0, width: 1),
        "heavyoctave_direct_mix": Field(offset: 220, minimum: 0, maximum: 100, bias: 0, width: 1),
        "bend_pitch": Field(offset: 221, minimum: -24, maximum: 24, bias: 24, width: 1),
        "bend_pedal_pos": Field(offset: 222, minimum: 0, maximum: 100, bias: 0, width: 1),
        "bend_effect_level": Field(offset: 223, minimum: 0, maximum: 100, bias: 0, width: 1),
        "bend_direct_mix": Field(offset: 224, minimum: 0, maximum: 100, bias: 0, width: 1),
    ]

    private static func apply(_ section: String, _ values: [String: Any], image: inout [UInt8: [UInt8]]) throws {
        if section == "switches" || section == "colors" {
            let names = section == "switches"
                ? ["booster", "mod", "fx", "delay1", "delay2", "reverb"]
                : ["booster", "mod", "fx", "delay", "reverb"]
            let region: UInt8 = section == "switches" ? 0x08 : 0x04
            for (key, value) in values {
                guard let offset = names.firstIndex(of: key) else { throw KatanaError.invalidData }
                let byte = try number(value, types: section == "switches" ? ["off": 0, "on": 1] : colors)
                guard (0...(section == "switches" ? 1 : 2)).contains(byte) else { throw KatanaError.invalidData }
                try set(region, offset: offset, bytes: [UInt8(byte)], image: &image)
            }
            return
        }
        if section == "modtype" || section == "fxtype" {
            let base = section == "modtype" ? 0x10 : 0x16
            for (key, value) in values {
                guard let color = colors[key] else { throw KatanaError.invalidData }
                let type = try number(value, types: effectTypes)
                guard (0...30).contains(type) else { throw KatanaError.invalidData }
                try set(UInt8(base + 2 * color), offset: 0, bytes: [UInt8(type)], image: &image)
            }
            return
        }
        let color: Int
        if let value = values["color"] {
            guard let name = value as? String, let index = colors[name] else { throw KatanaError.invalidData }
            color = index
        } else { color = 0 }
        if section == "modparam" || section == "fxparam" {
            let region = UInt8((section == "modparam" ? 0x1C : 0x22) + 2 * color)
            for (key, value) in values where key != "color" {
                guard let field = effectFields[key] else { throw KatanaError.invalidData }
                let number = try number(value)
                guard (field.minimum...field.maximum).contains(number) else { throw KatanaError.invalidData }
                try set(region, offset: field.offset, bytes: encode(number + field.bias, width: field.width), image: &image)
            }
            return
        }
        let region: UInt8
        let fields: [String: Int]
        let types: [String: Int]
        switch section {
        case "amp": (region, fields, types) = (0x06, ampFields, ampTypes)
        case "other": (region, fields, types) = (0x02, otherFields, [:])
        case "booster": (region, fields, types) = (UInt8(0x0A + 2 * color), boosterFields, boosterTypes)
        case "delay1", "delay2":
            (region, fields, types) = (UInt8((section == "delay1" ? 0x28 : 0x2E) + 2 * color), delayFields, delayTypes)
        case "reverb": (region, fields, types) = (UInt8(0x34 + 2 * color), reverbFields, reverbTypes)
        case "ns": (region, fields, types) = (0x58, noiseFields, [:])
        case "solo": (region, fields, types) = (0x3A, soloFields, [:])
        default: throw KatanaError.unsupportedFormat
        }
        for (key, value) in values where key != "color" {
            let number = try number(value, types: key == "type" ? types : key == "sw" ? ["off": 0, "on": 1] : [:])
            if (section == "delay1" || section == "delay2") && key == "time" {
                guard (1...2000).contains(number) else { throw KatanaError.invalidData }
                try set(region, offset: 1, bytes: encode(number, width: 4), image: &image)
            } else if section == "reverb" && key == "predelay" {
                guard (0...500).contains(number) else { throw KatanaError.invalidData }
                try set(region, offset: 3, bytes: encode(number, width: 4), image: &image)
            } else {
                guard let offset = fields[key] else { throw KatanaError.invalidData }
                let raw = number - (section == "reverb" && key == "time" ? 1 : 0)
                guard (0...127).contains(raw) else { throw KatanaError.invalidData }
                try set(region, offset: offset, bytes: [UInt8(raw)], image: &image)
            }
        }
    }

    private static func number(_ value: Any, types: [String: Int] = [:]) throws -> Int {
        if let text = value as? String {
            guard let number = types[text] ?? Int(text) else { throw KatanaError.invalidData }
            return number
        }
        guard let number = value as? NSNumber, String(cString: number.objCType) != "c",
              number.doubleValue.isFinite, number.doubleValue.rounded() == number.doubleValue,
              (-65535...65535).contains(number.doubleValue) else { throw KatanaError.invalidData }
        return number.intValue
    }

    private static func encode(_ value: Int, width: Int) -> [UInt8] {
        width == 1 ? [UInt8(value)] : [12, 8, 4, 0].map { UInt8((value >> $0) & 0xF) }
    }

    private static func set(_ region: UInt8, offset: Int, bytes: [UInt8], image: inout [UInt8: [UInt8]]) throws {
        guard var block = image[region], offset >= 0, offset + bytes.count <= block.count else {
            throw KatanaError.invalidData
        }
        block.replaceSubrange(offset..<(offset + bytes.count), with: bytes)
        image[region] = block
    }

    private static func hex(_ list: [String]) throws -> [UInt8] {
        try list.map {
            guard $0.count == 2, let byte = UInt8($0, radix: 16), byte < 0x80 else { throw KatanaError.invalidData }
            return byte
        }
    }
}
