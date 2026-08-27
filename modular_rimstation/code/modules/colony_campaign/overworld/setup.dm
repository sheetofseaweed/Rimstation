/**
 * The screen somebody starts a campaign from.
 *
 * A short-lived controller rather than a machine: it exists only while a person is deciding, and is destroyed
 * whether they confirm or walk away. Nothing about it is campaign state - the campaign begins existing at the
 * moment `create_campaign()` succeeds, and not one step earlier.
 *
 * The preview is built through exactly the same path creation uses - same generation planet record, same
 * options, same generator - so what somebody is shown is what they get. A preview that merely resembled the
 * result would be worse than no preview at all.
 */
/datum/campaign_setup
	/// The identifier being typed. Validated on every change rather than only at confirm.
	var/campaign_id = CAMPAIGN_DEFAULT_ID
	/// The three region options, always a valid set.
	var/list/options
	/// The region last previewed, or null if none has been built yet.
	var/datum/overworld_region/preview
	/// TRUE when the options have moved since the preview was drawn.
	var/preview_stale = TRUE
	/// TRUE while a preview is being generated, so a second request cannot pile onto the first.
	var/preview_building = FALSE
	/// Who opened this, recorded as text rather than a client reference.
	var/opened_by
	/// One-shot guard. A campaign is the only copy of its colony, so confirm must never run twice.
	var/consumed = FALSE

/datum/campaign_setup/New(opened_by)
	. = ..()
	src.opened_by = opened_by
	options = default_overworld_options()

/datum/campaign_setup/Destroy(force)
	QDEL_NULL(preview)
	options = null
	return ..()

/datum/campaign_setup/ui_state(mob/user)
	return ADMIN_STATE(R_ADMIN)

/datum/campaign_setup/ui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "CampaignSetup")
		// Nothing here changes on its own; every update follows an action this screen took.
		ui.set_autoupdate(FALSE)
		ui.open()

/// Why this campaign cannot be started right now, or null if it can.
/datum/campaign_setup/proc/blocking_reason()
	if(SScampaign.is_campaign_active())
		return "A campaign is already running on this server."
	if(!get_colony_core())
		return "There is no colony core on this map. A campaign here could be saved but never lost, which is not a campaign."
	if(!CONFIG_GET(flag/persistent_save_enabled))
		return "Persistent saving is disabled in config, so a campaign would have nothing to commit."
	return null

/datum/campaign_setup/ui_data(mob/user)
	var/list/data = list()
	var/blocked = blocking_reason()

	data["campaign_id"] = campaign_id
	data["id_is_usable"] = is_safe_campaign_id(campaign_id)
	data["id_problem"] = is_safe_campaign_id(campaign_id) ? null : "Use letters, digits, dots, dashes and underscores."
	data["options"] = options.Copy()
	data["preview_stale"] = preview_stale
	data["preview_building"] = preview_building
	data["blocked_reason"] = blocked
	data["can_confirm"] = !consumed && !blocked && is_safe_campaign_id(campaign_id)

	data["extent_choices"] = build_choice_list(OVERWORLD_EXTENTS, list(
		OVERWORLD_EXTENT_COMPACT = list("Compact", "A short walk from edge to edge. Journeys stay brief."),
		OVERWORLD_EXTENT_STANDARD = list("Standard", "Room to travel without a trip taking a whole chapter."),
		OVERWORLD_EXTENT_EXPANSIVE = list("Expansive", "Far country. The far side is a serious expedition."),
	))
	data["roughness_choices"] = build_choice_list(OVERWORLD_ROUGHNESS_OPTIONS, list(
		OVERWORLD_ROUGHNESS_GENTLE = list("Gentle", "Mostly open ground, little of it barred, and quieter."),
		OVERWORLD_ROUGHNESS_VARIED = list("Varied", "A mix of easy going and country that has to be worked around."),
		OVERWORLD_ROUGHNESS_RUGGED = list("Rugged", "Hard ground, more of it impassable, and more dangerous."),
	))
	data["abundance_choices"] = build_choice_list(OVERWORLD_ABUNDANCE_OPTIONS, list(
		OVERWORLD_ABUNDANCE_SPARSE = list("Sparse", "Few deposits, and less in each. Every trip has to count."),
		OVERWORLD_ABUNDANCE_NORMAL = list("Normal", "Enough to reward going out without removing the decision."),
		OVERWORLD_ABUNDANCE_RICH = list("Rich", "Plentiful deposits carrying more. Ruins are unaffected."),
	))

	// Preview mode reveals everything: somebody choosing a world should see the world.
	data["radius"] = preview?.radius || 0
	data["fingerprint"] = preview?.fingerprint

	var/list/cells = list()
	var/list/known = list()
	for(var/cell_id in preview?.cells)
		var/datum/overworld_cell/cell = preview.cells[cell_id]
		UNTYPED_LIST_ADD(cells, list(
			"id" = cell_id,
			"q" = cell.q,
			"r" = cell.r,
			"distance" = overworld_axial_distance(0, 0, cell.q, cell.r),
		))
		UNTYPED_LIST_ADD(known, list(
			"id" = cell_id,
			"terrain" = cell.terrain,
			"topology" = cell.topology,
			"danger" = cell.danger,
			"seconds" = cell.traversal_seconds(),
		))
	data["cells"] = cells
	data["known_cells"] = known

	var/list/sites = list()
	for(var/site_id in preview?.sites)
		var/datum/overworld_site/site = preview.sites[site_id]
		UNTYPED_LIST_ADD(sites, list(
			"id" = site_id,
			"kind" = site.kind,
			"cell" = "[site.q],[site.r]",
			"distance" = overworld_axial_distance(0, 0, site.q, site.r),
			"yield" = site.yield,
		))
	data["known_sites"] = sites
	data["resource_site_count"] = length(preview?.sites_of_kind(OVERWORLD_SITE_RESOURCE))
	data["ruin_site_count"] = length(preview?.sites_of_kind(OVERWORLD_SITE_RUIN))
	return data

