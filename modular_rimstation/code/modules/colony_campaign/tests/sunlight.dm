/**
 * Roof detection on a map with no level above.
 *
 * The unit test map is single-z, which is exactly the expedition-site case: no ceiling to look at, so the
 * area decides, and the per-turf override has to beat it either way.
 */
/datum/unit_test/rimstation_sunlight_roofing

/datum/unit_test/rimstation_sunlight_roofing/Run()
	var/turf/subject = run_loc_floor_bottom_left
	var/area/original_area = subject.loc
	var/was_outdoors = original_area.outdoors
	var/had_override = subject.roofed_override

	original_area.outdoors = TRUE
	subject.roofed_override = FALSE
	TEST_ASSERT(subject.is_sky_visible(), "An outdoor area with nothing above it reported no sky.")

	original_area.outdoors = FALSE
	TEST_ASSERT(!subject.is_sky_visible(), "An indoor area with nothing above it reported open sky.")

	original_area.outdoors = TRUE
	subject.roofed_override = TRUE
	TEST_ASSERT(!subject.is_sky_visible(), "The roof override did not beat an outdoor area.")

	original_area.outdoors = was_outdoors
	subject.roofed_override = had_override

/**
 * A closed turf never passes light down, whatever is above it.
 *
 * Turfs cannot be allocated, so this converts a scratch turf and converts it back. ChangeTurf is the only
 * honest way to get a wall here, and it exercises the AfterChange hook at the same time.
 */
/datum/unit_test/rimstation_sunlight_closed_blocks

/datum/unit_test/rimstation_sunlight_closed_blocks/Run()
	var/turf/scratch = run_loc_floor_bottom_left
	var/original_type = scratch.type

	var/turf/wall = scratch.ChangeTurf(/turf/closed/wall)
	TEST_ASSERT(!wall.is_sky_visible_through(), "A wall let sky through to the tile below it.")

	// Run the state step by hand. The subsystem does this from a queue, which has not fired yet.
	wall.update_sky_state()

	// A roofed tile no daylight reaches gets no mask at all - drawing nothing is what dark looks like, and
	// building one per turf would cost an atom for every tile underground.
	if(!wall.is_sky_visible() && !wall.has_sun_falloff())
		TEST_ASSERT_NULL(wall.sunlight_effect, "A fully dark roofed tile was given a mask it does not need.")

	// Put the map back. Later tests share this turf.
	wall.ChangeTurf(original_type)

/**
 * Falloff drops with distance and never leaves 0..1.
 *
 * The maths is a softened cone. If it ever returns above 1 the colour matrix saturates and a doorway looks
 * brighter than open ground, which reads as a bug in the roof code rather than in this one line.
 *
 * Uses dummy corners with hand-set coordinates. Real corners register themselves onto the four turfs around
 * them, so building two here would detach the map's own corners and quietly break lighting for every test
 * that ran afterwards.
 */
/datum/unit_test/rimstation_sunlight_falloff

/datum/unit_test/rimstation_sunlight_falloff/Run()
	var/turf/source = run_loc_floor_bottom_left

	// A real corner sits half a tile off its turf, so this is the closest one can ever be.
	var/datum/lighting_corner/dummy/near = new
	near.x = source.x + 0.5
	near.y = source.y + 0.5

	var/datum/lighting_corner/dummy/far = new
	far.x = source.x + SUNLIGHT_SPREAD_RANGE + 0.5
	far.y = source.y + 0.5

	// Zero separation. The softening term drives the radicand negative here, and sqrt of a negative is a
	// runtime rather than a wrong number, so this case has to stay covered.
	var/datum/lighting_corner/dummy/coincident = new
	coincident.x = source.x
	coincident.y = source.y

	var/near_value = SUNLIGHT_FALLOFF(near, source)
	var/far_value = SUNLIGHT_FALLOFF(far, source)
	var/coincident_value = SUNLIGHT_FALLOFF(coincident, source)

	TEST_ASSERT(near_value > far_value, "Falloff did not decrease with distance: near [near_value], far [far_value].")
	TEST_ASSERT(near_value <= 1, "Falloff exceeded 1 at the nearest corner: [near_value].")
	TEST_ASSERT(far_value >= 0, "Falloff went below 0 at maximum range: [far_value].")
	TEST_ASSERT_EQUAL(coincident_value, 1, "Falloff at zero separation was [coincident_value] instead of full strength.")

	qdel(near, force = TRUE)
	qdel(far, force = TRUE)
	qdel(coincident, force = TRUE)

/**
 * Every point in the day maps to exactly one step, and every step is reachable.
 *
 * A gap here shows up in play as the sky freezing on one colour for a whole day, which is easy to mistake
 * for the plane master having failed rather than the clock.
 */
/datum/unit_test/rimstation_sunlight_day_steps

/datum/unit_test/rimstation_sunlight_day_steps/Run()
	var/list/seen = list()
	for(var/tenth in 0 to 999)
		var/datum/time_of_day/step = SSdaylight.step_for_fraction(tenth / 1000)
		TEST_ASSERT_NOTNULL(step, "No day step covers fraction [tenth / 1000].")
		seen |= step

	TEST_ASSERT_EQUAL(length(seen), length(SSdaylight.day_steps), "Only [length(seen)] of [length(SSdaylight.day_steps)] day steps are reachable.")

/// Midnight owns the small hours, before dawn has started.
/datum/unit_test/rimstation_sunlight_wraps_past_midnight

