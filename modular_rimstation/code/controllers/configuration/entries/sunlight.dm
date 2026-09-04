// Roof-based sunlight.
/**
 * Minutes of real time in one full in-game day.
 *
 * Config rather than a define because day length is the single knob playtesting will want to move, and
 * rebuilding to change it wastes ten minutes each time.
 */
/datum/config_entry/number/sunlight_day_length_minutes
	config_entry_value = 120
	min_val = 1
