/**
 * Dumps what the sunlight system thinks about one tile.
 *
 * The three layers fail differently and look the same on screen: a tile can be wrongly roofed, correctly
 * roofed but wrongly rendered, or correct but stuck in a queue. This says which.
 */
ADMIN_VERB(sunlight_inspect, R_DEBUG, "Inspect Sunlight", "Show the sunlight state of a tile.", ADMIN_CATEGORY_DEBUG, turf/target in world)
	var/atom/movable/sunlight_effect/effect = target.sunlight_effect
	var/turf/ceiling = GET_TURF_ABOVE(target)
	var/area/our_area = target.loc

	var/list/report = list()
	report += "<b>Sunlight at [AREACOORD(target)]</b>"
	report += "sky visible: [target.is_sky_visible() ? "yes" : "no"]"
	report += "roof override: [target.roofed_override ? "set" : "not set"]"
	report += "turf above: [ceiling ? "[ceiling.type], [istransparentturf(ceiling) ? "transparent" : "solid"]" : "none - area outdoors is [our_area.outdoors ? "true" : "false"]"]"

	if(effect)
		var/list/state_names = list("[SKY_BLOCKED]" = "blocked", "[SKY_VISIBLE]" = "visible", "[SKY_VISIBLE_BORDER]" = "border")
		report += "effect state: [state_names["[effect.state]"]]"
		report += "corners cast to: [length(effect.affecting_corners)]"
	else
		report += "effect: none"

	target.sunlight_ensure_corners()
	report += "corner falloff: NE [target.lighting_corner_NE?.sun_falloff] SE [target.lighting_corner_SE?.sun_falloff] SW [target.lighting_corner_SW?.sun_falloff] NW [target.lighting_corner_NW?.sun_falloff]"
	report += "lumcount: [target.get_lumcount()]"
	report += "queued: [target.turf_flags & TURF_SUNLIGHT_QUEUED ? "yes" : "no"]"
	report += "sunlit z-level: [SSdaylight.sunlit_z_levels["[target.z]"] ? "yes" : "no - this level gets no sunlight at all"]"
	report += "time of day: [SSdaylight.current_step?.name] ([SSdaylight.picked_colour]), day fraction [round(SSdaylight.day_fraction(), 0.001)]"

	// Says whether the tint reached your screen. A missing filter here with a correct mask above means the
	// world is lit but uncoloured, which is a different bug from a world that is simply dark.
	var/list/planes = user.mob?.hud_used?.get_true_plane_masters(SUNLIGHTING_PLANE)
	report += "sunlight planes on your screen: [length(planes)]"
	for(var/atom/movable/screen/plane_master/plane as anything in planes)
		report += "&nbsp;&nbsp;[plane.name]: tint filter [plane.get_filter(SUNLIGHT_TINT_FILTER) ? "present" : "MISSING"]"

	to_chat(user, jointext(report, "<br>"), confidential = TRUE)

/**
 * Jumps the sky straight to a chosen time of day.
 *
 * Waiting out a real day to look at dusk makes tuning the colours impractical. This does not move the clock,
 * so the cycle carries on from wherever it really is on the next step - long enough to judge a colour.
 */
ADMIN_VERB(sunlight_set_time, R_DEBUG, "Set Time Of Day", "Jump the sky to a chosen time of day.", ADMIN_CATEGORY_DEBUG)
	var/list/choices = list()
	for(var/datum/time_of_day/step as anything in SSdaylight.day_steps)
		choices[step.name] = step

	var/chosen = tgui_input_list(user, "Which time of day?", "Set Time Of Day", choices)
	if(isnull(chosen))
		return

	var/datum/time_of_day/step = choices[chosen]
	SSdaylight.set_time_of_day(step)
	SSdaylight.retint_all_planes(override_transition = 2 SECONDS)

	to_chat(user, span_notice("Sky set to [SSdaylight.current_step.name] ([SSdaylight.picked_colour]). The clock now reads [round(SSdaylight.day_fraction() * 24, 0.1)]:00 and carries on from there."), confidential = TRUE)
