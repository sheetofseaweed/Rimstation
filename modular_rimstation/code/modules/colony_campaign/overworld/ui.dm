/**
 * The table the colony plans expeditions on.
 *
 * Read-only for now: it draws the region and nothing else. Party formation, routing and travel arrive in later
 * tasks, and the map is worth judging before any of them exist - if the region is not legible at a glance
 * there is no point building travel across it.
 *
 * The region itself is derived rather than stored, so this is the only place that decides which region is
 * "the" one and keeps it alive. Rebuilding a few hundred cells per interface open would be wasteful and, more
 * importantly, pointless: the same inputs always produce the same region.
 */

/// The region currently being played, rebuilt only when the inputs behind it change.
GLOBAL_DATUM(active_overworld_region, /datum/overworld_region)
/// What the cached region above was built from, so a changed planet or option set invalidates it.
GLOBAL_VAR(active_overworld_signature)

/**
 * The region for the running campaign, or a fixed development one when no campaign exists.
 *
 * The development fallback exists so the map can be opened and judged on an ordinary round. It is deliberately
 * a fixed seed rather than a random one: a map that looks different every time you open it cannot be reviewed.
 */
/proc/get_active_overworld_region()
	RETURN_TYPE(/datum/overworld_region)
	var/datum/campaign_manifest/manifest = SScampaign.manifest
	var/datum/overworld_state/region_state = SScampaign.get_overworld_state()
	var/list/options = region_state?.options || default_overworld_options()

	var/datum/planet_definition/planet
	if(length(manifest?.planet_record))
		planet = new
		if(!planet.deserialize(manifest.planet_record))
			QDEL_NULL(planet)

	if(!planet)
		// No campaign, or an unreadable planet record. Either way the map still has to draw something.
		planet = new("rimstation-development-region", "development-planet")

	var/signature = "[planet.root_seed]:[options["extent"]]:[options["roughness"]]:[options["abundance"]]:[OVERWORLD_GENERATION_VERSION]"
	if(GLOB.active_overworld_region && GLOB.active_overworld_signature == signature)
		qdel(planet)
		return GLOB.active_overworld_region

	QDEL_NULL(GLOB.active_overworld_region)
	GLOB.active_overworld_region = new(planet, options)
	GLOB.active_overworld_signature = signature
	qdel(planet)
	return GLOB.active_overworld_region

/**
 * Which cells the colony can currently see.
 *
 * Task 1 has no stored discovery, so this is the initial reveal every colony starts with. Persistent discovery
 * replaces the body of this proc without changing anything that calls it.
 */
/proc/get_discovered_cell_ids(datum/overworld_region/region)
	RETURN_TYPE(/list)
	var/list/discovered = list()
	if(!region)
		return discovered

	// A running campaign knows what it has walked. Without one the map still has to show something, so it
	// falls back to what any colony can see from its own doorstep.
	var/datum/overworld_state/region_state = SScampaign.get_overworld_state()
	if(region_state)
		return region_state.discovered_cells.Copy()

	for(var/cell_id in region.cells)
		var/datum/overworld_cell/cell = region.cells[cell_id]
		if(overworld_axial_distance(0, 0, cell.q, cell.r) <= OVERWORLD_INITIAL_REVEAL_RADIUS)
			discovered[cell_id] = TRUE
	return discovered


/// Every expedition table that exists, so a discovery can refresh the ones people are looking at.
GLOBAL_LIST_EMPTY(colony_overworld_consoles)

/obj/machinery/computer/colony_overworld
	name = "expedition table"
	desc = "A lit table showing the country around the settlement. Somebody has scratched distances into the frame."
	icon_screen = "mining"
	icon_keyboard = "med_key"
	circuit = /obj/item/circuitboard/computer/colony_overworld
	light_color = LIGHT_COLOR_DIM_YELLOW
	/// The site somebody is currently looking at, so both route offers can be priced for it. Per table, and
	/// never persisted: it is where a player's attention is, not a fact about the colony.
	var/previewed_site_id

