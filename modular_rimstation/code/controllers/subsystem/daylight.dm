/// Turfs whose sky state needs deciding.
GLOBAL_LIST_EMPTY(sunlight_queue_state)
/// Effects whose spread needs applying.
GLOBAL_LIST_EMPTY(sunlight_queue_effect)
/// Turfs whose mask needs rebuilding from their corners.
GLOBAL_LIST_EMPTY(sunlight_queue_corner)

/**
 * Drives roof-based sunlight and the day/night cycle.
 *
 * Split into three queues because the work is genuinely sequential: a turf has to know it is roofed before a
 * neighbour can know it is a border, and a corner cannot be rendered until every tile that reaches it has
 * had its say. Running them in one pass produced tiles that were a tick behind the wall beside them.
 */
SUBSYSTEM_DEF(daylight)
	name = "Sunlight"
	dependencies = list(
		/datum/controller/subsystem/lighting,
		/datum/controller/subsystem/mapping,
	)
	wait = 1
	ss_flags = SS_TICKER

	/// Cached colour matrices, keyed by their four corner strengths.
	var/list/matrix_cache
	/// Where we are in the day.
	var/datum/time_of_day/current_step
	/// What comes next, and when.
	var/datum/time_of_day/next_step
	/// The colour the current step picked.
	var/picked_colour
	/// Manual shift applied to the day clock, in deciseconds. Kept in [0, day length).
	var/clock_offset = 0
	/// Z-levels that get sunlight at all, keyed by z number as text for a cheap lookup on a hot path.
	var/list/sunlit_z_levels = list()

/datum/controller/subsystem/daylight/stat_entry(msg)
	msg = "\n  State:[length(GLOB.sunlight_queue_state)]|Effect:[length(GLOB.sunlight_queue_effect)]|Corner:[length(GLOB.sunlight_queue_corner)] [current_step?.name]"
	return ..()

/datum/controller/subsystem/daylight/Initialize()
	advance_time_of_day()
	for(var/z_level in SSmapping.levels_by_trait(ZTRAIT_STATION))
		sunlit_z_levels["[z_level]"] = TRUE
		for(var/turf/target as anything in Z_TURFS(z_level))
			target.turf_flags |= TURF_SKY_STATE_QUEUED
			GLOB.sunlight_queue_state += target
	initialized = TRUE

	// Drain everything here, inside startup, rather than letting it bleed into the first minute of the round.
	// One pass is not enough: the three queues feed each other, so the state pass fills the effect pass and
	// that fills the corner pass. Leftovers used to surface as a tick dilation spike right after roundstart.
	//
	// Bounded, because no queue should refill itself and a startup that never returns is far worse than one
	// that hands the remainder to the first few ticks. If this ever trips, a pass is adding its own work back.
	var/passes = 0
	while(length(GLOB.sunlight_queue_state) || length(GLOB.sunlight_queue_effect) || length(GLOB.sunlight_queue_corner))
		fire(FALSE, TRUE)
		passes++
		if(passes > SUNLIGHT_MAX_INIT_PASSES)
			stack_trace("Sunlight init did not settle after [passes] passes - state:[length(GLOB.sunlight_queue_state)] effect:[length(GLOB.sunlight_queue_effect)] corner:[length(GLOB.sunlight_queue_corner)]. A queue is feeding itself.")
			break

	return SS_INIT_SUCCESS

/datum/controller/subsystem/daylight/fire(resumed, init_tick_checks)
	MC_SPLIT_TICK_INIT(3)
	if(!init_tick_checks)
		MC_SPLIT_TICK

	var/index = 0

	for(index in 1 to length(GLOB.sunlight_queue_state))
		var/turf/target = GLOB.sunlight_queue_state[index]
		if(target)
			target.turf_flags &= ~TURF_SKY_STATE_QUEUED
			target.update_sky_state()
			var/atom/movable/sunlight_effect/effect = target.sunlight_effect
			if(effect && !effect.queued)
				effect.queued = TRUE
				GLOB.sunlight_queue_effect += effect
		if(init_tick_checks)
			CHECK_TICK
		else if(MC_TICK_CHECK)
			break
	if(index)
		GLOB.sunlight_queue_state.Cut(1, index + 1)
		index = 0

	if(!init_tick_checks)
		MC_SPLIT_TICK

	for(index in 1 to length(GLOB.sunlight_queue_effect))
		var/atom/movable/sunlight_effect/effect = GLOB.sunlight_queue_effect[index]
		if(effect)
			effect.queued = FALSE
			effect.process_state()
			apply_mask(effect)
		if(init_tick_checks)
			CHECK_TICK
		else if(MC_TICK_CHECK)
			break
	if(index)
		GLOB.sunlight_queue_effect.Cut(1, index + 1)
		index = 0

	if(!init_tick_checks)
		MC_SPLIT_TICK

	for(index in 1 to length(GLOB.sunlight_queue_corner))
		var/turf/target = GLOB.sunlight_queue_corner[index]
		target.turf_flags &= ~TURF_SUNLIGHT_QUEUED
		var/atom/movable/sunlight_effect/effect = target.sunlight_effect
		// A roofed tile only gets a mask once daylight actually reaches it. Building one for every dark tile
		// would cost an atom per turf underground for something that renders as nothing.
		if(!effect && target.has_sun_falloff())
			effect = new /atom/movable/sunlight_effect(null, target)
			effect.state = SKY_BLOCKED
		// Only roofed tiles read their corners. Open ones are full white regardless.
		if(effect?.state == SKY_BLOCKED)
			apply_mask(effect)
		if(init_tick_checks)
			CHECK_TICK
		else if(MC_TICK_CHECK)
			break
	if(index)
		GLOB.sunlight_queue_corner.Cut(1, index + 1)

	if(should_advance_time())
		advance_time_of_day()
		retint_all_planes()

