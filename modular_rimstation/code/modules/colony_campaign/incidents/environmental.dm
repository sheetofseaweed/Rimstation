/**
 * Weather the colony has to be indoors for.
 *
 * The whole incident is a wrapper around `/datum/weather`, which already telegraphs, runs, winds down and
 * spares anyone under a roof. That is exactly the shape wanted here - a warning worth acting on, and a reward
 * for having built somewhere to shelter - so nothing about it is reimplemented.
 *
 * Which storm arrives comes from the planet's own `weather_set`, so an arid world throws sand and a cold one
 * throws snow. That field has been in the planet record since Phase 1 and nothing read it until now.
 */
/datum/colony_incident/storm
	name = "storm"
	category = COLONY_INCIDENT_CATEGORY_ENVIRONMENTAL
	tags = list(INCIDENT_TAG_WEATHER)
	warning_duration = 90 SECONDS
	// A storm announces itself through the weather's own telegraph and needs no answer.
	answer_sources = NONE
	/// The weather this planet's climate produces.
	var/datum/weather/storm_type
	/// The running weather, so the incident can tell whether it actually happened.
	var/datum/weather/running_storm
	/// How many people were caught outside when it hit.
	var/caught_outside = 0

/datum/colony_incident/storm/can_begin()
	if(!..())
		return FALSE
	// Nowhere to have weather, or weather already happening, means this is not the moment for a storm.
	if(!length(get_colony_z_levels()))
		return FALSE
	for(var/datum/weather/existing as anything in SSweather.processing)
		if(existing.telegraph_duration || existing.weather_duration)
			return FALSE
	return TRUE

/// The z-levels the colony actually occupies. Weather is run against these rather than a station-wide trait.
/datum/colony_incident/storm/proc/get_colony_z_levels()
	RETURN_TYPE(/list)
	return SSmapping.levels_by_trait(ZTRAIT_STATION)

/**
 * Picks the storm from the planet's climate.
 *
 * Falls back to rain, which is the mildest of the three, so an unknown climate produces a survivable storm
 * rather than no incident at all.
 */
/datum/colony_incident/storm/select_target()
	var/datum/planet_definition/planet = get_active_colony_planet()
	switch(planet?.weather_set)
		if("arid")
			storm_type = /datum/weather/sand_storm
		if("frozen")
			storm_type = /datum/weather/snow_storm
		else
			storm_type = /datum/weather/particle/rain_storm
	return TRUE

/datum/colony_incident/storm/announce_warning()
	priority_announce("Atmospheric readings indicate severe weather closing on the settlement. Get everyone and everything under cover within [DisplayTimeText(warning_duration)].", "Colony Weather Advisory")
	return TRUE

/datum/colony_incident/storm/execute()
	if(!storm_type)
		select_target()

	running_storm = SSweather.run_weather(storm_type, get_colony_z_levels())
	if(!running_storm)
		// No storm, no incident. Resolving here rather than waiting means the colony is not told to shelter
		// from something that never arrives.
		resolve(COLONY_INCIDENT_OUTCOME_IGNORED)
		return FALSE

	// Counted once, when it lands: who was standing outside at the moment it hit is the thing preparation was
	// supposed to change.
	caught_outside = count_exposed_colonists()
	return TRUE

/// Living people standing in an area the storm reaches.
/datum/colony_incident/storm/proc/count_exposed_colonists()
	var/exposed = 0
	if(!running_storm)
		return exposed

	for(var/mob/living/person in GLOB.player_list)
		var/turf/standing = get_turf(person)
		if(!standing || !(standing.z in running_storm.impacted_z_levels))
			continue
		// The weather itself decides which areas it reaches, and it skips anything not marked outdoors - so
		// being under a roof is what saves you, without this having to work out what a roof is.
		if(!(get_area(standing) in running_storm.impacted_areas))
			continue
		exposed++
	return exposed

/**
 * A storm the colony sheltered from is a storm it beat.
 *
 * Judged on whether anyone was caught rather than on damage taken: the decision this incident asks for is
 * "stop what you are doing and get inside", and that is what gets marked.
 */
/datum/colony_incident/storm/build_result(datum/colony_incident_result/building)
	building.record_telemetry("caught_outside", caught_outside)
	building.record_telemetry("storm_type", "[storm_type]")

	if(caught_outside)
		building.add_consequence("[caught_outside] caught in the open when the weather hit")
	else
		building.add_consequence("the settlement was under cover before the weather hit")
		building.add_reward("shelter held")
	return TRUE

/// Resolved on how many were caught, so a colony that prepared is told it prepared.
/datum/colony_incident/storm/begin_resolving()
	if(!..())
		return FALSE
	resolve(caught_outside ? COLONY_INCIDENT_OUTCOME_FAILED : COLONY_INCIDENT_OUTCOME_SUCCEEDED, caught_outside ? 2 : -1)
	return TRUE