/obj/item/circuitboard/computer/colony_overworld
	name = "Expedition Table (Computer Board)"
	greyscale_colors = CIRCUIT_COLOR_GENERIC
	build_path = /obj/machinery/computer/colony_overworld

/obj/machinery/computer/colony_overworld/ui_interact(mob/user, datum/tgui/ui)
	. = ..()
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "ColonyOverworld", name)
		// The region does not change on its own, and the payload is a few hundred cells. Pushing on change
		// costs nothing; rebuilding this every tick for every viewer would cost a great deal.
		ui.set_autoupdate(FALSE)
		ui.open()

/**
 * The region's shape and vocabulary: everything that cannot change while the map is open.
 *
 * Every cell's coordinates are sent, because the field's outline is not a secret - the player can see how far
 * the region extends. What is in each cell is not sent here; that belongs to ui_data(), which only describes
 * cells the colony has actually seen.
 */
/obj/machinery/computer/colony_overworld/ui_static_data(mob/user)
	var/list/data = list()
	var/datum/overworld_region/region = get_active_overworld_region()

	data["radius"] = region?.radius || 0
	data["options"] = region?.options?.Copy() || list()
	data["fingerprint"] = region?.fingerprint

	var/list/cells = list()
	for(var/cell_id in region?.cells)
		var/datum/overworld_cell/cell = region.cells[cell_id]
		UNTYPED_LIST_ADD(cells, list(
			"id" = cell_id,
			"q" = cell.q,
			"r" = cell.r,
			"distance" = overworld_axial_distance(0, 0, cell.q, cell.r),
		))
	data["cells"] = cells

	// Sent so the interface can label and colour without inventing its own vocabulary or receiving CSS from DM.
	data["terrain_names"] = list(
		OVERWORLD_TERRAIN_FROZEN_STEPPE = "frozen steppe",
		OVERWORLD_TERRAIN_TUNDRA = "tundra",
		OVERWORLD_TERRAIN_TAIGA = "taiga",
		OVERWORLD_TERRAIN_SCRUBLAND = "scrubland",
		OVERWORLD_TERRAIN_GRASSLAND = "grassland",
		OVERWORLD_TERRAIN_FOREST = "forest",
		OVERWORLD_TERRAIN_DESERT = "desert",
		OVERWORLD_TERRAIN_SAVANNA = "savanna",
		OVERWORLD_TERRAIN_MARSH = "marsh",
	)
	data["topology_names"] = list(
		OVERWORLD_TOPOLOGY_EASY = "open ground",
		OVERWORLD_TOPOLOGY_NORMAL = "broken ground",
		OVERWORLD_TOPOLOGY_DIFFICULT = "hard going",
		OVERWORLD_TOPOLOGY_IMPASSABLE = "impassable",
	)
	return data

/**
 * What the colony currently knows.
 *
 * Undiscovered cells contribute nothing at all - not their terrain, not their cost, not whether something is
 * standing on them. Sending hidden facts and trusting the interface not to draw them would make the fog a
 * rendering choice rather than a rule.
 */
