/**
 * What play has done to the region, and nothing else.
 *
 * The region itself is derived from the planet and the creation options, so none of it is stored: not the
 * cells, not their terrain, not where the sites are. What cannot be derived is what people did - which ground
 * they have walked, which deposits they have emptied - and that is all this holds.
 *
 * The consequence worth stating plainly: this record is meaningless without the region it describes. Cell and
 * site ids are only stable while the generator is, which is why the generator version is stored alongside them
 * and why a record from a newer one is refused rather than reinterpreted.
 */
/datum/overworld_state
	var/schema_version = COLONY_OVERWORLD_SCHEMA_VERSION
	/// Which generator built the region these ids refer to.
	var/generation_version = OVERWORLD_GENERATION_VERSION
	/// The three validated creation options. The region is rebuilt from these plus the planet.
	var/list/options
	/// Cell ids the colony has seen, as an assoc set.
	var/list/discovered_cells
	/// Site id to a plain list describing what play changed. Untouched sites are absent.
	var/list/site_states
	/// The fingerprint of the region this state was last saved against. Diagnostic only; drift is logged.
	var/region_fingerprint
	/**
	 * Admin edits to the generated cells, keyed by cell id. Only the fields actually changed are stored.
	 *
	 * The region is rebuilt from the planet seed every time it is asked for rather than saved, so an edit made
	 * to the live region would last until the next rebuild and no longer. These are re-applied on top of every
	 * build, which is what makes an admin's change to the map outlive the chapter it was made in.
	 */
	var/list/cell_overrides
	/// Sites an admin placed that the generator did not, keyed by site id. Same reason as above.
	var/list/added_sites
	/// The expedition currently out or being assembled, or null. At most one at a time, on purpose.
	var/datum/overworld_party/active_party
	/// Issues party ids. Monotonic and never rewound, so a finished journey's id is never reused by a later one.
	var/next_party_number = 1
	/// Issues decision ids, on the same terms. An answer names the question it answers, so the ids must be unique.
	var/next_decision_number = 1

/datum/overworld_state/New(list/starting_options)
	. = ..()
	options = (is_valid_overworld_options(starting_options) ? starting_options.Copy() : default_overworld_options())
	discovered_cells = list()
	site_states = list()
	cell_overrides = list()
	added_sites = list()

/datum/overworld_state/Destroy(force)
	QDEL_NULL(active_party)
	options = null
	discovered_cells = null
	site_states = null
	cell_overrides = null
	added_sites = null
	return ..()

/**
 * Starts assembling an expedition, if one is not already under way.
 *
 * Refuses rather than replaces. The party that exists may have people standing in it, or be halfway across the
 * region, and quietly building a second one over the top is how a caravan full of colonists stops existing.
 */
/datum/overworld_state/proc/create_party()
	RETURN_TYPE(/datum/overworld_party)
	if(active_party)
		return null

	active_party = new("party-[next_party_number]")
	next_party_number++
	return active_party

/**
 * Drops the finished party, freeing the slot for the next one.
 *
 * Only for parties that have actually ended. A party still on the road is people who are somewhere, and
 * forgetting it here would strand them with nothing tracking their way home.
 */
/datum/overworld_state/proc/clear_party(reason)
	if(!active_party)
		return FALSE
	if(!(active_party.state in OVERWORLD_PARTY_TERMINAL_STATES))
		return FALSE

	log_game("Overworld cleared party [active_party.party_id]([reason || "no reason"]).")
	QDEL_NULL(active_party)
	return TRUE

/**
 * Reveals the colony's own surroundings.
 *
 * Called once, when a campaign first gains a region. Everything past this radius is walked to.
 */
/datum/overworld_state/proc/reveal_initial(datum/overworld_region/region)
	if(!region)
		return 0

	var/revealed = 0
	for(var/cell_id in region.cells)
		var/datum/overworld_cell/cell = region.cells[cell_id]
		if(overworld_axial_distance(0, 0, cell.q, cell.r) > OVERWORLD_INITIAL_REVEAL_RADIUS)
			continue
		if(discover_cell(region, cell_id))
			revealed++
	return revealed

/**
 * Marks one cell as seen. Returns TRUE only if this call is what revealed it.
 *
 * Validated against the generated region rather than accepted on faith: a cell id that does not exist would
 * be a discovery of nowhere, and would survive in the record long after anyone could work out what it meant.
 */
/datum/overworld_state/proc/discover_cell(datum/overworld_region/region, cell_id)
	if(!region?.cells[cell_id])
		return FALSE
	if(discovered_cells[cell_id])
		return FALSE

	discovered_cells[cell_id] = TRUE
	return TRUE