/**
 * Writes the right mask onto one effect.
 *
 * Sets icon_state, colour and luminosity one at a time rather than assigning an appearance. Assigning a whole
 * appearance would overwrite the per-z plane offset the effect set in Initialize, and the mask would render
 * on the wrong level.
 */
/datum/controller/subsystem/daylight/proc/apply_mask(atom/movable/sunlight_effect/effect)
	if(effect.state != SKY_BLOCKED)
		effect.icon_state = null
		effect.color = SUNLIGHT_FULL_MATRIX
		effect.luminosity = 1
		return

	var/turf/target = effect.affected_turf
	target.sunlight_ensure_corners()

	var/static/datum/lighting_corner/dummy/dummy_corner = new
	var/datum/lighting_corner/red = target.lighting_corner_SW || dummy_corner
	var/datum/lighting_corner/green = target.lighting_corner_SE || dummy_corner
	var/datum/lighting_corner/blue = target.lighting_corner_NW || dummy_corner
	var/datum/lighting_corner/alpha = target.lighting_corner_NE || dummy_corner

	var/strongest = max(red.sun_falloff, green.sun_falloff, blue.sun_falloff, alpha.sun_falloff)
	#if LIGHTING_SOFT_THRESHOLD != 0
	var/any_light = strongest > LIGHTING_SOFT_THRESHOLD
	#else
	var/any_light = strongest > 1e-6
	#endif

	if(!any_light)
		effect.icon_state = "lighting_dark"
		effect.color = null
		effect.luminosity = 0
		return

	effect.icon_state = null
	effect.color = get_matrix(red.sun_falloff, green.sun_falloff, blue.sun_falloff, alpha.sun_falloff)
	effect.luminosity = 1

/// Fetches a cached colour matrix for these four strengths, building it if this combination is new.
/datum/controller/subsystem/daylight/proc/get_matrix(red = 0, green = 0, blue = 0, alpha = 0)
	var/key = "[red]|[green]|[blue]|[alpha]"
	if(!matrix_cache?[key])
		LAZYSET(matrix_cache, key, list(
			red, red, red, 0,
			green, green, green, 0,
			blue, blue, blue, 0,
			alpha, alpha, alpha, 0,
			0, 0, 0, 1
		))
	return matrix_cache[key]

/**
 * Fades every player's sunlight plane to the current colour.
 *
 * `override_transition` exists for the debug verb: the natural fade is a fraction of a day, which is useless
 * when you are jumping between times to judge a colour.
 */
/datum/controller/subsystem/daylight/proc/retint_all_planes(override_transition)
	var/transition = isnull(override_transition) ? transition_length() : override_transition
	for(var/mob/player as anything in GLOB.player_list)
		var/datum/hud/player_hud = player.hud_used
		if(!player_hud)
			continue
		for(var/atom/movable/screen/plane_master/plane as anything in player_hud.get_true_plane_masters(SUNLIGHTING_PLANE))
			tint_plane(plane, transition)

/**
 * Puts the current colour on one sunlight plane.
 *
 * A colour matrix filter, not the plane's own `color`. This plane is captured to a render target and relayed
 * onto the lighting plate, and a plane master's colour does not survive that capture - the tint simply never
 * appeared. Filters do survive it, which is how client colour tints the game plane
 * (`/mob/proc/update_client_colour`).
 */
/datum/controller/subsystem/daylight/proc/tint_plane(atom/movable/screen/plane_master/plane, transition)
	var/list/tint = color_matrix_filter(picked_colour)
	if(plane.get_filter(SUNLIGHT_TINT_FILTER))
		plane.transition_filter(SUNLIGHT_TINT_FILTER, tint, transition)
		return
	plane.add_filter(SUNLIGHT_TINT_FILTER, 1, tint)
