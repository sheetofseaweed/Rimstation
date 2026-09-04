/**
 * Sunlight state carried on the shared lighting corner.
 *
 * A corner is touched by up to four turfs, and any number of sunlit tiles can reach it. We keep the whole set
 * rather than a single value, because removing one sunlit tile must not darken a corner that another still
 * reaches - that was the bug that made roofs flicker when a wall went up beside a door.
 */
/datum/lighting_corner
	/// Sunlit effects reaching us, mapped to the strength each one contributes.
	var/list/sunlight_sources
	/// The strongest contribution in that list. What the mask actually renders.
	var/sun_falloff = 0

/// Recalculates sun_falloff from scratch. Call after removing a source.
/datum/lighting_corner/proc/recalculate_sun_falloff()
	sun_falloff = 0
	for(var/atom/movable/sunlight_effect/source as anything in sunlight_sources)
		var/contribution = sunlight_sources[source]
		if(contribution > sun_falloff)
			sun_falloff = contribution

/// Queues every turf this corner touches for a sunlight mask rebuild.
/datum/lighting_corner/proc/queue_sunlight_masters()
	queue_sunlight_turf(master_NE)
	queue_sunlight_turf(master_SE)
	queue_sunlight_turf(master_SW)
	queue_sunlight_turf(master_NW)

/// Queues one turf, if it is not already waiting.
/datum/lighting_corner/proc/queue_sunlight_turf(turf/target)
	if(isnull(target) || (target.turf_flags & TURF_SUNLIGHT_QUEUED))
		return
	target.turf_flags |= TURF_SUNLIGHT_QUEUED
	GLOB.sunlight_queue_corner += target