/obj/machinery/computer/colony_overworld/ui_data(mob/user)
	var/list/data = list()
	var/datum/overworld_region/region = get_active_overworld_region()
	var/list/discovered = get_discovered_cell_ids(region)

	var/list/known = list()
	for(var/cell_id in discovered)
		var/datum/overworld_cell/cell = region.cells[cell_id]
		if(!cell)
			continue
		UNTYPED_LIST_ADD(known, list(
			"id" = cell_id,
			"terrain" = cell.terrain,
			"topology" = cell.topology,
			"danger" = cell.danger,
			"seconds" = cell.traversal_seconds(),
		))
	data["known_cells"] = known

	var/list/known_sites = list()
	for(var/site_id in region?.sites)
		var/datum/overworld_site/site = region.sites[site_id]
		if(!discovered["[site.q],[site.r]"])
			continue
		UNTYPED_LIST_ADD(known_sites, list(
			"id" = site_id,
			"kind" = site.kind,
			"cell" = "[site.q],[site.r]",
			"distance" = overworld_axial_distance(0, 0, site.q, site.r),
			"yield" = site.yield,
		))
	data["known_sites"] = known_sites

	data["campaign"] = SScampaign.manifest?.campaign_id
	data["chapter"] = SScampaign.manifest?.chapter
	// The colony's books. Every expedition spends and earns against these, so the table that plans journeys is
	// the obvious place to be able to read them.
	data["ledger"] = SScampaign.get_ledger()?.build_readout()
	data["campaign_clock"] = SScampaign.get_campaign_time()
	data["colony_under_attack"] = is_colony_raid_running()

	// Who is standing at the table decides what they are allowed to do with it. Everything below is about this
	// one colonist, so a second person reading over their shoulder sees their own buttons rather than theirs.
	var/datum/colonist_record/viewer = SScampaign.get_colonist_record_for_body(user)
	data["viewer_colonist_id"] = viewer?.colonist_id
	data["viewer_is_colonist"] = !isnull(viewer)
	data["viewer_has_locker"] = viewer ? !isnull(get_personal_colonist_locker(viewer.colonist_id)) : FALSE

	data["previewed_site_id"] = previewed_site_id
	data["party"] = build_party_payload(region, discovered, viewer)
	data["route_offers"] = build_route_offers(region, discovered)
	return data

/**
 * The expedition as the table shows it, or null when there is not one.
 *
 * Names rather than ids wherever a person is shown: a colonist id is how the campaign refers to somebody, not
 * how anybody at the table does.
 */
/obj/machinery/computer/colony_overworld/proc/build_party_payload(datum/overworld_region/region, list/discovered, datum/colonist_record/viewer)
	RETURN_TYPE(/list)
	var/datum/overworld_party/party = SScampaign.get_active_party()
	if(!party)
		return null

	var/datum/colonist_roster/roster = SScampaign.get_roster()
	var/list/members = list()
	for(var/colonist_id in party.member_ids)
		var/datum/colonist_record/record = roster?.get_record(colonist_id)
		var/mob/living/body = SScampaign.get_colonist_body(colonist_id)
		UNTYPED_LIST_ADD(members, list(
			"id" = colonist_id,
			"name" = record?.display_name || colonist_id,
			"ready" = (colonist_id in party.ready_member_ids),
			"present" = !isnull(body) && body.stat != DEAD,
			"has_locker" = !isnull(get_personal_colonist_locker(colonist_id)),
			"is_you" = (colonist_id == viewer?.colonist_id),
		))

	var/datum/overworld_site/destination = region?.sites[party.destination_site_id]
	return list(
		"party_id" = party.party_id,
		"state" = party.state,
		"is_planning" = party.is_planning(),
		"members" = members,
		"max_members" = OVERWORLD_PARTY_MAX_MEMBERS,
		"everyone_ready" = party.everyone_ready(),
		"destination_site_id" = party.destination_site_id,
		"destination_cell" = destination ? "[destination.q],[destination.r]" : null,
		"route" = party.route.Copy(),
		"route_kind" = party.route_kind,
		"travel_seconds" = region?.route_travel_seconds(party.route) || 0,
		"route_danger" = region?.route_danger(party.route) || 0,
		"supply_cost" = party.supply_cost(),
		// Counted off the larder rather than read out of the ledger, because the larder is what somebody just
		// put food into and the number beside the button has to move when they do.
		"supplies_held" = count_colony_food(),
		"supplies_shortfall_price" = colony_food_shortfall_price(party.supply_cost()),
		"has_larder" = !isnull(get_colony_larder()),
		"current_cell" = party.current_cell,
		"next_cell" = party.leg_target_cell(),
		"leg_started_at" = party.leg_started_at,
		"leg_arrives_at" = party.leg_arrives_at,
		"clock_now" = SScampaign.get_campaign_time(),
		"supplies_carried" = party.supplies,
		"pending_decision" = party.pending_decision?.Copy(),
		"gathered_ids" = party_members_at_post(party),
		"has_hitching_post" = !isnull(get_caravan_hitching_post()),
		"gather_radius" = OVERWORLD_GATHER_RADIUS,
		"you_are_a_member" = viewer ? (viewer.colonist_id in party.member_ids) : FALSE,
		"you_are_ready" = viewer ? (viewer.colonist_id in party.ready_member_ids) : FALSE,
		"join_problem" = viewer ? party.joining_problem(viewer.colonist_id) : "You are not one of this colony's colonists.",
		"departure_problem" = party.departure_problem(region, discovered),
	)