/// Turns an allowlist plus its copy into the list the interface renders. Labels live here, not in the frontend.
/datum/campaign_setup/proc/build_choice_list(list/ids, list/copy)
	RETURN_TYPE(/list)
	var/list/choices = list()
	for(var/id in ids)
		var/list/text = copy[id]
		UNTYPED_LIST_ADD(choices, list(
			"id" = id,
			"label" = text?[1] || id,
			"detail" = text?[2] || "",
		))
	return choices

/datum/campaign_setup/ui_act(action, list/params, datum/tgui/ui, datum/ui_state/state)
	. = ..()
	if(.)
		return

	switch(action)
		if("set_id")
			// Typed by a person, so it is trimmed and length-bounded before it is ever a directory name.
			var/typed = params["campaign_id"]
			if(!istext(typed))
				return TRUE
			campaign_id = copytext(trim(typed), 1, 33)
			return TRUE

		if("set_option")
			return set_option(params["option"], params["value"])

		if("generate_preview")
			if(preview_building)
				return TRUE
			preview_building = TRUE
			// Generating a region can yield, and ui_act() must never sleep. The push happens when it finishes.
			INVOKE_ASYNC(src, PROC_REF(build_preview))
			return TRUE

		if("confirm")
			return confirm_campaign(usr)

	return FALSE

/**
 * Applies one option, refusing anything that is not on its allowlist.
 *
 * Both the name and the value are checked against the server's own lists rather than trusted, because every
 * value arriving here was chosen by whatever sent the message rather than by the interface being honest.
 */
/datum/campaign_setup/proc/set_option(option, value)
	var/list/allowed
	switch(option)
		if("extent")
			allowed = OVERWORLD_EXTENTS
		if("roughness")
			allowed = OVERWORLD_ROUGHNESS_OPTIONS
		if("abundance")
			allowed = OVERWORLD_ABUNDANCE_OPTIONS
		else
			return TRUE

	if(!(value in allowed))
		return TRUE

	if(options[option] == value)
		return TRUE

	options[option] = value
	// The drawn preview is now of a different world than the one selected, and says so rather than pretending.
	preview_stale = TRUE
	return TRUE

/**
 * Builds the region this campaign would begin on.
 *
 * Uses `build_generation_planet_record()` with generation 1 - the same call `create_campaign()` makes - so the
 * preview and the campaign cannot diverge. Changing the campaign name therefore changes the world, which is
 * true of creation as well and is worth seeing before committing to it.
 */
/datum/campaign_setup/proc/build_preview()
	var/list/planet_record = SScampaign.build_generation_planet_record(campaign_id, 1)
	var/datum/planet_definition/planet = new
	if(!planet.deserialize(planet_record))
		qdel(planet)
		preview_building = FALSE
		SStgui.update_uis(src)
		return FALSE

	QDEL_NULL(preview)
	preview = new(planet, options)
	qdel(planet)

	preview_stale = FALSE
	preview_building = FALSE
	SStgui.update_uis(src)
	return TRUE

/**
 * Starts the campaign, exactly once.
 *
 * The one-shot guard is set before anything is written. A campaign is the only copy of its colony, so a
 * double-submit that created two, or overwrote one, is the single most expensive mistake this screen could make.
 */
/datum/campaign_setup/proc/confirm_campaign(mob/user)
	if(consumed)
		return TRUE

	var/blocked = blocking_reason()
	if(blocked)
		to_chat(user, span_warning(blocked))
		return TRUE

	if(!is_safe_campaign_id(campaign_id))
		to_chat(user, span_warning("'[campaign_id]' cannot be used as a directory name."))
		return TRUE

	consumed = TRUE
	if(!SScampaign.create_campaign(campaign_id, key_name(user), options))
		to_chat(user, span_warning("The campaign could not be started. It may already exist on disk - check the game log."))
		// Released rather than left consumed: nothing was created, so the screen is still usable.
		consumed = FALSE
		SStgui.update_uis(src)
		return TRUE

	message_admins("[key_name_admin(user)] started colony campaign [campaign_id] ([options["extent"]] region, [options["roughness"]] terrain, [options["abundance"]] resources). This round is chapter 1.")
	log_admin("[key_name(user)] started colony campaign [campaign_id].")
	to_chat(user, span_notice("Campaign '[campaign_id]' has begun. This round is chapter one."))

	SStgui.close_uis(src)
	qdel(src)
	return TRUE
