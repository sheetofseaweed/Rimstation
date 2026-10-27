/**
 * Whether this client cuts the rain out from under roofs.
 *
 * Correctness costs a render pass. The mask is a plane captured to a render target and subtracted from the
 * weather planes as an inverse alpha filter, which is a second full-screen mask on top of the one upstream
 * already runs for particle weather. On a machine that was only just keeping up, that is the kind of thing
 * that turns rain into a slideshow.
 *
 * Off, the tiles keep their masks - those are turf overlays, shared by everybody - and this client simply
 * stops subtracting them. Rain is then drawn over roofed ground again, exactly as it was before the mask
 * existed. It still does not *do* anything there: [weather_roofing.dm] is what keeps a sheltered colonist dry,
 * and it is server-side and unaffected.
 *
 * Defaults to on. A preference exists at all because "is this what is slow" cannot be answered from a log -
 * it needs the player who is complaining to turn one thing off and say whether it helped.
 */
/datum/preference/toggle/roof_mask_weather
	category = PREFERENCE_CATEGORY_GAME_PREFERENCES
	savefile_key = "roof_mask_weather"
	savefile_identifier = PREFERENCE_PLAYER
	default_value = TRUE

/datum/preference/toggle/roof_mask_weather/apply_to_client(client/client, value)
	var/datum/hud/using = client.mob?.hud_used
	if(!using)
		return

	for(var/plane_number in list(WEATHER_PLANE, PARTICLE_WEATHER_PLANE, RENDER_PLANE_PARTICLE_WEATHER))
		for(var/atom/movable/screen/plane_master/plane as anything in using.get_true_plane_masters(plane_number))
			plane.update_roof_mask_filter(value)

/**
 * Adds or removes this plane's roof cutout.
 *
 * Lives on the plane master rather than in the preference so that a plane built after the preference was read -
 * a new HUD, or a client changing z-level - can ask for the same thing without duplicating the filter name and
 * priority in two places.
 */
/atom/movable/screen/plane_master/proc/update_roof_mask_filter(enabled)
	if(!enabled)
		remove_filter("roof_mask")
		return
	if(get_filter("roof_mask"))
		return
	add_filter("roof_mask", 2, alpha_mask_filter(render_source = OFFSET_RENDER_TARGET(ROOF_MASK_RENDER_TARGET, offset), flags = MASK_INVERSE))

/// Reads the preference for whoever owns this plane. Defaults to on for anything with no client to ask.
/atom/movable/screen/plane_master/proc/wants_roof_mask(mob/viewer)
	var/client/asking = viewer?.canon_client
	if(!asking?.prefs)
		return TRUE
	return asking.prefs.read_preference(/datum/preference/toggle/roof_mask_weather)
