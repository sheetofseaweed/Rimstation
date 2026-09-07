/**
 * Reveals the whole region, or everything within a radius of a cell.
 *
 * The existing single-cell verb reveals one hex and its neighbours, which is the right shape for testing a
 * discovery but the wrong one for setting up a scenario. Revealing the map is the common case by a long way.
 */
ADMIN_VERB(rimstation_reveal_overworld_region, R_ADMIN, "Reveal Colony Region", "Marks the whole region, or a radius of it, as discovered.", ADMIN_CATEGORY_COLONY)
	var/datum/overworld_state/region_state = SScampaign.get_overworld_state()
	var/datum/overworld_region/region = get_active_overworld_region()
	if(!region_state || !region)
		to_chat(user, span_warning("No campaign is loaded, so there is no region to reveal."))
		return

	var/list/how = list("The whole region" = "all", "A radius around one cell" = "radius")
	var/scope = tgui_input_list(user, "How much should be revealed?", "Colony Region", how)
	if(isnull(scope))
		return

	var/revealed = 0
	if(how[scope] == "all")
		for(var/cell_id in region.cells)
			if(region_state.discover_cell(region, cell_id))
				revealed++
	else
		var/cell_id = tgui_input_text(user, "Which cell, as q,r?", "Colony Region", "0,0", max_length = 16)
		if(!cell_id)
			return
		if(!region.cells[cell_id])
			to_chat(user, span_warning("There is no cell '[cell_id]' in this region."))
			return
		var/radius = tgui_input_number(user, "Radius in cells", "Colony Region", default = 2, max_value = region.radius, min_value = 0, round_value = TRUE)
		if(isnull(radius))
			return
		revealed = region_state.discover_radius(region, cell_id, radius)

	SScampaign.sync_overworld()
	SScampaign.refresh_overworld_consoles()

	message_admins("[key_name_admin(user)] revealed [revealed] overworld cells.")
	log_admin("[key_name(user)] revealed [revealed] overworld cells.")
	to_chat(user, span_notice("Revealed [revealed] cells. The region has [length(region.cells)] in total."))


/**
 * Edits one cell of the generated map, and makes the edit outlive the chapter.
 *
 * The region is not saved - it is rebuilt from the planet seed whenever anything asks for it - so an edit made
 * to the live cell would last until the next rebuild and no further. What is stored is the edit itself, laid
 * back over every build, which is why this is worth having at all.
 */
ADMIN_VERB(rimstation_edit_overworld_cell, R_ADMIN, "Edit Colony Region Cell", "Changes a cell's terrain, topology or danger, and keeps the change.", ADMIN_CATEGORY_COLONY)
	var/datum/overworld_state/region_state = SScampaign.get_overworld_state()
	var/datum/overworld_region/region = get_active_overworld_region()
	if(!region_state || !region)
		to_chat(user, span_warning("No campaign is loaded, so there is no region to edit."))
		return

	var/cell_id = tgui_input_text(user, "Which cell, as q,r?", "Colony Region", "0,0", max_length = 16)
	if(!cell_id)
		return

	var/datum/overworld_cell/cell = region.cells[cell_id]
	if(!cell)
		to_chat(user, span_warning("There is no cell '[cell_id]' in this region. It runs to radius [region.radius]."))
		return

	to_chat(user, span_notice("Cell [cell_id]: terrain [cell.terrain], topology [cell.topology], danger [cell.danger]."))

	var/list/terrains = list("Leave as it is" = null) + OVERWORLD_TERRAINS
	var/terrain = tgui_input_list(user, "Terrain", "Colony Region", terrains)
	if(isnull(terrain))
		return
	terrain = (terrain == "Leave as it is") ? null : terrain

	var/list/topologies = list("Leave as it is") + OVERWORLD_TOPOLOGY_COSTS
	var/topology = tgui_input_list(user, "Topology", "Colony Region", topologies)
	if(isnull(topology))
		return
	topology = (topology == "Leave as it is") ? null : topology

	var/danger = tgui_input_number(user, "Danger (0-[OVERWORLD_MAX_CELL_DANGER])", "Colony Region", default = cell.danger, max_value = OVERWORLD_MAX_CELL_DANGER, min_value = 0, round_value = TRUE)
	if(isnull(danger))
		return

	if(!region_state.set_cell_override(region, cell_id, terrain, topology, danger))
		to_chat(user, span_warning("Nothing about that edit was usable, so the cell was left alone."))
		return

	SScampaign.sync_overworld()
	SScampaign.refresh_overworld_consoles()

	message_admins("[key_name_admin(user)] edited overworld cell [cell_id]: terrain [cell.terrain], topology [cell.topology], danger [cell.danger].")
	log_admin("[key_name(user)] edited overworld cell [cell_id].")
	to_chat(user, span_notice("Cell [cell_id] is now terrain [cell.terrain], topology [cell.topology], danger [cell.danger]. The edit will survive a reload."))


