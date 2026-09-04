/**
 * Draws every sunlight mask, tinted to the time of day.
 *
 * The tint lives here rather than on the masks because a plane master is per-client: changing the colour of
 * the whole sky is one animate() per player instead of one per tile. Relays onto the turf lighting plate so
 * sunlight and lamps add together the way two lamps would.
 */
/atom/movable/screen/plane_master/sunlighting
	name = "Sunlighting"
	documentation = "Holds the grayscale sunlight masks that say how much sky each tile can see. White is open \
		ground, black is under a roof. This plane's own colour is the time of day, applied by SSdaylight, so \
		the whole world changes colour without touching a single turf."
	plane = SUNLIGHTING_PLANE
	appearance_flags = PLANE_MASTER | NO_CLIENT_COLOR
	render_relay_planes = list(RENDER_PLANE_TURF_LIGHTING)
	blend_mode_override = BLEND_ADD
	mouse_opacity = MOUSE_OPACITY_TRANSPARENT
	critical = PLANE_CRITICAL_DISPLAY

/atom/movable/screen/plane_master/sunlighting/Initialize(mapload, datum/hud/hud_owner, datum/plane_master_group/home, offset = 0)
	. = ..()
	// A plane that appears mid-round must not flash white before the first cycle tick. Filter rather than
	// colour, for the reason documented on SSdaylight.tint_plane.
	SSdaylight.tint_plane(src, 0)