/**
 * Both ways of getting to whatever is being looked at, priced.
 *
 * Computed here and only here. The interface never sends a route or a total back - it names a site and picks
 * one of these two answers, so nothing a client says can inflate what a journey pays or shorten what it costs.
 */
/obj/machinery/computer/colony_overworld/proc/build_route_offers(datum/overworld_region/region, list/discovered)
	RETURN_TYPE(/list)
	var/list/offers = list()
	var/datum/overworld_site/site = region?.sites[previewed_site_id]
	if(!site)
		return offers

	var/datum/overworld_party/party = SScampaign.get_active_party()
	var/from_cell = party?.current_cell || "0,0"
	var/heads = max(1, length(party?.member_ids))
	var/list/kinds = OVERWORLD_ROUTE_KINDS

	for(var/kind in kinds)
		var/list/route = region.plan_route(from_cell, "[site.q],[site.r]", kind, discovered)
		if(length(route) < 2)
			continue
		var/edges = length(route) - 1
		UNTYPED_LIST_ADD(offers, list(
			"kind" = kind,
			"route" = route,
			"steps" = edges,
			"travel_seconds" = region.route_travel_seconds(route),
			"danger" = region.route_danger(route),
			// Priced for who is signed on now, so the number moves as people join rather than after departure.
			"supply_cost" = ((OVERWORLD_SUPPLY_PER_EDGE * edges) + OVERWORLD_SUPPLY_RESERVE) * heads,
		))
	return offers

/**
 * Everything a person can do at the table.
 *
 * Nothing here takes a colonist id from the message. Who is acting is whoever is standing at the table, which
 * is what stops one player signing another one up for a journey, or marking them ready to leave.
 */