/// Hands a cell back to the generator, dropping whatever was edited into it.
ADMIN_VERB(rimstation_clear_overworld_cell_edit, R_ADMIN, "Clear Colony Region Cell Edit", "Drops an admin edit, letting the generator decide that cell again.", ADMIN_CATEGORY_COLONY_DEBUG)
	var/datum/overworld_state/region_state = SScampaign.get_overworld_state()
	if(!region_state)
		to_chat(user, span_warning("No campaign is loaded."))
		return

	if(!length(region_state.cell_overrides))
		to_chat(user, span_notice("No cells have been edited."))
		return

	var/cell_id = tgui_input_list(user, "Which edit should be dropped?", "Colony Region", region_state.cell_overrides)
	if(isnull(cell_id))
		return

	if(!region_state.clear_cell_override(get_active_overworld_region(), cell_id))
		to_chat(user, span_warning("Cell [cell_id] had no edit on it."))
		return

	// The generator's own value only comes back on a rebuild, and the cached region is not one. Dropping the
	// cache is what makes the next reader see the unedited cell rather than the edit that was just removed.
	QDEL_NULL(GLOB.active_overworld_region)
	GLOB.active_overworld_signature = null
	SScampaign.sync_overworld()
	SScampaign.refresh_overworld_consoles()

	message_admins("[key_name_admin(user)] dropped the admin edit on overworld cell [cell_id].")
	log_admin("[key_name(user)] dropped the admin edit on overworld cell [cell_id].")


/**
 * Puts a site on the map that the generator did not.
 *
 * Ranked above anything generation reaches, so a placed site can never take a generated one's identity - and
 * with it whatever play had already done to that site.
 */
ADMIN_VERB(rimstation_spawn_overworld_site, R_ADMIN, "Spawn Colony Region Site", "Places a resource or ruin site on a chosen cell, and keeps it.", ADMIN_CATEGORY_COLONY)
	var/datum/overworld_state/region_state = SScampaign.get_overworld_state()
	var/datum/overworld_region/region = get_active_overworld_region()
	if(!region_state || !region)
		to_chat(user, span_warning("No campaign is loaded, so there is no region to place a site on."))
		return

	var/kind = tgui_input_list(user, "What kind of site?", "Colony Region", OVERWORLD_SITE_KINDS)
	if(isnull(kind))
		return

	var/cell_id = tgui_input_text(user, "Which cell, as q,r?", "Colony Region", "0,0", max_length = 16)
	if(!cell_id)
		return
	var/datum/overworld_cell/cell = region.cells[cell_id]
	if(!cell)
		to_chat(user, span_warning("There is no cell '[cell_id]' in this region."))
		return

	var/site_yield = 0
	if(kind == OVERWORLD_SITE_RESOURCE)
		site_yield = tgui_input_number(user, "Ledger units this site pays out", "Colony Region", default = 40, max_value = 10000, min_value = 0, round_value = TRUE)
		if(isnull(site_yield))
			return

	var/site_id = region_state.add_site(region, kind, cell.q, cell.r, site_yield)
	if(!site_id)
		to_chat(user, span_warning("That site could not be placed."))
		return

	SScampaign.sync_overworld()
	SScampaign.refresh_overworld_consoles()

	message_admins("[key_name_admin(user)] placed overworld site [site_id] at [cell_id].")
	log_admin("[key_name(user)] placed overworld site [site_id] at [cell_id].")
	to_chat(user, span_notice("Placed [site_id] at [cell_id]. It will survive a reload."))