/datum/unit_test/rimstation_sunlight_wraps_past_midnight/Run()
	var/datum/time_of_day/small_hours = SSdaylight.step_for_fraction(0.05)
	TEST_ASSERT(istype(small_hours, /datum/time_of_day/midnight), "The hour after midnight reported [small_hours.name] instead of Midnight.")

/**
 * The steps tile the whole day, in order, and night is the length it is meant to be.
 *
 * Starts are a hand-tuned list of fractions. A typo produces an out-of-order or zero-length step, which does
 * not crash - it just makes one part of the day unreachable or instant, and that is very hard to spot in play.
 * Night being eight hours is a design decision rather than an accident, so a retune that changes it should
 * have to say so here.
 */
/datum/unit_test/rimstation_sunlight_step_durations

/datum/unit_test/rimstation_sunlight_step_durations/Run()
	var/list/datum/time_of_day/steps = SSdaylight.day_steps
	var/total = 0

	for(var/index in 1 to length(steps))
		var/datum/time_of_day/step = steps[index]
		var/datum/time_of_day/next = index == length(steps) ? steps[1] : steps[index + 1]

		// The last step wraps past midnight, so its successor starts earlier in the day than it does.
		var/duration = next.start - step.start
		if(duration <= 0)
			duration += 1

		TEST_ASSERT(duration > 0, "[step.name] has no duration, so it can never be seen.")
		total += duration

	TEST_ASSERT_EQUAL(round(total, 0.0001), 1, "The day steps cover [total] of a day instead of exactly one.")

	var/datum/time_of_day/night = steps[length(steps)]
	var/night_hours = (steps[1].start - night.start + 1) * 24
	TEST_ASSERT(night_hours > 7.5 && night_hours < 8.5, "Night runs [night_hours] hours; it is meant to be about 8.")

/**
 * Setting the time of day survives the next subsystem tick.
 *
 * The first version of the debug verb assigned current_step directly. That lost after one tick, because fire()
 * compares the step against the real clock and snaps it back, so setting the sky to noon appeared to do
 * nothing at all. Moving the clock is what makes it stick, and that is what this pins.
 */
/datum/unit_test/rimstation_sunlight_set_time_sticks

/datum/unit_test/rimstation_sunlight_set_time_sticks/Run()
	var/original_offset = SSdaylight.clock_offset

	for(var/datum/time_of_day/step as anything in SSdaylight.day_steps)
		SSdaylight.set_time_of_day(step)
		TEST_ASSERT_EQUAL(SSdaylight.current_step, step, "Setting the sky to [step.name] left it reading [SSdaylight.current_step?.name].")

		// What fire() asks every tick. If this is true the step is about to be overwritten.
		TEST_ASSERT(!SSdaylight.should_advance_time(), "[step.name] disagreed with the clock straight away, so the next tick would revert it.")

		var/fraction = SSdaylight.day_fraction()
		TEST_ASSERT(fraction >= 0 && fraction < 1, "Setting [step.name] put the day fraction out of range at [fraction].")

	SSdaylight.clock_offset = original_offset
	SSdaylight.advance_time_of_day()

/**
 * The fade never outlasts the step it belongs to.
 *
 * Ranges, not exact values - the clock is live and a test that pinned an exact length would only pass on a
 * server that had just started.
 */
/datum/unit_test/rimstation_sunlight_transition_bounded

/datum/unit_test/rimstation_sunlight_transition_bounded/Run()
	var/transition = SSdaylight.transition_length()
	TEST_ASSERT(transition > 0, "The colour fade had no duration.")
	TEST_ASSERT(transition <= SSdaylight.day_length(), "The colour fade ([transition]) outlasts a whole day ([SSdaylight.day_length()]).")


/**
 * A roof stops the weather, not only the light.
 *
 * The shelter capsule always worked because it brings an indoor area with it. A built room does not: its area
 * is carved out of open country and inherits `outdoors` from it, so the area flag alone calls it outside. This
 * asserts the turf is asked as well, which is what makes a player-built roof keep the rain off.
 */
/datum/unit_test/rimstation_weather_respects_roofs

/datum/unit_test/rimstation_weather_respects_roofs/Run()
	var/turf/subject = run_loc_floor_bottom_left
	var/area/test_area = subject.loc
	var/was_outdoors = test_area.outdoors
	var/had_override = subject.roofed_override

	// Open country, so the area is not what refuses the weather below.
	test_area.outdoors = TRUE
	subject.roofed_override = FALSE

	var/datum/weather/storm = new /datum/weather/particle/rain_storm(list(subject.z))
	allocated += storm

	TEST_ASSERT(subject.is_sky_visible(), "The test turf is not under open sky, so this test cannot ask its question.")
	TEST_ASSERT(storm.can_weather_act_turf(subject), "Rain did not fall on open ground.")

	// The same tile, roofed. Nothing about the area changed - only what is over the tile.
	subject.roofed_override = TRUE
	TEST_ASSERT(!subject.is_sky_visible(), "A roofed tile still reported open sky.")
	TEST_ASSERT(!storm.can_weather_act_turf(subject), "Rain fell through a roof, because the weather asked the area instead of the tile.")

	// Open country is never treated as covered. This is the early exit that keeps the wilds cheap to check.
	test_area.outdoors = TRUE
	subject.roofed_override = FALSE
	TEST_ASSERT(!area_is_fully_roofed(test_area, list(subject.z)), "Open country was reported as fully roofed, which would stop weather everywhere.")

	// An area with no turfs on the level being checked is absent, not covered.
	TEST_ASSERT(!area_is_fully_roofed(test_area, list()), "An area was called covered without a single level being checked.")

	test_area.outdoors = was_outdoors
	subject.roofed_override = had_override
