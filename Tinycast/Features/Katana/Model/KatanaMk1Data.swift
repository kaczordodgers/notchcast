nonisolated enum KatanaMk1Data {
    static let names: [KatanaMkIIBlock: String] = [
        .name: """
            patch_name1 patch_name2 patch_name3 patch_name4 patch_name5 patch_name6 patch_name7 patch_name8 patch_name9
            patch_name10 patch_name11 patch_name12 patch_name13 patch_name14 patch_name15 patch_name16
            """,
        .patch0: """
            od_ds_on_off od_ds_type od_ds_drive od_ds_bottom od_ds_tone od_ds_solo_sw od_ds_solo_level od_ds_effect_level
            od_ds_direct_mix - - - - - - - - preamp_a_type preamp_a_gain - preamp_a_bass preamp_a_middle preamp_a_treble
            preamp_a_presence preamp_a_level preamp_a_bright - preamp_a_solo_sw preamp_a_solo_level - - - - - - -
            - - - - - - - - - - - - eq_on_off eq_type eq_low_cut eq_low_gain eq_low_mid_freq eq_low_mid_q eq_low_mid_gain
            eq_high_mid_freq eq_high_mid_q eq_high_mid_gain eq_high_gain eq_high_cut eq_level eq_geq_31hz eq_geq_62hz
            eq_geq_125hz eq_geq_250hz eq_geq_500hz eq_geq_1khz eq_geq_2khz eq_geq_4khz eq_geq_8khz eq_geq_16khz eq_geq_level
            """,
        .fx1: """
            fx1_on_off fx1_fx_type fx1_t_wah_mode fx1_t_wah_polar fx1_t_wah_sens fx1_t_wah_freq fx1_t_wah_peak
            fx1_t_wah_direct_mix
            fx1_t_wah_effect_level fx1_auto_wah_mode fx1_auto_wah_freq fx1_auto_wah_peak fx1_auto_wah_rate fx1_auto_wah_depth
            fx1_auto_wah_direct_mix fx1_auto_wah_effect_level fx1_sub_wah_type fx1_sub_wah_pedal_pos fx1_sub_wah_pedal_min
            fx1_sub_wah_pedal_max fx1_sub_wah_effect_level fx1_sub_wah_direct_mix fx1_adv_comp_type fx1_adv_comp_sustain
            fx1_adv_comp_attack fx1_adv_comp_tone fx1_adv_comp_level fx1_limiter_type fx1_limiter_attack fx1_limiter_thresh
            fx1_limiter_ratio fx1_limiter_release fx1_limiter_level fx1_graphic_eq_31hz fx1_graphic_eq_62hz fx1_graphic_eq_125hz
            fx1_graphic_eq_250hz fx1_graphic_eq_500hz fx1_graphic_eq_1khz fx1_graphic_eq_2khz fx1_graphic_eq_4khz
            fx1_graphic_eq_8khz fx1_graphic_eq_16khz fx1_graphic_eq_level fx1_parametric_eq_low_cut fx1_parametric_eq_low_gain
            fx1_parametric_eq_low_mid_freq fx1_parametric_eq_low_mid_q fx1_parametric_eq_low_mid_gain
            fx1_parametric_eq_high_mid_freq
            fx1_parametric_eq_high_mid_q fx1_parametric_eq_high_mid_gain fx1_parametric_eq_high_gain fx1_parametric_eq_high_cut
            fx1_parametric_eq_level fx1_guitar_sim_type fx1_guitar_sim_low fx1_guitar_sim_high fx1_guitar_sim_level
            fx1_guitar_sim_body fx1_slow_gear_sens fx1_slow_gear_rise_time fx1_slow_gear_level fx1_wave_synth_wave
            fx1_wave_synth_cutoff fx1_wave_synth_reso fx1_wave_synth_filter_sens fx1_wave_synth_filter_decay
            fx1_wave_synth_filter_depth
            fx1_wave_synth_synth_level fx1_wave_synth_direct_mix fx1_octave_range fx1_octave_level fx1_octave_direct_mix
            fx1_pitch_shifter_voice fx1_pitch_shifter_ps1mode fx1_pitch_shifter_ps1pitch fx1_pitch_shifter_ps1fine
            fx1_pitch_shifter_ps1pre_dly_h fx1_pitch_shifter_ps1pre_dly_l fx1_pitch_shifter_ps1level fx1_pitch_shifter_ps2mode
            fx1_pitch_shifter_ps2pitch fx1_pitch_shifter_ps2fine fx1_pitch_shifter_ps2pre_dly_h fx1_pitch_shifter_ps2pre_dly_l
            fx1_pitch_shifter_ps2level fx1_pitch_shifter_ps1f_back fx1_pitch_shifter_direct_mix fx1_harmonist_voice
            fx1_harmonist_hr1harm fx1_harmonist_hr1pre_dly_h fx1_harmonist_hr1pre_dly_l fx1_harmonist_hr1level
            fx1_harmonist_hr2harm
            fx1_harmonist_hr2pre_dly_h fx1_harmonist_hr2pre_dly_l fx1_harmonist_hr2level fx1_harmonist_hr1f_back
            fx1_harmonist_direct_mix
            fx1_harmonist_hr1c fx1_harmonist_hr1db fx1_harmonist_hr1d fx1_harmonist_hr1eb fx1_harmonist_hr1e fx1_harmonist_hr1f
            fx1_harmonist_hr1f_s fx1_harmonist_hr1g fx1_harmonist_hr1ab fx1_harmonist_hr1a fx1_harmonist_hr1bb
            fx1_harmonist_hr1b
            fx1_harmonist_hr2c fx1_harmonist_hr2db fx1_harmonist_hr2d fx1_harmonist_hr2eb fx1_harmonist_hr2e fx1_harmonist_hr2f
            fx1_harmonist_hr2f_s fx1_harmonist_hr2g fx1_harmonist_hr2ab fx1_harmonist_hr2a fx1_harmonist_hr2bb
            fx1_harmonist_hr2b
            fx1_ac_processor_type fx1_ac_processor_bass fx1_ac_processor_middle fx1_ac_processor_middle_freq
            fx1_ac_processor_treble
            fx1_ac_processor_presence fx1_ac_processor_level fx1_phaser_type fx1_phaser_rate fx1_phaser_depth fx1_phaser_manual
            fx1_phaser_reso fx1_phaser_step_rate fx1_phaser_effect_level fx1_phaser_direct_mix fx1_flanger_rate
            fx1_flanger_depth
            fx1_flanger_manual fx1_flanger_reso - fx1_flanger_low_cut fx1_flanger_effect_level fx1_flanger_direct_mix
            fx1_tremolo_wave_shape fx1_tremolo_rate fx1_tremolo_depth fx1_tremolo_level - - fx1_rotary_rate_fast -
            - fx1_rotary_depth fx1_rotary_level fx1_uni_v_rate fx1_uni_v_depth fx1_uni_v_level fx1_slicer_pattern
            fx1_slicer_rate fx1_slicer_trigger_sens fx1_slicer_effect_level fx1_slicer_direct_mix fx1_vibrato_rate
            fx1_vibrato_depth - - fx1_vibrato_level fx1_ring_mod_mode fx1_ring_mod_freq fx1_ring_mod_effect_level
            fx1_ring_mod_direct_mix fx1_humanizer_mode fx1_humanizer_vowel1 fx1_humanizer_vowel2 fx1_humanizer_sens
            fx1_humanizer_rate fx1_humanizer_depth fx1_humanizer_manual fx1_humanizer_level fx1_2x2_chorus_xover_freq
            fx1_2x2_chorus_low_rate fx1_2x2_chorus_low_depth fx1_2x2_chorus_low_pre_delay fx1_2x2_chorus_low_level
            fx1_2x2_chorus_high_rate fx1_2x2_chorus_high_depth fx1_2x2_chorus_high_pre_delay fx1_2x2_chorus_high_level
            fx1_2x2_chorus_direct_level fx1_acsim_high fx1_acsim_body fx1_acsim_low - fx1_acsim_level fx1_phaser90e_script
            fx1_phaser90e_speed fx1_flanger117e_manual fx1_flanger117e_width fx1_flanger117e_speed fx1_flanger117e_regen
            fx1_wah95e_pedal_pos fx1_wah95e_pedal_min fx1_wah95e_pedal_max fx1_wah95e_effect_level fx1_wah95e_direct_mix
            fx1_dc30_selector fx1_dc30_input_volume fx1_dc30_chorus_intensity fx1_dc30_echo_repeat_rate_h
            fx1_dc30_echo_repeat_rate_l
            fx1_dc30_echo_intensity fx1_dc30_echo_volume fx1_dc30_tone fx1_dc30_output
            """,
        .fx2: """
            fx2_on_off fx2_fx_type fx2_t_wah_mode fx2_t_wah_polar fx2_t_wah_sens fx2_t_wah_freq fx2_t_wah_peak
            fx2_t_wah_direct_mix
            fx2_t_wah_effect_level fx2_auto_wah_mode fx2_auto_wah_freq fx2_auto_wah_peak fx2_auto_wah_rate fx2_auto_wah_depth
            fx2_auto_wah_direct_mix fx2_auto_wah_effect_level fx2_sub_wah_type fx2_sub_wah_pedal_pos fx2_sub_wah_pedal_min
            fx2_sub_wah_pedal_max fx2_sub_wah_effect_level fx2_sub_wah_direct_mix fx2_adv_comp_type fx2_adv_comp_sustain
            fx2_adv_comp_attack fx2_adv_comp_tone fx2_adv_comp_level fx2_limiter_type fx2_limiter_attack fx2_limiter_thresh
            fx2_limiter_ratio fx2_limiter_release fx2_limiter_level fx2_graphic_eq_31hz fx2_graphic_eq_62hz fx2_graphic_eq_125hz
            fx2_graphic_eq_250hz fx2_graphic_eq_500hz fx2_graphic_eq_1khz fx2_graphic_eq_2khz fx2_graphic_eq_4khz
            fx2_graphic_eq_8khz fx2_graphic_eq_16khz fx2_graphic_eq_level fx2_parametric_eq_low_cut fx2_parametric_eq_low_gain
            fx2_parametric_eq_low_mid_freq fx2_parametric_eq_low_mid_q fx2_parametric_eq_low_mid_gain
            fx2_parametric_eq_high_mid_freq
            fx2_parametric_eq_high_mid_q fx2_parametric_eq_high_mid_gain fx2_parametric_eq_high_gain fx2_parametric_eq_high_cut
            fx2_parametric_eq_level fx2_guitar_sim_type fx2_guitar_sim_low fx2_guitar_sim_high fx2_guitar_sim_level
            fx2_guitar_sim_body fx2_slow_gear_sens fx2_slow_gear_rise_time fx2_slow_gear_level fx2_wave_synth_wave
            fx2_wave_synth_cutoff fx2_wave_synth_reso fx2_wave_synth_filter_sens fx2_wave_synth_filter_decay
            fx2_wave_synth_filter_depth
            fx2_wave_synth_synth_level fx2_wave_synth_direct_mix fx2_octave_range fx2_octave_level fx2_octave_direct_mix
            fx2_pitch_shifter_voice fx2_pitch_shifter_ps1mode fx2_pitch_shifter_ps1pitch fx2_pitch_shifter_ps1fine
            fx2_pitch_shifter_ps1pre_dly_h fx2_pitch_shifter_ps1pre_dly_l fx2_pitch_shifter_ps1level fx2_pitch_shifter_ps2mode
            fx2_pitch_shifter_ps2pitch fx2_pitch_shifter_ps2fine fx2_pitch_shifter_ps2pre_dly_h fx2_pitch_shifter_ps2pre_dly_l
            fx2_pitch_shifter_ps2level fx2_pitch_shifter_ps1f_back fx2_pitch_shifter_direct_mix fx2_harmonist_voice
            fx2_harmonist_hr1harm fx2_harmonist_hr1pre_dly_h fx2_harmonist_hr1pre_dly_l fx2_harmonist_hr1level
            fx2_harmonist_hr2harm
            fx2_harmonist_hr2pre_dly_h fx2_harmonist_hr2pre_dly_l fx2_harmonist_hr2level fx2_harmonist_hr1f_back
            fx2_harmonist_direct_mix
            fx2_harmonist_hr1c fx2_harmonist_hr1db fx2_harmonist_hr1d fx2_harmonist_hr1eb fx2_harmonist_hr1e fx2_harmonist_hr1f
            fx2_harmonist_hr1f_s fx2_harmonist_hr1g fx2_harmonist_hr1ab fx2_harmonist_hr1a fx2_harmonist_hr1bb
            fx2_harmonist_hr1b
            fx2_harmonist_hr2c fx2_harmonist_hr2db fx2_harmonist_hr2d fx2_harmonist_hr2eb fx2_harmonist_hr2e fx2_harmonist_hr2f
            fx2_harmonist_hr2f_s fx2_harmonist_hr2g fx2_harmonist_hr2ab fx2_harmonist_hr2a fx2_harmonist_hr2bb
            fx2_harmonist_hr2b
            fx2_ac_processor_type fx2_ac_processor_bass fx2_ac_processor_middle fx2_ac_processor_middle_freq
            fx2_ac_processor_treble
            fx2_ac_processor_presence fx2_ac_processor_level fx2_phaser_type fx2_phaser_rate fx2_phaser_depth fx2_phaser_manual
            fx2_phaser_reso fx2_phaser_step_rate fx2_phaser_effect_level fx2_phaser_direct_mix fx2_flanger_rate
            fx2_flanger_depth
            fx2_flanger_manual fx2_flanger_reso - fx2_flanger_low_cut fx2_flanger_effect_level fx2_flanger_direct_mix
            fx2_tremolo_wave_shape fx2_tremolo_rate fx2_tremolo_depth fx2_tremolo_level - - fx2_rotary_rate_fast -
            - fx2_rotary_depth fx2_rotary_level fx2_uni_v_rate fx2_uni_v_depth fx2_uni_v_level fx2_slicer_pattern
            fx2_slicer_rate fx2_slicer_trigger_sens fx2_slicer_effect_level fx2_slicer_direct_mix fx2_vibrato_rate
            fx2_vibrato_depth - - fx2_vibrato_level fx2_ring_mod_mode fx2_ring_mod_freq fx2_ring_mod_effect_level
            fx2_ring_mod_direct_mix fx2_humanizer_mode fx2_humanizer_vowel1 fx2_humanizer_vowel2 fx2_humanizer_sens
            fx2_humanizer_rate fx2_humanizer_depth fx2_humanizer_manual fx2_humanizer_level fx2_2x2_chorus_xover_freq
            fx2_2x2_chorus_low_rate fx2_2x2_chorus_low_depth fx2_2x2_chorus_low_pre_delay fx2_2x2_chorus_low_level
            fx2_2x2_chorus_high_rate fx2_2x2_chorus_high_depth fx2_2x2_chorus_high_pre_delay fx2_2x2_chorus_high_level
            fx2_2x2_chorus_direct_level - - - - - - - - - - - fx2_wah95e_pedal_pos fx2_wah95e_pedal_min fx2_wah95e_pedal_max
            fx2_wah95e_effect_level fx2_wah95e_direct_mix fx2_dc30_selector fx2_dc30_input_volume fx2_dc30_chorus_intensity
            fx2_dc30_echo_repeat_rate_h fx2_dc30_echo_repeat_rate_l fx2_dc30_echo_intensity fx2_dc30_echo_volume fx2_dc30_tone
            fx2_dc30_output
            """,
        .delay1: """
            delay_on_off delay_type delay_delay_time_h delay_delay_time_l delay_f_back delay_high_cut delay_effect_level
            delay_direct_mix delay_tap_time - - - - - - - - - - delay_mod_rate delay_mod_depth delay_vtg_lpf delay_vtg_filter
            delay_vtg_feedback_phase delay_vtg_effect_phase delay_vtg_mod_sw
            """,
        .delay2: """
            delay2_on_off delay2_type delay2_delay_time_h delay2_delay_time_l delay2_f_back delay2_high_cut delay2_effect_level
            delay2_direct_mix delay2_tap_time - - - - - - - - - - delay2_mod_rate delay2_mod_depth delay2_vtg_lpf
            delay2_vtg_filter delay2_vtg_feedback_phase delay2_vtg_effect_phase delay2_vtg_mod_sw
            """,
        .patch1: """
            reverb_on_off reverb_type reverb_time reverb_pre_delay_h reverb_pre_delay_l reverb_low_cut reverb_high_cut
            reverb_density reverb_effect_level reverb_direct_mix - - - - - - - - - - - - - - - - - - - - - - - -
            send_return_on_off
            send_return_mode send_return_send_level send_return_return_level ns1_on_off ns1_threshold ns1_release
            - - - - - - - - master_key
            """,
        .patch2: """
            chain_ptn send_return_position eq_position - fxbox_asgn_fx1a_g fxbox_asgn_fx1a_r fxbox_asgn_fx1a_y fxbox_asgn_fx1b_g
            fxbox_asgn_fx1b_r fxbox_asgn_fx1b_y fxbox_asgn_fx2b_g fxbox_asgn_fx2b_r fxbox_asgn_fx2b_y fxbox_asgn_fx2a_g
            fxbox_asgn_fx2a_r fxbox_asgn_fx2a_y fxbox_asgn_fx3_g fxbox_asgn_fx3_r fxbox_asgn_fx3_y fxbox_asgn_fx3b_g
            fxbox_asgn_fx3b_r fxbox_asgn_fx3b_y fxbox_layer_fx3_g fxbox_layer_fx3_r fxbox_layer_fx3_y fxbox_sel_fx1a
            fxbox_sel_fx1b fxbox_sel_fx2b fxbox_sel_fx2a fxbox_sel_fx3 pedal_function_exp_pedal pedal_function_gafc_exp1
            pedal_function_gafc_exp2
            """,
        .knobAssign: """
            knob_assign_booster knob_assign_delay knob_assign_reverb knob_assign_chorus knob_assign_flanger knob_assign_phaser
            knob_assign_uni_v knob_assign_tremolo knob_assign_vibrato knob_assign_rotary knob_assign_ring_mod
            knob_assign_slow_gear
            knob_assign_slicer knob_assign_comp knob_assign_limiter knob_assign_t_wah knob_assign_auto_wah knob_assign_pedal_wah
            knob_assign_geq knob_assign_peq knob_assign_guitar_sim knob_assign_ac_guitar_sim knob_assign_ac_processor
            knob_assign_wave_synth knob_assign_octave knob_assign_pitch_shifter knob_assign_harmonist knob_assign_humanizer
            knob_assign_evh_phaser knob_assign_evh_flanger knob_assign_evh_wah knob_assign_dc30
            """,
        .pedalAssign: """
            exp_pedal_assign_booster exp_pedal_assign_delay exp_pedal_assign_reverb exp_pedal_assign_chorus
            exp_pedal_assign_flanger
            exp_pedal_assign_phaser exp_pedal_assign_uni_v exp_pedal_assign_tremolo exp_pedal_assign_vibrato
            exp_pedal_assign_rotary
            exp_pedal_assign_ring_mod exp_pedal_assign_slow_gear exp_pedal_assign_slicer exp_pedal_assign_comp
            exp_pedal_assign_limiter
            exp_pedal_assign_t_wah exp_pedal_assign_auto_wah exp_pedal_assign_pedal_wah exp_pedal_assign_geq
            exp_pedal_assign_peq
            exp_pedal_assign_guitar_sim exp_pedal_assign_ac_guitar_sim exp_pedal_assign_ac_processor exp_pedal_assign_wave_synth
            exp_pedal_assign_octave exp_pedal_assign_pitch_shifter exp_pedal_assign_harmonist exp_pedal_assign_humanizer
            exp_pedal_assign_evh_phaser exp_pedal_assign_evh_flanger exp_pedal_assign_evh_wah exp_pedal_assign_dc30
            """,
        .pedalRange: """
            exp_pedal_assign_booster_min exp_pedal_assign_booster_max exp_pedal_assign_delay_min_h exp_pedal_assign_delay_min_l
            exp_pedal_assign_delay_max_h exp_pedal_assign_delay_max_l exp_pedal_assign_reverb_min_h
            exp_pedal_assign_reverb_min_l
            exp_pedal_assign_reverb_max_h exp_pedal_assign_reverb_max_l exp_pedal_assign_chorus_min exp_pedal_assign_chorus_max
            exp_pedal_assign_flanger_min exp_pedal_assign_flanger_max exp_pedal_assign_phaser_min exp_pedal_assign_phaser_max
            exp_pedal_assign_uni_v_min exp_pedal_assign_uni_v_max exp_pedal_assign_tremolo_min exp_pedal_assign_tremolo_max
            exp_pedal_assign_vibrato_min exp_pedal_assign_vibrato_max exp_pedal_assign_rotary_min exp_pedal_assign_rotary_max
            exp_pedal_assign_ring_mod_min exp_pedal_assign_ring_mod_max exp_pedal_assign_slow_gear_min
            exp_pedal_assign_slow_gear_max
            exp_pedal_assign_slicer_min exp_pedal_assign_slicer_max exp_pedal_assign_comp_min exp_pedal_assign_comp_max
            exp_pedal_assign_limiter_min exp_pedal_assign_limiter_max exp_pedal_assign_t_wah_min exp_pedal_assign_t_wah_max
            exp_pedal_assign_auto_wah_min exp_pedal_assign_auto_wah_max exp_pedal_assign_pedal_wah_min
            exp_pedal_assign_pedal_wah_max
            exp_pedal_assign_geq_min exp_pedal_assign_geq_max exp_pedal_assign_peq_min exp_pedal_assign_peq_max
            exp_pedal_assign_guitar_sim_min
            exp_pedal_assign_guitar_sim_max exp_pedal_assign_ac_guitar_sim_min exp_pedal_assign_ac_guitar_sim_max
            exp_pedal_assign_ac_processor_min exp_pedal_assign_ac_processor_max exp_pedal_assign_wave_synth_min
            exp_pedal_assign_wave_synth_max
            exp_pedal_assign_octave_min exp_pedal_assign_octave_max exp_pedal_assign_pitch_shifter_min_h
            exp_pedal_assign_pitch_shifter_min_l
            exp_pedal_assign_pitch_shifter_max_h exp_pedal_assign_pitch_shifter_max_l exp_pedal_assign_harmonist_min_h
            exp_pedal_assign_harmonist_min_l exp_pedal_assign_harmonist_max_h exp_pedal_assign_harmonist_max_l
            exp_pedal_assign_humanizer_min
            exp_pedal_assign_humanizer_max exp_pedal_assign_evh_phaser_min exp_pedal_assign_evh_phaser_max
            exp_pedal_assign_evh_flanger_min
            exp_pedal_assign_evh_flanger_max exp_pedal_assign_evh_wah_min exp_pedal_assign_evh_wah_max
            exp_pedal_assign_dc30_min_h
            exp_pedal_assign_dc30_min_l exp_pedal_assign_dc30_max_h exp_pedal_assign_dc30_max_l
            """,
    ]

    static let fileRuns: [(file: Int, count: Int, block: KatanaMkIIBlock, first: Int)] = [
        (0, 16, .name, 0), (48, 9, .patch0, 0), (81, 2, .patch0, 17), (84, 6, .patch0, 20), (91, 2, .patch0, 27),
        (176, 1, .patch0, 48), (177, 11, .patch0, 50), (192, 2, .fx1, 0), (204, 7, .fx1, 2), (212, 7, .fx1, 9),
        (220, 6, .fx1, 16), (227, 5, .fx1, 22), (233, 6, .fx1, 27), (240, 11, .fx1, 33), (252, 11, .fx1, 44),
        (270, 5, .fx1, 55), (276, 3, .fx1, 60), (288, 8, .fx1, 63), (305, 3, .fx1, 71), (309, 15, .fx1, 74),
        (325, 35, .fx1, 89), (365, 7, .fx1, 124), (373, 8, .fx1, 131), (382, 4, .fx1, 139), (387, 3, .fx1, 144),
        (391, 4, .fx1, 147), (398, 1, .fx1, 153), (401, 2, .fx1, 156), (404, 3, .fx1, 158), (415, 5, .fx1, 161),
        (421, 2, .fx1, 166), (425, 1, .fx1, 170), (427, 4, .fx1, 171), (432, 8, .fx1, 175), (441, 10, .fx1, 183),
        (460, 2, .fx2, 0), (472, 7, .fx2, 2), (480, 7, .fx2, 9), (488, 6, .fx2, 16), (495, 5, .fx2, 22), (501, 6, .fx2, 27),
        (508, 11, .fx2, 33), (520, 11, .fx2, 44), (538, 5, .fx2, 55), (544, 3, .fx2, 60), (556, 8, .fx2, 63),
        (573, 3, .fx2, 71), (577, 15, .fx2, 74), (593, 35, .fx2, 89), (633, 7, .fx2, 124), (641, 8, .fx2, 131),
        (650, 4, .fx2, 139), (655, 3, .fx2, 144), (659, 4, .fx2, 147), (666, 1, .fx2, 153), (669, 2, .fx2, 156),
        (672, 3, .fx2, 158), (683, 5, .fx2, 161), (689, 2, .fx2, 166), (693, 1, .fx2, 170), (695, 4, .fx2, 171),
        (700, 8, .fx2, 175), (709, 10, .fx2, 183), (736, 9, .delay1, 0), (755, 2, .delay1, 19), (784, 10, .patch1, 0),
        (853, 4, .patch1, 34), (867, 3, .patch1, 38), (920, 1, .patch1, 49), (2064, 3, .fx1, 193), (2068, 1, .fx1, 197),
        (2109, 6, .fx1, 198), (2121, 5, .delay1, 21), (2126, 9, .delay2, 0), (2145, 7, .delay2, 19), (2152, 14, .fx1, 204),
        (2166, 14, .fx2, 204), (2180, 1, .patch0, 49), (2181, 11, .patch0, 61), (2304, 1, .patch2, 0), (2305, 6, .patch2, 4),
        (2311, 3, .patch2, 13), (2314, 3, .patch2, 10), (2317, 3, .patch2, 16), (2320, 2, .patch2, 25), (2322, 1, .patch2, 28),
        (2323, 1, .patch2, 27), (2324, 1, .patch2, 29), (2327, 2, .patch2, 1), (2329, 6, .patch2, 19), (2335, 3, .patch2, 30),
        (2352, 32, .knobAssign, 0), (2432, 32, .pedalAssign, 0), (2464, 74, .pedalRange, 0),
    ]

    static let initial: [KatanaMkIIBlock: String] = [
        .name: """
            4B4154414E4120202020202020202020
            """,
        .patch0: """
            000A453C32003229000032323232320001173C0A32362F003100010032000101
            0564000032320505323232070A0A0200000000140E0114170114140E14181818
            1818181818181818
            """,
        .eq2: """
            000000140E0114170114140E141818181818181818181818
            """,
        .fx1: """
            011D01013223230032012332323C0032006400646400003232323200001E0B0A
            1E141414141414141414141400140D0114170114140E1400323232322D323C00
            281E2832321900003E640001183C0000460118280000460064010C0000460700
            0050006418181818181818181818181818181818181818181818181801323210
            32323200462837000064001F28523200003C0046554132011E5500003C32463C
            640032323200502D01003200326464010002325064326404502E034B46300341
            50323232323201322D3232506400646400003232031032643200320064243264
            00
            """,
        .fx2: """
            011501013223230032012332323C0032006400646400003232323200001E0B0A
            1E141414141414141414141400140D0114170114140E1400323232322D323C00
            281E2832321900003E640001183C0000460118280000460064010C0000460700
            0050006418181818181818181818181818181818181818181818181801323210
            32323200462837000064001F28523200003C00465A4132011E5500003C32463C
            640032323200502D010032003264640100023250643264042B2E034B21300341
            50323232323201322D3232506400646400003232031032643200320064243264
            00
            """,
        .delay1: """
            00000310170C6064320064160A320310160A3228370100000000
            """,
        .delay2: """
            00000310160A3264320064160A320310160A3228370100000000
            """,
        .patch1: """
            01041D000A0E0805646400640000000000000064006464002432640064006464
            0064010032320005320000000000000064000000000000000000000000000000
            000000000000000000000000000000000000000000320000070132
            """,
        .patch2: """
            010001000A0B0E1D141315000E00070804050300070802020200000000000200
            02000401
            """,
        .status: """
            013232323232320000000000000000000000
            """,
        .knobAssign: """
            0000000000000000000000000000000000000000000000000000000000000000
            0000
            """,
        .pedalAssign: """
            0000000000000000000000000000000000000000000000000000000000000000
            0000
            """,
        .pedalRange: """
            0064000000640000006400640064006400640064006400640064006400640064
            0064006400640064006400640064006400640064006400000064000000640064
            0064006400640000006400640064
            """,
        .fsAssign: """
            0001
            """,
        .solo: """
            000000180D0118180E1800010310163264000A002837
            """,
        .contour1: """
            0032
            """,
        .contour2: """
            0032
            """,
        .contour3: """
            0032
            """,
    ]
}
