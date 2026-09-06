/turf
	/// Our sunlight mask, if we have one.
	var/tmp/atom/movable/sunlight_effect/sunlight_effect
	/// Forces this turf to count as roofed whatever the z-stack says. For tents, and for single-z maps.
	var/roofed_override = FALSE

/**
 * Can this turf see the sky?
 *
 * Walks up the z-stack. A turf with nothing above it falls back to its area, which is the only case where an
 * area flag still decides anything - it is what a top z-level has instead of a roof.
 */
/turf/proc/is_sky_visible()
	if(roofed_override)
		return FALSE

	var/turf/ceiling = GET_TURF_ABOVE(src)
	if(ceiling)
		return ceiling.is_sky_visible_through()

	var/area/our_area = loc
	return our_area.outdoors

/// Does this turf let the one below it see the sky?
/turf/proc/is_sky_visible_through()
	if(!istransparentturf(src))
		return FALSE
	return is_sky_visible()

/// Closed turfs never let light down. Skip the checks.
/turf/closed/is_sky_visible_through()
	return FALSE

/// Creates any lighting corners this turf is missing. GENERATE_MISSING_CORNERS is undef'd where it lives.
/turf/proc/sunlight_ensure_corners()
	if(lighting_corners_initialised)
		return
	if(!lighting_corner_NE)
		lighting_corner_NE = new /datum/lighting_corner(x, y, z)
	if(!lighting_corner_SE)
		lighting_corner_SE = new /datum/lighting_corner(x, y - 1, z)
	if(!lighting_corner_SW)
		lighting_corner_SW = new /datum/lighting_corner(x - 1, y - 1, z)
	if(!lighting_corner_NW)
		lighting_corner_NW = new /datum/lighting_corner(x - 1, y, z)
	lighting_corners_initialised = TRUE

/**
 * Works out our sky state and creates our mask if we do not have one.
 *
 * A tile is a border only if it can see the sky and a neighbour cannot. This deliberately differs from the
 * Vanderlin source, which also treats any neighbouring closed turf as a border trigger. That works on a
 * hand-mapped town where a wall always carries a roof. It would be ruinous here: the wilds generator fills
 * the surface with loose rock, so every tile beside a boulder would run a view(3) spread it has no use for.
 * A wall under open sky casts no shadow, so it should not make its neighbours border tiles.
 */
/turf/proc/update_sky_state()
	var/sees_sky = is_sky_visible()
	// The weather's hole in this tile turns on the same answer, so it is set from here rather than from a queue
	// of its own. It has to happen before the early return below, which a dark roofed tile takes.
	update_roof_mask(sees_sky)

	var/new_state
	if(!sees_sky)
		new_state = SKY_BLOCKED
	else
		new_state = SKY_VISIBLE
		for(var/turf/neighbour in orange(1, src))
			if(!neighbour.is_sky_visible())
				new_state = SKY_VISIBLE_BORDER
				break

	// A fully roofed tile that no daylight reaches needs no mask at all: drawing nothing on the sunlight
	// plane already leaves it dark. Only make one when there is light to show, or when we already have one
	// that may still be catching spread from a nearby opening. Skipping this is the difference between one
	// mask per turf and one per lit turf, which on a whole underground level is tens of thousands of atoms.
	if(!sunlight_effect)
		if(new_state == SKY_BLOCKED)
			return
		new /atom/movable/sunlight_effect(null, src)
	sunlight_effect.state = new_state

/// Does any daylight reach this turf's corners? Cheap check before building a mask for a roofed tile.
/turf/proc/has_sun_falloff()
	return lighting_corner_NE?.sun_falloff \
		|| lighting_corner_SE?.sun_falloff \
		|| lighting_corner_SW?.sun_falloff \
		|| lighting_corner_NW?.sun_falloff

/**
 * Queues this turf and everything below it for a fresh sky check.
 *
 * Called whenever a turf appears or changes. A roof going up on one level darkens the tiles under it, so the
 * whole column below has to be reconsidered, not just the tile that changed.
 */
/turf/proc/reassess_sky_column()
	if(!SSdaylight.initialized)
		return
	// Only the sunlit levels have sky to reassess. Reserved and transit turfs in particular must be left
	// alone: GET_TURF_BELOW routes them through their reservation, which is not yet built while the turf is
	// being created, and asking runtimes out of ChangeTurf.
	if(!SSdaylight.sunlit_z_levels["[z]"])
		return

	queue_sky_state()

	// Our neighbours may stop or start being border tiles because of us.
	for(var/turf/neighbour in orange(1, src))
		neighbour.queue_sky_state()

	var/turf/below = GET_TURF_BELOW(src)
	if(below)
		below.reassess_sky_column()

/// Puts this turf in the sky-state queue once. A flag, not a list search - `|=` on a six-figure queue is
/// quadratic, and terrain generation pushes tens of thousands of turfs through here.
/turf/proc/queue_sky_state()
	if(turf_flags & TURF_SKY_STATE_QUEUED)
		return
	turf_flags |= TURF_SKY_STATE_QUEUED
	GLOB.sunlight_queue_state += src