/// Reveals a cell and the ring around it, which is what entering somewhere actually shows you.
/datum/overworld_state/proc/discover_around(datum/overworld_region/region, cell_id)
	var/datum/overworld_cell/centre = region?.cells[cell_id]
	if(!centre)
		return 0

	var/revealed = discover_cell(region, cell_id) ? 1 : 0
	var/list/directions = OVERWORLD_AXIAL_DIRECTIONS
	for(var/list/step as anything in directions)
		var/datum/overworld_cell/neighbour = region.get_cell(centre.q + step[1], centre.r + step[2])
		if(neighbour && discover_cell(region, neighbour.cell_id()))
			revealed++
	return revealed

/// TRUE when the colony has seen this cell.
/datum/overworld_state/proc/is_discovered(cell_id)
	return !isnull(discovered_cells[cell_id])

/**
 * Reveals everything within a given distance of a cell. Returns how many were newly seen.
 *
 * What a party standing somewhere and looking properly can take in, as opposed to the single ring that simply
 * passing through reveals. Walks the whole field rather than the ring, because at radius two the neighbours of
 * neighbours overlap and counting them by hand is where hex maths goes wrong.
 */
/datum/overworld_state/proc/discover_radius(datum/overworld_region/region, cell_id, radius)
	var/datum/overworld_cell/centre = region?.cells[cell_id]
	if(!centre)
		return 0

	var/revealed = 0
	for(var/candidate_id in region.cells)
		var/datum/overworld_cell/cell = region.cells[candidate_id]
		if(overworld_axial_distance(centre.q, centre.r, cell.q, cell.r) > radius)
			continue
		if(discover_cell(region, candidate_id))
			revealed++
	return revealed

/**
 * Records that play changed a site. Returns TRUE if the record now says so.
 *
 * Only changed sites are stored, so setting a site back to available removes its entry rather than writing
 * "available" - the absence of a record is what untouched means.
 */
/datum/overworld_state/proc/set_site_state(datum/overworld_region/region, site_id, new_state, reason)
	if(!region?.sites[site_id])
		return FALSE

	var/list/known_states = OVERWORLD_SITE_STATES
	if(!(new_state in known_states))
		return FALSE

	if(new_state == OVERWORLD_SITE_STATE_AVAILABLE)
		site_states -= site_id
		return TRUE

	site_states[site_id] = list(
		"state" = new_state,
		"reason" = reason,
	)
	return TRUE

/// What play has left this site as. Untouched sites report available.
/datum/overworld_state/proc/get_site_state(site_id)
	var/list/record = site_states[site_id]
	return record?["state"] || OVERWORLD_SITE_STATE_AVAILABLE

/**
 * Records an admin edit to one cell. Null fields are left as the generator made them.
 *
 * Returns TRUE if anything was recorded. Values are checked here rather than at the verb, because this record
 * goes to disk and comes back from it - a hand-edited file must not be able to hand the map a topology with no
 * traversal cost, which would make the cell silently free to cross.
 */
/datum/overworld_state/proc/set_cell_override(datum/overworld_region/region, cell_id, terrain, topology, danger)
	var/datum/overworld_cell/cell = region?.cells[cell_id]
	if(!cell)
		return FALSE

	var/list/edit = cell_overrides[cell_id] || list()
	var/list/terrains = OVERWORLD_TERRAINS
	var/list/costs = OVERWORLD_TOPOLOGY_COSTS

	if(terrain && (terrain in terrains))
		edit["terrain"] = terrain
	if(topology && (topology in costs))
		edit["topology"] = topology
	if(isnum(danger))
		edit["danger"] = clamp(round(danger), 0, OVERWORLD_MAX_CELL_DANGER)

	if(!length(edit))
		return FALSE

	cell_overrides[cell_id] = edit
	apply_overrides(region)
	return TRUE

/// Forgets every edit made to one cell, handing it back to the generator. Returns TRUE if there was one.
/datum/overworld_state/proc/clear_cell_override(datum/overworld_region/region, cell_id)
	if(!cell_overrides[cell_id])
		return FALSE
	cell_overrides -= cell_id
	return TRUE

/**
 * Places a site the generator did not, at a cell that exists. Returns its site id, or null.
 *
 * Ranked above anything the generator reaches so it cannot inherit a generated site's identity, and with it
 * whatever play had already done to that site.
 */
/datum/overworld_state/proc/add_site(datum/overworld_region/region, kind, q, r, site_yield = 0)
	if(!region?.get_cell(q, r))
		return null

	var/list/kinds = OVERWORLD_SITE_KINDS
	if(!(kind in kinds))
		return null

	var/rank = OVERWORLD_ADMIN_SITE_RANK_BASE
	while(added_sites["[kind]:[rank]"] || region.sites["[kind]:[rank]"])
		rank++

	var/site_id = "[kind]:[rank]"
	added_sites[site_id] = list(
		"kind" = kind,
		"rank" = rank,
		"q" = q,
		"r" = r,
		"yield" = max(0, round(site_yield)),
	)
	apply_overrides(region)
	return site_id