/obj/machinery/computer/colony_overworld/ui_act(action, list/params, datum/tgui/ui, datum/ui_state/state)
	. = ..()
	if(.)
		return

	var/mob/living/actor = usr
	var/datum/overworld_region/region = get_active_overworld_region()
	var/list/discovered = get_discovered_cell_ids(region)
	var/datum/colonist_record/viewer = SScampaign.get_colonist_record_for_body(actor)
	var/datum/overworld_party/party = SScampaign.get_active_party()

	switch(action)
		if("preview_site")
			// Looking is free, and looking at nothing clears it. Validated anyway so the offer builder is never
			// handed a site id that came from outside the region.
			var/wanted = params["site_id"]
			previewed_site_id = (istext(wanted) && region?.sites[wanted]) ? wanted : null
			return TRUE

		if("form_party")
			if(party)
				return TRUE
			if(!SScampaign.form_party())
				to_chat(actor, span_warning("This colony has no campaign to send an expedition for."))
			return TRUE

		if("join")
			if(!party || !viewer)
				return TRUE
			var/problem = party.joining_problem(viewer.colonist_id)
			if(problem)
				to_chat(actor, span_warning(problem))
				return TRUE
			if(party.add_member(viewer.colonist_id))
				party.log_membership(viewer, "signed on")
				SScampaign.commit_party_change()
			return TRUE

		if("leave")
			if(!party || !viewer)
				return TRUE
			if(party.remove_member(viewer.colonist_id))
				party.log_membership(viewer, "withdrew from")
				SScampaign.commit_party_change()
			return TRUE

		if("set_ready")
			if(!party || !viewer)
				return TRUE
			var/wants_ready = !!params["ready"]
			if(party.set_ready(viewer.colonist_id, wants_ready))
				SScampaign.commit_party_change()
			else if(wants_ready)
				to_chat(actor, span_warning("There is no route to be ready for yet."))
			return TRUE

		if("choose_route")
			if(!party || !previewed_site_id)
				return TRUE
			if(!party.is_planning())
				to_chat(actor, span_warning("The expedition has already left."))
				return TRUE
			var/kind = params["kind"]
			if(!(kind in OVERWORLD_ROUTE_KINDS))
				return TRUE
			if(!party.set_destination(region, previewed_site_id, kind, discovered))
				to_chat(actor, span_warning("There is no way there that the colony has walked."))
				return TRUE
			SScampaign.commit_party_change()
			return TRUE

		if("clear_route")
			if(!party)
				return TRUE
			if(party.clear_destination("somebody changed the plan"))
				SScampaign.commit_party_change()
			return TRUE

		if("disband")
			// Anybody on it may call it off while it is still gathering. Nothing has been spent yet - the food is
			// debited at departure - so this costs the colony nothing but the walk back to the table.
			if(!party || !viewer)
				return TRUE
			if(!party.is_planning())
				to_chat(actor, span_warning("The expedition has already left."))
				return TRUE
			if(!(viewer.colonist_id in party.member_ids))
				to_chat(actor, span_warning("You are not on this expedition."))
				return TRUE

			party.set_state(OVERWORLD_PARTY_LOST, "[viewer.display_name] called the muster off")
			SScampaign.overworld?.clear_party("the muster was called off")
			SScampaign.commit_party_change()
			to_chat(actor, span_notice("You call the muster off. Everyone signed on is stood down."))
			return TRUE

		if("answer_decision")
			// Any member may answer, and the first answer wins. Waiting on one nominated leader is how a party
			// gets stranded at a boundary by somebody's connection dropping.
			if(!party || !viewer)
				return TRUE
			if(!(viewer.colonist_id in party.member_ids))
				to_chat(actor, span_warning("You are not on this expedition."))
				return TRUE

			var/refused = SSoverworld.answer_decision(party, params["decision_id"], params["choice"], actor)
			if(refused)
				to_chat(actor, span_warning(refused))
			return TRUE

		if("head_home")
			// Any member may call the trip. Waiting on one nominated leader is how a party gets stranded by a
			// disconnect, so the first person to say so decides for everybody.
			if(!party || !viewer)
				return TRUE
			if(!(viewer.colonist_id in party.member_ids))
				to_chat(actor, span_warning("You are not on this expedition."))
				return TRUE
			if(party.state != OVERWORLD_PARTY_AT_SITE)
				to_chat(actor, span_warning("The expedition is not standing anywhere it can leave from."))
				return TRUE
			if(!party.begin_return("[viewer.display_name] called the expedition home"))
				return TRUE

			// Onto the road properly, rather than standing around the site they have finished with.
			INVOKE_ASYNC(SSoverworld, TYPE_PROC_REF(/datum/controller/subsystem/overworld, board_for_return), party.party_id)

			var/datum/overworld_region/home_region = get_active_overworld_region()
			SSoverworld.schedule_leg(party, home_region)
			SScampaign.commit_party_change()
			return TRUE

	return FALSE

/obj/machinery/computer/colony_overworld/Initialize(mapload)
	. = ..()
	GLOB.colony_overworld_consoles += src

/obj/machinery/computer/colony_overworld/Destroy()
	GLOB.colony_overworld_consoles -= src
	return ..()
