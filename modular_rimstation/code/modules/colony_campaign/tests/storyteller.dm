#if (defined(UNIT_TESTS) || defined(SPACEMAN_DMM)) && !defined(RIMSTATION_STORYTELLER_TESTS)
#define RIMSTATION_STORYTELLER_TESTS

/datum/unit_test/rimstation_storyteller_config
	var/list/original_controls

/datum/unit_test/rimstation_storyteller_config/Run()
	original_controls = SSgamemode.control

	var/datum/round_event_control/test_control = new /datum/round_event_control/aurora_caelus
	SSgamemode.control = list(test_control)
	SSgamemode.apply_event_config(list("/datum/round_event_control/aurora_caelus" = list(
		"weight" = 7,
		"earliest_start" = 12,
	)))

	TEST_ASSERT_EQUAL(test_control.weight, 7, "Typepath-keyed event config did not set weight.")
	TEST_ASSERT_EQUAL(test_control.earliest_start, 12 MINUTES, "Event config did not convert minutes to deciseconds.")

	var/storyteller_config = file2text("config/bubbers/storyteller.txt")
	TEST_ASSERT_NOTNULL(storyteller_config, "Could not read config/bubbers/storyteller.txt.")
	for(var/config_line in splittext(storyteller_config, "\n"))
		config_line = trim(config_line)
		if(!length(config_line) || findtext(config_line, "#") == 1)
			continue
		TEST_ASSERT(findtext(config_line, "DEFAULT_STORYTELLER /datum/storyteller/extended") != 1, "Extended is forced instead of allowing a storyteller vote.")
		TEST_ASSERT(findtext(config_line, "ROLESET_") != 1, "Storyteller config still contains a stale ROLESET_ key.")
		TEST_ASSERT(findtext(config_line, "OBJECTIVES_") != 1, "Storyteller config still contains a stale OBJECTIVES_ key.")

/datum/unit_test/rimstation_storyteller_config/Destroy()
	SSgamemode.control = original_controls
	original_controls = null
	return ..()


/datum/unit_test/rimstation_storyteller_point_gain
	var/original_frequency_multiplier
	var/original_allow_pop_scaling
	var/list/original_point_gain_multipliers
	var/list/original_pop_scale_thresholds
	var/list/original_pop_scale_penalties

/datum/unit_test/rimstation_storyteller_point_gain/Run()
	original_frequency_multiplier = SSgamemode.event_frequency_multiplier
	original_allow_pop_scaling = SSgamemode.allow_pop_scaling
	original_point_gain_multipliers = SSgamemode.point_gain_multipliers
	original_pop_scale_thresholds = SSgamemode.pop_scale_thresholds
	original_pop_scale_penalties = SSgamemode.pop_scale_penalties

	SSgamemode.event_frequency_multiplier = 0.5
	SSgamemode.allow_pop_scaling = TRUE
	SSgamemode.point_gain_multipliers = list(EVENT_TRACK_MUNDANE = 2)
	SSgamemode.pop_scale_thresholds = list(EVENT_TRACK_MUNDANE = 10)
	SSgamemode.pop_scale_penalties = list(EVENT_TRACK_MUNDANE = 30)

	var/datum/storyteller/test_storyteller = new
	var/delta_time = 20
	var/base_gain = EVENT_POINT_GAINED_PER_SECOND * delta_time
	var/actual_gain = test_storyteller.get_track_point_gain(EVENT_TRACK_MUNDANE, delta_time, 5)
	TEST_ASSERT_EQUAL(actual_gain, base_gain * 2 * 0.5 * 0.85, "Point gain did not apply track, global-frequency, and linear population multipliers.")
	SSgamemode.pop_scale_thresholds[EVENT_TRACK_MUNDANE] = 0
	TEST_ASSERT_EQUAL(SSgamemode.get_population_frequency_multiplier(EVENT_TRACK_MUNDANE, 0), 1, "A zero population threshold should disable population scaling.")
	SSgamemode.pop_scale_thresholds[EVENT_TRACK_MUNDANE] = 10
	SSgamemode.pop_scale_penalties[EVENT_TRACK_MUNDANE] = 150
	TEST_ASSERT_EQUAL(SSgamemode.get_population_frequency_multiplier(EVENT_TRACK_MUNDANE, 0), 0, "Population penalties should clamp at 100 percent without becoming negative.")
	qdel(test_storyteller)

/datum/unit_test/rimstation_storyteller_point_gain/Destroy()
	SSgamemode.event_frequency_multiplier = original_frequency_multiplier
	SSgamemode.allow_pop_scaling = original_allow_pop_scaling
	SSgamemode.point_gain_multipliers = original_point_gain_multipliers
	SSgamemode.pop_scale_thresholds = original_pop_scale_thresholds
	SSgamemode.pop_scale_penalties = original_pop_scale_penalties
	return ..()

#endif
