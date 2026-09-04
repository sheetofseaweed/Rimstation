/**
 * One step of the day, and the colour the sky takes during it.
 *
 * Colours are lists so a step can vary between days - two dawns that look identical every single round read
 * as a loop rather than a world. One is picked when the step begins.
 */
/datum/time_of_day
	var/name = ""
	/// Colours this step may take. One is picked per occurrence.
	var/list/colours
	/// When this step starts, as a fraction of the day from 0 to 1.
	var/start = 0

/**
 * Dawn.
 *
 * Cool and blue, but bright enough to work in. The Vanderlin values these replaced were around 30% luminance,
 * which rendered as a second night: two hours of darkness the clock called morning.
 */
/datum/time_of_day/dawn
	name = "Dawn"
	colours = list("#7e8fc4", "#9b8ac0", "#bf9bb2")
	start = 0.208333 // 05:00

/datum/time_of_day/sunrise
	name = "Sunrise"
	colours = list("#f598ab", "#f28a8a", "#f5906f")
	start = 0.3125 // 07:30

/datum/time_of_day/daytime
	name = "Daytime"
	colours = list("#f7baba", "#f5eabe", "#ffface", "#bfd7e0", "#d2c1eb", "#e7bbd8")
	start = 0.333333 // 08:00

/datum/time_of_day/sunset
	name = "Sunset"
	colours = list("#fc7c52")
	start = 0.75 // 18:00

/datum/time_of_day/dusk
	name = "Dusk"
	colours = list("#df6e4c", "#df4974", "#cf472b")
	start = 0.770833 // 18:30

/**
 * Full night, and the only genuinely dark step.
 *
 * Starts at 21:00 rather than 20:00 so that night runs exactly eight hours, 21:00 to 05:00. The hour it gave
 * up went to dusk and the half hour at the far end to dawn, so the extra time is daylight rather than a
 * longer twilight on one side only.
 */
/datum/time_of_day/midnight
	name = "Midnight"
	colours = list("#29173f", "#2f0f46", "#34013f")
	start = 0.875 // 21:00

/// The six steps, in order. Midnight must be last: the wrap-around depends on it.
/datum/controller/subsystem/daylight/var/list/datum/time_of_day/day_steps = list(
	new /datum/time_of_day/dawn(),
	new /datum/time_of_day/sunrise(),
	new /datum/time_of_day/daytime(),
	new /datum/time_of_day/sunset(),
	new /datum/time_of_day/dusk(),
	new /datum/time_of_day/midnight(),
)

/// How long one full day takes, in deciseconds.
/datum/controller/subsystem/daylight/proc/day_length()
	var/configured = CONFIG_GET(number/sunlight_day_length_minutes)
	if(!configured)
		return SUNLIGHT_DEFAULT_DAY_LENGTH
	return configured MINUTES

/// Where we are in the day, from 0 at midnight to 1 at the next midnight.
/datum/controller/subsystem/daylight/proc/day_fraction()
	var/length = day_length()
	return ((STATION_TIME_PASSED() + clock_offset) % length) / length

/**
 * Shifts the clock so that it now reads the start of `step`.
 *
 * Moves the clock rather than just assigning current_step. Assigning it alone survives exactly one tick: fire()
 * compares the step against the real clock every tick and snaps it back, so a manual set appeared to do nothing.
 *
 * Lands a nudge past the boundary rather than exactly on it. Multiplying a start fraction by the day length
 * and dividing it back does not always return the same number, and landing a hair short of a step means
 * step_for_fraction finds the one before it - which for Dawn is the wrap-around, so the sky read Midnight.
 */
/datum/controller/subsystem/daylight/proc/set_time_of_day(datum/time_of_day/step)
	var/length = day_length()
	var/target = (step.start + SUNLIGHT_STEP_NUDGE) * length
	var/now = (STATION_TIME_PASSED() + clock_offset) % length
	// Keep the offset positive: DM's modulo carries the sign of its left operand.
	clock_offset = (clock_offset + (target - now) + length) % length
	advance_time_of_day()

/// Has the day moved into a new step?
/datum/controller/subsystem/daylight/proc/should_advance_time()
	return step_for_fraction(day_fraction()) != current_step

/// Which step covers this point in the day. The last step wraps around past midnight.
/datum/controller/subsystem/daylight/proc/step_for_fraction(fraction)
	var/datum/time_of_day/found
	for(var/datum/time_of_day/step as anything in day_steps)
		if(fraction >= step.start)
			found = step
	// Before the first step of the day means we are still in the last step of the one before.
	return found || day_steps[length(day_steps)]

/// Moves to whichever step the clock now says, and picks its colour.
/datum/controller/subsystem/daylight/proc/advance_time_of_day()
	current_step = step_for_fraction(day_fraction())
	var/current_index = day_steps.Find(current_step)
	next_step = current_index == length(day_steps) ? day_steps[1] : day_steps[current_index + 1]
	picked_colour = pick(current_step.colours)

/**
 * How long the fade to the new colour should take.
 *
 * Capped at the time left in the step so a short step is never still fading when it ends, which looked like
 * the cycle had stalled.
 */
/datum/controller/subsystem/daylight/proc/transition_length()
	var/length = day_length()
	// A next step earlier in the day than we are means it belongs to tomorrow.
	var/remaining = next_step.start - day_fraction()
	if(remaining <= 0)
		remaining += 1
	return min(length * 0.08, length * remaining)