/// Removes a placed site. A generated one cannot be removed - deplete it instead, which is what play does.
/datum/overworld_state/proc/remove_added_site(site_id)
	if(!added_sites[site_id])
		return FALSE
	added_sites -= site_id
	site_states -= site_id
	return TRUE

/**
 * Lays this state's edits over a freshly generated region.
 *
 * Called on every build rather than once, because the region is cached by a signature over the seed and the
 * options and is thrown away whenever that changes. An edit that was applied only at restore would vanish the
 * first time anything asked for the map again.
 *
 * The region's fingerprint is deliberately left alone. It identifies what the *generator* produced, and that is
 * exactly what the drift check downstream needs it to mean - an admin's edits are a layer on top, not evidence
 * that the generator has changed.
 */
/datum/overworld_state/proc/apply_overrides(datum/overworld_region/region)
	if(!region)
		return 0

	. = 0
	for(var/cell_id in cell_overrides)
		var/datum/overworld_cell/cell = region.cells[cell_id]
		if(!cell)
			continue
		var/list/edit = cell_overrides[cell_id]
		if(edit["terrain"])
			cell.terrain = edit["terrain"]
		if(edit["topology"])
			cell.topology = edit["topology"]
		if(isnum(edit["danger"]))
			cell.danger = edit["danger"]
		.++

	for(var/site_id in added_sites)
		if(region.sites[site_id])
			continue
		var/list/spec = added_sites[site_id]
		var/datum/overworld_site/placed = new(spec["kind"], spec["rank"], spec["q"], spec["r"])
		placed.yield = spec["yield"]
		region.sites[site_id] = placed
		.++

	return .

/// Flat list form for the manifest. Keep in step with deserialize().
/datum/overworld_state/proc/serialize()
	RETURN_TYPE(/list)
	var/list/discovered = list()
	for(var/cell_id in discovered_cells)
		discovered += cell_id

	var/list/changed = list()
	for(var/site_id in site_states)
		var/list/record = site_states[site_id]
		changed[site_id] = list(
			"state" = record["state"],
			"reason" = record["reason"],
		)

	var/list/edited_cells = list()
	for(var/cell_id in cell_overrides)
		edited_cells[cell_id] = cell_overrides[cell_id].Copy()

	var/list/placed_sites = list()
	for(var/site_id in added_sites)
		placed_sites[site_id] = added_sites[site_id].Copy()

	return list(
		"schema_version" = schema_version,
		"generation_version" = generation_version,
		"options" = options.Copy(),
		"discovered_cells" = discovered,
		"site_states" = changed,
		"region_fingerprint" = region_fingerprint,
		// Added without a schema bump on purpose: the version check below is an equality test with no
		// migration behind it, so raising it would refuse every record written before this field existed and
		// reset a running campaign's map. A record without them reads as a map nobody has edited, which is
		// exactly what it is.
		"cell_overrides" = edited_cells,
		"added_sites" = placed_sites,
		"next_party_number" = next_party_number,
		"next_decision_number" = next_decision_number,
		"active_party" = active_party?.serialize(),
	)

/**
 * Loads a record produced by serialize(). Returns TRUE on success.
 *
 * Refuses outright on anything that makes the record's ids meaningless - an unknown schema, a generator from
 * the future, or options the build does not have - because every cell and site id inside it is only
 * interpretable against the region those inputs would build.
 *
 * Individual bad entries are dropped rather than refused, on the same principle used everywhere else in this
 * campaign: a corrupted line costs the colony that line, not its whole history.
 */
