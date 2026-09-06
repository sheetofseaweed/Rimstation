/**
 * Cutting the weather out from under a roof.
 *
 * [weather_roofing.dm] stops rain *doing* anything to a covered tile. This stops it being *drawn* there, which
 * is the other half and needs different machinery: the rain sprite is an overlay on the area, so it covers a
 * built room whether or not anything lands in it.
 *
 * Rather than fight the area overlay, roofed tiles draw their own white square on a plane nobody displays, and
 * the weather planes take that plane as an inverse alpha mask. Weather shows where the weather mask says yes
 * and the roof mask says nothing - so a roof punches a hole, and no upstream weather code has to know why.
 */

/// One white square per roofed tile, captured to a render target and shown to nobody.
/atom/movable/screen/plane_master/roof_mask
	name = "Roof Mask"
	documentation = "Holds a solid square for every roofed tile that stands under an open-sky area. Never \
		rendered on its own - the weather planes subtract it, so a player-built roof keeps the rain off the \
		same way the shelter capsule's own area does."
	plane = ROOF_MASK_PLANE
	appearance_flags = PLANE_MASTER | NO_CLIENT_COLOR
	render_target = ROOF_MASK_RENDER_TARGET
	render_relay_planes = list()
	start_hidden = TRUE
	critical = PLANE_CRITICAL_DISPLAY
	// The weather planes that subtract this are themselves shrunk when you look at a level below you. A mask
	// that shrank too would be captured small and then shrunk again, which is the double transform
	// plane_double_transform exists to catch. Scaling happens once, on the plane doing the subtracting.
	multiz_scaled = FALSE

/atom/movable/screen/plane_master/roof_mask/set_home(datum/plane_master_group/home)
	. = ..()
	if(!.)
		return
	// Kept alive only while weather is, exactly like the mask it works against. A roof mask maintained through
	// a clear day would be a plane's worth of work for nothing to look at.
	home.AddComponent(/datum/component/hide_weather_planes, src)

/**
 * The tiling rain sprite, minus anything roofed.
 *
 * Set on the parent type so the particle variant inherits it: both planes hold the same sprite and only one is
 * shown, so masking one and not the other would fix the weather for half the server's players.
 */
/atom/movable/screen/plane_master/weather/Initialize(mapload, datum/hud/hud_owner, datum/plane_master_group/home, offset = 0)
	. = ..()
	add_filter("roof_mask", 2, alpha_mask_filter(render_source = OFFSET_RENDER_TARGET(ROOF_MASK_RENDER_TARGET, offset), flags = MASK_INVERSE))

/// And the falling particles, which are masked separately from the sprite behind them.
/atom/movable/screen/plane_master/rendering_plate/particle_weather/Initialize(mapload, datum/hud/hud_owner, datum/plane_master_group/home, offset)
	. = ..()
	add_filter("roof_mask", 2, alpha_mask_filter(render_source = OFFSET_RENDER_TARGET(ROOF_MASK_RENDER_TARGET, offset), flags = MASK_INVERSE))


/// Cached square per plane offset. These are identical for every tile on a level, so one is enough.
GLOBAL_LIST_EMPTY(roof_mask_appearances)

/// The square a roofed tile wears, for the level it is standing on.
/proc/roof_mask_appearance(turf/target)
	var/offset = GET_TURF_PLANE_OFFSET(target)
	var/key = "[offset]"
	var/mutable_appearance/cached = GLOB.roof_mask_appearances[key]
	if(cached)
		return cached

	cached = mutable_appearance('icons/effects/alphacolors.dmi', "white", ROOF_MASK_LAYER, null, ROOF_MASK_PLANE, offset_const = offset)
	GLOB.roof_mask_appearances[key] = cached
	return cached

/turf
	/// TRUE while this turf is wearing its roof mask, so it is put on and taken off exactly once.
	var/tmp/roof_mask_applied = FALSE

/**
 * Adds or removes this tile's hole in the weather.
 *
 * Only tiles whose area is open sky ever get one. Underground is already excluded from weather by its area, and
 * giving every tile down there a mask would cost an appearance per turf for a level nothing rains on.
 */
/turf/proc/update_roof_mask(sees_sky)
	if(isnull(sees_sky))
		sees_sky = is_sky_visible()

	var/area/our_area = loc
	var/wants_mask = !isnull(our_area) && our_area.outdoors && !sees_sky
	if(wants_mask == roof_mask_applied)
		return

	roof_mask_applied = wants_mask
	if(wants_mask)
		add_overlay(roof_mask_appearance(src))
	else
		cut_overlay(roof_mask_appearance(src))