/**
 * Marks a site available, resolved or depleted.
 *
 * This is also how a site is retired: depleting one is what play does to a site that is finished with, and a
 * generated site cannot be deleted because the generator would put it straight back on the next build.
 */
ADMIN_VERB(rimstation_set_overworld_site_state, R_ADMIN, "Set Colony Region Site State", "Marks a site as available, resolved or depleted.", ADMIN_CATEGORY_COLONY)
	var/datum/overworld_state/region_state = SScampaign.get_overworld_state()
	var/datum/overworld_region/region = get_active_overworld_region()
	if(!region_state || !region)
		to_chat(user, span_warning("No campaign is loaded, so there are no sites."))
		return

	if(!length(region.sites))
		to_chat(user, span_warning("This region has no sites."))
		return

	var/list/choices = list()
	for(var/site_id in region.sites)
		var/datum/overworld_site/site = region.sites[site_id]
		choices["[site_id] at [site.q],[site.r] - [region_state.get_site_state(site_id)]"] = site_id

	var/chosen = tgui_input_list(user, "Which site?", "Colony Region", choices)
	if(isnull(chosen))
		return
	var/site_id = choices[chosen]

	var/new_state = tgui_input_list(user, "What state should [site_id] be in?", "Colony Region", OVERWORLD_SITE_STATES)
	if(isnull(new_state))
		return

	if(!region_state.set_site_state(region, site_id, new_state, "set by [key_name(user)]"))
		to_chat(user, span_warning("[site_id] could not be set to '[new_state]'."))
		return

	SScampaign.sync_overworld()
	SScampaign.refresh_overworld_consoles()

	message_admins("[key_name_admin(user)] set overworld site [site_id] to [new_state].")
	log_admin("[key_name(user)] set overworld site [site_id] to [new_state].")


/// Reports the region as it currently stands, edits included, without changing any of it.
ADMIN_VERB(rimstation_inspect_overworld_region, R_ADMIN, "Inspect Colony Region", "Reports the region's size, sites, discoveries and admin edits.", ADMIN_CATEGORY_COLONY_DEBUG)
	var/datum/overworld_state/region_state = SScampaign.get_overworld_state()
	var/datum/overworld_region/region = get_active_overworld_region()
	if(!region_state || !region)
		to_chat(user, span_warning("No campaign is loaded, so there is no region."))
		return

	var/list/lines = list()
	lines += "Region radius [region.radius], [length(region.cells)] cells, [length(region.sites)] sites."
	lines += "Options: extent [region.options["extent"]], roughness [region.options["roughness"]], abundance [region.options["abundance"]]."
	lines += "Generator fingerprint: [region.fingerprint]."
	lines += "Discovered: [length(region_state.discovered_cells)] cells."
	lines += "Admin edits: [length(region_state.cell_overrides)] cells, [length(region_state.added_sites)] placed sites."
	lines += "---"

	for(var/site_id in region.sites)
		var/datum/overworld_site/site = region.sites[site_id]
		var/placed = region_state.added_sites[site_id] ? " (placed)" : ""
		lines += "[site_id] at [site.q],[site.r] - [region_state.get_site_state(site_id)], yield [site.yield][placed]"

	if(length(region_state.cell_overrides))
		lines += "---"
		for(var/cell_id in region_state.cell_overrides)
			var/list/edit = region_state.cell_overrides[cell_id]
			var/list/parts = list()
			for(var/field in edit)
				parts += "[field] [edit[field]]"
			lines += "Edited [cell_id]: [parts.Join(", ")]"

	to_chat(user, boxed_message(span_notice(lines.Join("\n"))))
