/**
 * The grayscale sunlight mask for one turf.
 *
 * Sits in the turf's vis_contents with a null loc, the same as a lighting_object, so it can carry a per-z
 * plane offset. White means full daylight, black means fully roofed, and anything between is a tile near a
 * roof edge. The colour of the light is not here - the plane master tints the whole plane at once.
 */
/atom/movable/sunlight_effect
	name = ""
	anchored = TRUE
	plane = SUNLIGHTING_PLANE
	icon = LIGHTING_ICON
	icon_state = null
	color = null
	appearance_flags = RESET_COLOR | RESET_ALPHA | RESET_TRANSFORM
	mouse_opacity = MOUSE_OPACITY_TRANSPARENT
	invisibility = INVISIBILITY_LIGHTING
	move_resist = INFINITY

	/// The turf we mask.
	var/turf/affected_turf
	/// SKY_BLOCKED, SKY_VISIBLE or SKY_VISIBLE_BORDER.
	var/state = SKY_VISIBLE
	/// Corners we currently contribute light to. Only border tiles have any.
	var/list/datum/lighting_corner/affecting_corners
	/// Whether we are already sitting in the effect queue. A flag rather than a list search, because that
	/// queue holds one entry per lit turf at init and `|=` on it would be quadratic.
	var/queued = FALSE

/atom/movable/sunlight_effect/Initialize(mapload, turf/affected_turf)
	. = ..()
	verbs.Cut()

	if(!isturf(affected_turf))
		qdel(src, force = TRUE)
		CRASH("a sunlight effect was assigned to [affected_turf], a non turf!")

	src.affected_turf = affected_turf
	if(SSmapping.max_plane_offset)
		plane = SUNLIGHTING_PLANE - (PLANE_RANGE * GET_Z_PLANE_OFFSET(affected_turf.z))

	if(affected_turf.sunlight_effect)
		qdel(affected_turf.sunlight_effect, force = TRUE)
	affected_turf.sunlight_effect = src
	affected_turf.vis_contents += src

/atom/movable/sunlight_effect/Destroy(force)
	if(!force)
		return QDEL_HINT_LETMELIVE

	stop_casting()

	if(queued)
		GLOB.sunlight_queue_effect -= src
		queued = FALSE

	if(isturf(affected_turf))
		affected_turf.vis_contents -= src
		if(affected_turf.sunlight_effect == src)
			affected_turf.sunlight_effect = null
	affected_turf = null
	return ..()

/// Applies whatever our state now demands.
/atom/movable/sunlight_effect/proc/process_state()
	switch(state)
		if(SKY_BLOCKED)
			stop_casting()
		if(SKY_VISIBLE_BORDER)
			cast_into_shade()
		if(SKY_VISIBLE)
			stop_casting()

/**
 * Drops every corner contribution we make, and queues the turfs that lose light.
 *
 * Returns immediately when we were casting nothing, which is the overwhelmingly common case: an open tile
 * under open sky has no corners to release. Doing work here anyway queued every lit turf in the world on the
 * first pass, and that queue was still draining minutes into the round.
 *
 * Our own mask does not need queueing. The subsystem calls apply_mask on us directly after this returns.
 */
/atom/movable/sunlight_effect/proc/stop_casting()
	if(!length(affecting_corners))
		return

	for(var/datum/lighting_corner/corner as anything in affecting_corners)
		LAZYREMOVE(corner.sunlight_sources, src)
		corner.recalculate_sun_falloff()
		corner.queue_sunlight_masters()
	affecting_corners = null

/**
 * Spreads our light onto every corner within reach that a wall does not block.
 *
 * The turf's luminosity is raised for the duration because view() will not see past darkness otherwise, and
 * a roofed neighbour is by definition dark. It is restored before we return.
 */
/atom/movable/sunlight_effect/proc/cast_into_shade()
	var/turf/source = affected_turf
	if(isnull(source))
		return

	var/list/reached_corners = list()
	var/old_luminosity = source.luminosity
	source.luminosity = SUNLIGHT_SPREAD_RANGE

	// No `as anything` here. view() returns every atom in range, including areas and movables, and that skips
	// the type filter rather than applying it - which meant calling turf procs on /area and runtiming out of
	// this proc on the first one.
	for(var/turf/nearby in view(SUNLIGHT_SPREAD_RANGE, source))
		if(nearby.opacity)
			continue
		nearby.sunlight_ensure_corners()
		reached_corners |= nearby.lighting_corner_NE
		reached_corners |= nearby.lighting_corner_SE
		reached_corners |= nearby.lighting_corner_SW
		reached_corners |= nearby.lighting_corner_NW

	source.luminosity = old_luminosity
	reached_corners -= null

	LAZYINITLIST(affecting_corners)

	// Corners we newly reach, or still reach: write our contribution.
	var/list/gained = reached_corners - affecting_corners
	affecting_corners += gained
	for(var/datum/lighting_corner/corner as anything in gained)
		LAZYSET(corner.sunlight_sources, src, SUNLIGHT_FALLOFF(corner, source))
		if(corner.sunlight_sources[src] > corner.sun_falloff)
			corner.sun_falloff = corner.sunlight_sources[src]
			corner.queue_sunlight_masters()

	// Corners we no longer reach: drop out and let them recalculate.
	var/list/lost = affecting_corners - reached_corners
	affecting_corners -= lost
	for(var/datum/lighting_corner/corner as anything in lost)
		LAZYREMOVE(corner.sunlight_sources, src)
		corner.recalculate_sun_falloff()
		corner.queue_sunlight_masters()
