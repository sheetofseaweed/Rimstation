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


/datum/unit_test/rimstation_storyteller_earliest_start
	var/datum/round_event_control/midround_control
	var/datum/round_event_control/roundstart_control

/datum/unit_test/rimstation_storyteller_earliest_start/Run()
	midround_control = new
	midround_control.earliest_start = 10 MINUTES
	// If the shared contract already rejects this control the timing assertions below would pass for the wrong reason.
	TEST_ASSERT(midround_control.can_spawn_event(0), "Baseline event eligibility failed, so the earliest_start assertions are meaningless.")

	TEST_ASSERT(!midround_control.can_spawn_storyteller_event(0, 9 MINUTES), "An event was eligible one minute before its earliest_start.")
	TEST_ASSERT(midround_control.can_spawn_storyteller_event(0, 10 MINUTES), "An event was not eligible exactly at its earliest_start.")

	// earliest_start describes midround timing only. Roundstart events are gated by the roundstart/round-started check instead.
	roundstart_control = new
	roundstart_control.earliest_start = 10 MINUTES
	roundstart_control.roundstart = TRUE
	TEST_ASSERT_EQUAL(roundstart_control.can_spawn_storyteller_event(0, 0), roundstart_control.can_spawn_event(0), "earliest_start was applied to a roundstart event.")

/datum/unit_test/rimstation_storyteller_earliest_start/Destroy()
	QDEL_NULL(midround_control)
	QDEL_NULL(roundstart_control)
	return ..()


/datum/unit_test/rimstation_storyteller_event_control_lookup
	var/list/original_gamemode_controls
	var/datum/round_event_control/legacy_control
	var/datum/round_event_control/storyteller_control

/datum/unit_test/rimstation_storyteller_event_control_lookup/Run()
	original_gamemode_controls = SSgamemode.control

	legacy_control = new /datum/round_event_control/aurora_caelus
	SSevents.control += legacy_control
	storyteller_control = new /datum/round_event_control/aurora_caelus
	SSgamemode.control = list(storyteller_control)

	TEST_ASSERT_EQUAL(SSgamemode.get_event_control(/datum/round_event_control/aurora_caelus), storyteller_control, "get_event_control returned the legacy instance instead of the active storyteller one.")
	TEST_ASSERT_NULL(SSgamemode.get_event_control(/datum/round_event_control/brand_intelligence), "get_event_control invented a control that is not in the active pool.")

/datum/unit_test/rimstation_storyteller_event_control_lookup/Destroy()
	SSgamemode.control = original_gamemode_controls
	original_gamemode_controls = null
	SSevents.control -= legacy_control
	QDEL_NULL(legacy_control)
	QDEL_NULL(storyteller_control)
	return ..()


/datum/unit_test/rimstation_storyteller_vote
	var/original_configured_default

/datum/unit_test/rimstation_storyteller_vote/Run()
	original_configured_default = CONFIG_GET(string/default_storyteller)

	CONFIG_SET(string/default_storyteller, "")
	var/datum/storyteller/chill = SSgamemode.storytellers[/datum/storyteller/chill]
	TEST_ASSERT_NOTNULL(chill, "The chill storyteller is missing, so the vote assertions cannot run.")
	TEST_ASSERT_EQUAL(SSgamemode.resolve_storyteller_choice(chill.name), /datum/storyteller/chill, "A winning storyteller name did not resolve to its type.")
	TEST_ASSERT_EQUAL(SSgamemode.resolve_storyteller_choice(null), /datum/storyteller/default, "An empty vote result did not fall back to the default storyteller.")
	TEST_ASSERT_EQUAL(SSgamemode.resolve_storyteller_choice("Not A Storyteller"), /datum/storyteller/default, "An unknown vote result did not fall back to the default storyteller.")

	// A server that configures a default is deliberately overriding the vote.
	CONFIG_SET(string/default_storyteller, "/datum/storyteller/extended")
	TEST_ASSERT_EQUAL(SSgamemode.resolve_storyteller_choice(chill.name), /datum/storyteller/extended, "A configured default storyteller did not override the vote result.")

	// A broken config entry must not silently become the round's storyteller.
	CONFIG_SET(string/default_storyteller, "/datum/storyteller/does_not_exist")
	TEST_ASSERT_EQUAL(SSgamemode.resolve_storyteller_choice(chill.name), /datum/storyteller/chill, "An invalid configured default was used instead of falling back to the vote.")

/datum/unit_test/rimstation_storyteller_vote/Destroy()
	CONFIG_SET(string/default_storyteller, original_configured_default)
	return ..()


/datum/unit_test/rimstation_storyteller_eta
	var/list/original_point_thresholds
	var/list/original_track_points
	var/list/original_point_gains

/datum/unit_test/rimstation_storyteller_eta/Run()
	original_point_thresholds = SSgamemode.point_thresholds
	original_track_points = SSgamemode.event_track_points
	original_point_gains = SSgamemode.last_point_gains

	SSgamemode.point_thresholds = list(EVENT_TRACK_MUNDANE = 1200)
	SSgamemode.event_track_points = list(EVENT_TRACK_MUNDANE = 0)
	SSgamemode.last_point_gains = list(EVENT_TRACK_MUNDANE = 1)

	// 1200 remaining points at 1 point per 20-second storyteller tick.
	TEST_ASSERT_EQUAL(SSgamemode.estimate_track_eta(EVENT_TRACK_MUNDANE), 24000 SECONDS, "Track ETA did not account for the storyteller tick length.")

	SSgamemode.last_point_gains[EVENT_TRACK_MUNDANE] = 0
	TEST_ASSERT_NULL(SSgamemode.estimate_track_eta(EVENT_TRACK_MUNDANE), "A track gaining no points reported an ETA instead of nothing.")

	SSgamemode.last_point_gains[EVENT_TRACK_MUNDANE] = 1
	SSgamemode.event_track_points[EVENT_TRACK_MUNDANE] = 1200
	TEST_ASSERT_EQUAL(SSgamemode.estimate_track_eta(EVENT_TRACK_MUNDANE), 0, "A track already at its threshold did not report an immediate ETA.")

/datum/unit_test/rimstation_storyteller_eta/Destroy()
	SSgamemode.point_thresholds = original_point_thresholds
	SSgamemode.event_track_points = original_track_points
	SSgamemode.last_point_gains = original_point_gains
	return ..()

#endif