/datum/overworld_state/proc/deserialize(list/data)
	if(!islist(data))
		return FALSE

	var/incoming_schema = data["schema_version"]
	if(!isnum(incoming_schema) || incoming_schema != COLONY_OVERWORLD_SCHEMA_VERSION)
		log_game("Overworld state rejected: unsupported schema version '[incoming_schema]'.")
		return FALSE

	var/incoming_generation = data["generation_version"]
	if(!isnum(incoming_generation) || incoming_generation > OVERWORLD_GENERATION_VERSION)
		log_game("Overworld state rejected: generator version [incoming_generation] is newer than this build understands ([OVERWORLD_GENERATION_VERSION]).")
		return FALSE

	if(!is_valid_overworld_options(data["options"]))
		log_game("Overworld state rejected: the stored region options are not ones this build can generate.")
		return FALSE
	var/list/incoming_options = data["options"]

	var/list/incoming_discovered = list()
	if(islist(data["discovered_cells"]))
		for(var/cell_id in data["discovered_cells"])
			if(istext(cell_id))
				incoming_discovered[cell_id] = TRUE

	var/list/known_states = OVERWORLD_SITE_STATES
	var/list/incoming_sites = list()
	if(islist(data["site_states"]))
		for(var/site_id in data["site_states"])
			var/list/record = data["site_states"][site_id]
			if(!istext(site_id) || !islist(record))
				continue
			if(!(record["state"] in known_states) || record["state"] == OVERWORLD_SITE_STATE_AVAILABLE)
				continue
			incoming_sites[site_id] = list(
				"state" = record["state"],
				"reason" = record["reason"],
			)

	// Each edit is checked on the way in, on the same terms as the ones above: a record off disk is not
	// trusted, and a line that makes no sense costs the map that line rather than every edit on it.
	var/list/terrains = OVERWORLD_TERRAINS
	var/list/costs = OVERWORLD_TOPOLOGY_COSTS
	var/list/incoming_cell_edits = list()
	if(islist(data["cell_overrides"]))
		for(var/cell_id in data["cell_overrides"])
			var/list/edit = data["cell_overrides"][cell_id]
			if(!istext(cell_id) || !islist(edit))
				continue
			var/list/clean = list()
			if(edit["terrain"] in terrains)
				clean["terrain"] = edit["terrain"]
			if(edit["topology"] in costs)
				clean["topology"] = edit["topology"]
			if(isnum(edit["danger"]))
				clean["danger"] = clamp(round(edit["danger"]), 0, OVERWORLD_MAX_CELL_DANGER)
			if(length(clean))
				incoming_cell_edits[cell_id] = clean

	var/list/kinds = OVERWORLD_SITE_KINDS
	var/list/incoming_placed_sites = list()
	if(islist(data["added_sites"]))
		for(var/site_id in data["added_sites"])
			var/list/spec = data["added_sites"][site_id]
			if(!istext(site_id) || !islist(spec))
				continue
			if(!(spec["kind"] in kinds) || !isnum(spec["rank"]) || !isnum(spec["q"]) || !isnum(spec["r"]))
				continue
			incoming_placed_sites[site_id] = list(
				"kind" = spec["kind"],
				"rank" = round(spec["rank"]),
				"q" = round(spec["q"]),
				"r" = round(spec["r"]),
				"yield" = isnum(spec["yield"]) ? max(0, round(spec["yield"])) : 0,
			)

	// Built before anything is assigned, so a party record that turns out to be unreadable costs the caravan
	// rather than the whole regional record - the discoveries beside it are still perfectly good.
	var/datum/overworld_party/incoming_party = null
	if(islist(data["active_party"]))
		var/datum/overworld_party/candidate = new()
		if(candidate.deserialize(data["active_party"]))
			incoming_party = candidate
		else
			qdel(candidate)
			log_game("Overworld state dropped an unreadable expedition record; its members are treated as home.")

	var/incoming_party_number = data["next_party_number"]
	if(!isnum(incoming_party_number) || incoming_party_number < 1 || incoming_party_number != round(incoming_party_number))
		incoming_party_number = 1

	var/incoming_decision_number = data["next_decision_number"]
	if(!isnum(incoming_decision_number) || incoming_decision_number < 1 || incoming_decision_number != round(incoming_decision_number))
		incoming_decision_number = 1

	schema_version = incoming_schema
	generation_version = incoming_generation
	options = incoming_options.Copy()
	discovered_cells = incoming_discovered
	site_states = incoming_sites
	cell_overrides = incoming_cell_edits
	added_sites = incoming_placed_sites
	region_fingerprint = istext(data["region_fingerprint"]) ? data["region_fingerprint"] : null
	QDEL_NULL(active_party)
	active_party = incoming_party
	next_decision_number = incoming_decision_number
	// Never allowed to go backwards past a party that already exists, or the next journey would take its id.
	next_party_number = incoming_party_number
	if(active_party)
		var/existing_number = text2num(copytext(active_party.party_id, 7))
		if(isnum(existing_number) && existing_number >= next_party_number)
			next_party_number = existing_number + 1
	return TRUE

/**
 * Drops everything play changed, keeping only what the colony chose.
 *
 * A lost generation is a lost world: its discoveries described ground that no longer exists. The options
 * survive because they are the player's preference about how they want to play, not a fact about the dead
 * planet.
 */
/datum/overworld_state/proc/reset_for_new_generation()
	discovered_cells = list()
	site_states = list()
	// Edits described the dead planet's ground as surely as the discoveries did. A cell id means somewhere
	// else now, so keeping them would move an admin's mountain range onto a world that never had one.
	cell_overrides = list()
	added_sites = list()
	region_fingerprint = null
	// Anybody who was still out there was out there on a planet that is gone. The counter is not rewound: ids
	// stay unique across the whole campaign, which is what makes an old ledger entry still readable.
	QDEL_NULL(active_party)
