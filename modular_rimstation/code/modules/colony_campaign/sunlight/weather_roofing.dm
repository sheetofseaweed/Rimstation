/**
 * Roofs keep the weather out, not just the light.
 *
 * Upstream weather asks one question - is this area `outdoors` - and the shelter capsule passes because it
 * brings its own indoor area with it. A colonist who builds a room and roofs it does not: the area is carved
 * out of the wilds and inherits `outdoors` from it, because roof-based sunlight needs that flag to stay honest
 * about what is under open sky. So the flag alone says a built room is outside, and rain fell through roofs.
 *
 * The authority is the same one the light uses: `is_sky_visible()`, which walks the z-stack. This makes the
 * weather read it too, at both scales - the area, so a covered room is never drawn as raining, and the turf,
 * so a roof going up mid-storm stops the rain over it immediately.
 */

/**
 * TRUE when nothing in this area can see the sky.
 *
 * Returns on the first uncovered turf, which is what keeps this cheap: open country answers on its first tile,
 * and only a genuinely enclosed room is ever walked to the end.
 */
/proc/area_is_fully_roofed(area/checking, list/z_levels)
	if(!istype(checking) || !length(z_levels))
		return FALSE

	var/found_any_turf = FALSE
	for(var/z in z_levels)
		if(length(checking.turfs_by_zlevel) < z)
			continue
		for(var/turf/covered as anything in checking.turfs_by_zlevel[z])
			if(isnull(covered))
				continue
			found_any_turf = TRUE
			if(covered.is_sky_visible())
				return FALSE

	// An area with no turfs on these levels is not "covered", it is simply not here. Saying otherwise would
	// silently exclude areas that weather has every right to reach.
	return found_any_turf

/**
 * Drops areas that are wholly under cover before the parent ever sees them.
 *
 * Filtering the candidates rather than pruning `impacted_areas` afterwards, because the parent also builds the
 * weighted turf tables from this list - removing an area later would leave it in those and keep it being picked.
 */
/datum/weather/setup_weather_areas(list/forced_areas)
	if(weather_flags & WEATHER_INDOORS)
		return ..()

	var/list/uncovered = list()
	for(var/area/candidate as anything in (forced_areas || get_areas(area_type)))
		if(area_is_fully_roofed(candidate, impacted_z_levels))
			continue
		uncovered += candidate
	return ..(uncovered)

/**
 * A tile under a roof is not rained on, whatever its area says.
 *
 * This is the half that covers a partly built room, and a roof raised while the storm is already running.
 */
/datum/weather/can_weather_act_turf(turf/valid_weather_turf)
	. = ..()
	if(!.)
		return .
	if(weather_flags & WEATHER_INDOORS)
		return .
	return valid_weather_turf.is_sky_visible()

/// And the same for whoever is standing on it, so shelter protects the person as well as the floor.
/datum/weather/can_weather_act_mob(mob/living/mob_to_check)
	. = ..()
	if(!.)
		return .
	if(weather_flags & WEATHER_INDOORS)
		return .

	var/turf/mob_turf = get_turf(mob_to_check)
	return mob_turf?.is_sky_visible()
