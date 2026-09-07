/**
 * The overworld record carries what was changed, and nothing that can be derived.
 *
 * If a cell, a terrain type or a site position ever reached this record as a *fact*, the campaign would have
 * two answers to what the region looks like - the stored one and the generated one - and they would drift
 * apart the first time a generation rule changed.
 *
 * The two override lists are the deliberate exception, and they hold the line rather than crossing it: they
 * store an admin's *edit*, not the region. The generator still decides what the map is, the edits are laid
 * over the top of every build, and there is still exactly one answer to what any cell looks like.
 */
/datum/unit_test/rimstation_overworld_state_stores_only_changes

/datum/unit_test/rimstation_overworld_state_stores_only_changes/Run()
	var/datum/planet_definition/planet = new("state-test-seed", "state-test-planet")
	allocated += planet
	var/datum/overworld_region/region = new(planet, default_overworld_options())
	allocated += region

	var/datum/overworld_state/state = new(default_overworld_options())
	allocated += state
	state.reveal_initial(region)

	var/list/stored = state.serialize()
	var/list/allowed = list(
		"schema_version",
		"generation_version",
		"options",
		"discovered_cells",
		"site_states",
		"region_fingerprint",
		// An expedition is people the colony sent out. Nothing about it is derivable from the region, and
		// forgetting it across a reboot would strand whoever was on it.
		"next_party_number",
		"next_decision_number",
		"active_party",
		// Admin edits to the generated map. Stored as edits rather than as the map, so the generator stays the
		// one authority on what the region is and these stay a layer over the top of it.
		"cell_overrides",
		"added_sites",
	)

	for(var/field in stored)
		TEST_ASSERT(field in allowed, "The overworld record stored '[field]', which is not something play changed. Anything derivable belongs in the generator, not in campaign state.")
	for(var/field in allowed)
		TEST_ASSERT(field in stored, "The overworld record did not store '[field]'.")

	// Nothing in it may be a datum, a turf or anything else that stops meaning something after a reboot.
	var/encoded = json_encode(stored)
	TEST_ASSERT(!findtext(encoded, "/datum/"), "The overworld record contains a datum reference.")
	TEST_ASSERT(!findtext(encoded, "/turf/"), "The overworld record contains a turf reference.")
	TEST_ASSERT(!findtext(encoded, "/obj/"), "The overworld record contains an object reference.")

	// An untouched site is absent rather than recorded as available: absence is what untouched means.
	TEST_ASSERT(!length(stored["site_states"]), "An untouched region recorded site states it did not need to.")
	// Same rule for the map itself. A region nobody edited must record no edits, or every campaign would carry
	// a copy of the generator's output around with it.
	TEST_ASSERT(!length(stored["cell_overrides"]), "An unedited region recorded cell overrides it did not need to.")
	TEST_ASSERT(!length(stored["added_sites"]), "A region nobody added a site to recorded placed sites.")


/**
 * An admin's edit to the map outlives the chapter it was made in.
 *
 * The region is rebuilt from the planet seed every time anything asks for it, so an edit written to the live
 * cell would last until the next rebuild and no longer. The whole point of storing the edit is that it can be
 * laid back over a region built fresh - which is what this measures, by building a second one and checking the
 * edit is on it.
 */
/datum/unit_test/rimstation_overworld_admin_edits_persist

/datum/unit_test/rimstation_overworld_admin_edits_persist/Run()
	var/datum/planet_definition/planet = new("override-test-seed", "override-test-planet")
	allocated += planet
	var/datum/overworld_region/region = new(planet, default_overworld_options())
	allocated += region

	var/datum/overworld_state/state = new(default_overworld_options())
	allocated += state

	// The origin cell always exists, whatever the seed produced around it.
	var/datum/overworld_cell/origin = region.get_cell(0, 0)
	TEST_ASSERT_NOTNULL(origin, "The region has no origin cell, so there is nothing to edit.")
	var/generated_terrain = origin.terrain

	// Something the generator did not produce here, so the edit is observable rather than a coincidence.
	var/edited_terrain = (generated_terrain == OVERWORLD_TERRAIN_MARSH) ? OVERWORLD_TERRAIN_DESERT : OVERWORLD_TERRAIN_MARSH

	TEST_ASSERT(state.set_cell_override(region, "0,0", edited_terrain, OVERWORLD_TOPOLOGY_DIFFICULT, 3), "A cell edit was refused.")
	TEST_ASSERT_EQUAL(origin.terrain, edited_terrain, "A cell edit did not reach the live region.")
	TEST_ASSERT_EQUAL(origin.topology, OVERWORLD_TOPOLOGY_DIFFICULT, "A topology edit did not reach the live region.")
	TEST_ASSERT_EQUAL(origin.danger, 3, "A danger edit did not reach the live region.")

	var/site_id = state.add_site(region, OVERWORLD_SITE_RESOURCE, 0, 0, 42)
	TEST_ASSERT_NOTNULL(site_id, "A placed site was refused.")
	TEST_ASSERT_NOTNULL(region.sites[site_id], "A placed site did not reach the live region.")

	// Through disk and back, because that is the trip it actually makes.
	var/datum/overworld_state/reloaded = new(default_overworld_options())
	allocated += reloaded
	TEST_ASSERT(reloaded.deserialize(json_decode(json_encode(state.serialize()))), "An overworld record carrying admin edits did not survive a JSON round trip.")

	// A region built fresh, exactly as the next chapter would build it.
	var/datum/overworld_region/rebuilt = new(planet, default_overworld_options())
	allocated += rebuilt
	var/datum/overworld_cell/rebuilt_origin = rebuilt.get_cell(0, 0)
	TEST_ASSERT_EQUAL(rebuilt_origin.terrain, generated_terrain, "A freshly built region already carried the edit, so this test cannot tell whether applying it did anything.")

	reloaded.apply_overrides(rebuilt)

	TEST_ASSERT_EQUAL(rebuilt_origin.terrain, edited_terrain, "A cell edit did not survive to the next region build, so an admin's change to the map dies with the chapter.")
	TEST_ASSERT_EQUAL(rebuilt_origin.topology, OVERWORLD_TOPOLOGY_DIFFICULT, "A topology edit did not survive to the next region build.")
	TEST_ASSERT_EQUAL(rebuilt_origin.danger, 3, "A danger edit did not survive to the next region build.")
	var/datum/overworld_site/rebuilt_site = rebuilt.sites[site_id]
	TEST_ASSERT_NOTNULL(rebuilt_site, "A placed site did not survive to the next region build.")
	TEST_ASSERT_EQUAL(rebuilt_site.yield, 42, "A placed site came back with a different yield than it was given.")

	// Dropping an edit hands the cell back, rather than freezing whatever it was last set to.
	TEST_ASSERT(reloaded.clear_cell_override(rebuilt, "0,0"), "Dropping a cell edit was refused.")
	var/datum/overworld_region/final = new(planet, default_overworld_options())
	allocated += final
	reloaded.apply_overrides(final)
	TEST_ASSERT_EQUAL(final.get_cell(0, 0).terrain, generated_terrain, "A dropped cell edit still applied, so the generator never gets its cell back.")


/**
 * A placed site cannot take a generated site's identity.
 *
 * A site is `<kind>:<rank>`, and that id is what everything play has done to it is filed under. A placed site
 * that landed on a generated one's id would silently inherit its state - and, when the generator later
 * produced that site for real, there would be two things claiming to be it.
 */
/datum/unit_test/rimstation_overworld_placed_sites_get_free_ids

/datum/unit_test/rimstation_overworld_placed_sites_get_free_ids/Run()
	var/datum/planet_definition/planet = new("placed-site-seed", "placed-site-planet")
	allocated += planet
	var/datum/overworld_region/region = new(planet, default_overworld_options())
	allocated += region
	var/datum/overworld_state/state = new(default_overworld_options())
	allocated += state

	var/list/generated_ids = region.sites.Copy()
	TEST_ASSERT(length(generated_ids), "The region generated no sites, so a collision cannot be tested.")

	var/first = state.add_site(region, OVERWORLD_SITE_RESOURCE, 0, 0, 10)
	var/second = state.add_site(region, OVERWORLD_SITE_RESOURCE, 0, 0, 10)
	TEST_ASSERT_NOTNULL(first, "The first placed site was refused.")
	TEST_ASSERT_NOTNULL(second, "The second placed site was refused.")
	TEST_ASSERT(first != second, "Two placed sites were given the same id, so one overwrote the other.")

	for(var/site_id in list(first, second))
		TEST_ASSERT(!(site_id in generated_ids), "A placed site took the id '[site_id]' of a site the generator had already made.")

	// A cell that is not in the region has nowhere to stand.
	TEST_ASSERT_NULL(state.add_site(region, OVERWORLD_SITE_RESOURCE, 9999, 9999, 10), "A site was placed on a cell outside the region.")
	TEST_ASSERT_NULL(state.add_site(region, "not_a_kind", 0, 0, 10), "A site was placed with a kind that does not exist.")


/**
 * A record off disk is not trusted, and one written before these fields existed still loads.
 *
 * The second half is the one that matters right now: the schema check is an equality test with no migration
 * behind it, so these fields were added without raising the version. A campaign that was running before they
 * existed has to keep its discoveries, not be told its map is unreadable.
 */
/datum/unit_test/rimstation_overworld_admin_edits_validated

/datum/unit_test/rimstation_overworld_admin_edits_validated/Run()
	var/datum/overworld_state/state = new(default_overworld_options())
	allocated += state

	var/list/record = state.serialize()
	record["cell_overrides"] = list(
		"0,0" = list("terrain" = "a_terrain_that_does_not_exist", "topology" = "sideways", "danger" = 99),
		"1,1" = list("terrain" = OVERWORLD_TERRAIN_DESERT),
		"2,2" = list(),
	)
	record["added_sites"] = list(
		"good:900" = list("kind" = OVERWORLD_SITE_RUIN, "rank" = 900, "q" = 1, "r" = 1, "yield" = 5),
		"bad:901" = list("kind" = "not_a_kind", "rank" = 901, "q" = 1, "r" = 1),
		"worse:902" = list("kind" = OVERWORLD_SITE_RUIN, "rank" = "not a number", "q" = 1, "r" = 1),
	)

	TEST_ASSERT(state.deserialize(record), "A record carrying unusable edits was refused outright, rather than dropping the bad lines.")

	var/list/kept_cell = state.cell_overrides["0,0"]
	TEST_ASSERT_NOTNULL(kept_cell, "A cell edit was dropped entirely because parts of it were bad.")
	TEST_ASSERT_NULL(kept_cell["terrain"], "A terrain that does not exist was restored.")
	TEST_ASSERT_NULL(kept_cell["topology"], "A topology with no traversal cost was restored, which would make the cell free to cross.")
	TEST_ASSERT_EQUAL(kept_cell["danger"], OVERWORLD_MAX_CELL_DANGER, "An out-of-range danger was not clamped.")
	TEST_ASSERT_EQUAL(state.cell_overrides["1,1"]["terrain"], OVERWORLD_TERRAIN_DESERT, "A valid cell edit beside a bad one was dropped.")
	TEST_ASSERT_NULL(state.cell_overrides["2,2"], "An edit that changed nothing was stored.")

	TEST_ASSERT_NOTNULL(state.added_sites["good:900"], "A valid placed site was dropped.")
	TEST_ASSERT_NULL(state.added_sites["bad:901"], "A placed site with a kind that does not exist was restored.")
	TEST_ASSERT_NULL(state.added_sites["worse:902"], "A placed site with a non-numeric rank was restored.")

	// A record written before these fields existed. It has to load, and read as a map nobody edited.
	var/datum/overworld_state/older = new(default_overworld_options())
	allocated += older
	var/list/old_record = state.serialize()
	old_record -= "cell_overrides"
	old_record -= "added_sites"
	TEST_ASSERT(older.deserialize(old_record), "A record written before admin edits existed was refused, which would reset a running campaign's map.")
	TEST_ASSERT(!length(older.cell_overrides), "A record with no edit fields came back carrying edits.")
	TEST_ASSERT(!length(older.added_sites), "A record with no placed-site field came back carrying placed sites.")


/// A lost generation takes its edits with it. A cell id describes ground that no longer exists.
/datum/unit_test/rimstation_overworld_admin_edits_dropped_with_generation

/datum/unit_test/rimstation_overworld_admin_edits_dropped_with_generation/Run()
	var/datum/planet_definition/planet = new("generation-drop-seed", "generation-drop-planet")
	allocated += planet
	var/datum/overworld_region/region = new(planet, default_overworld_options())
	allocated += region
	var/datum/overworld_state/state = new(default_overworld_options())
	allocated += state

	TEST_ASSERT(state.set_cell_override(region, "0,0", OVERWORLD_TERRAIN_MARSH, null, null), "A cell edit was refused.")
	TEST_ASSERT_NOTNULL(state.add_site(region, OVERWORLD_SITE_RUIN, 0, 0), "A placed site was refused.")

	state.reset_for_new_generation()

	TEST_ASSERT(!length(state.cell_overrides), "A new generation inherited the last one's cell edits, so an admin's mountain range moved onto a world that never had one.")
	TEST_ASSERT(!length(state.added_sites), "A new generation inherited the last one's placed sites.")


/// The record survives the trip to disk with its discoveries and changes intact.
/datum/unit_test/rimstation_overworld_state_round_trip

/datum/unit_test/rimstation_overworld_state_round_trip/Run()
	var/datum/planet_definition/planet = new("state-test-seed", "state-test-planet")
	allocated += planet
	var/list/options = list(
		"extent" = OVERWORLD_EXTENT_COMPACT,
		"roughness" = OVERWORLD_ROUGHNESS_RUGGED,
		"abundance" = OVERWORLD_ABUNDANCE_RICH,
	)
	var/datum/overworld_region/region = new(planet, options)
	allocated += region

	var/datum/overworld_state/state = new(options)
	allocated += state
	state.reveal_initial(region)
	state.region_fingerprint = region.fingerprint

	var/discovered_count = length(state.discovered_cells)
	TEST_ASSERT(discovered_count > 1, "Revealing the colony's surroundings discovered almost nothing.")

	// Empty one of the deposits, which is the kind of change that has to outlive a reboot.
	var/list/deposits = region.sites_of_kind(OVERWORLD_SITE_RESOURCE)
	TEST_ASSERT(length(deposits), "The test region has no deposits, so site state cannot be tested.")
	var/datum/overworld_site/emptied = deposits[1]
	TEST_ASSERT(state.set_site_state(region, emptied.site_id(), OVERWORLD_SITE_STATE_DEPLETED, "mined out"), "A site could not be recorded as depleted.")

	var/datum/overworld_state/restored = new
	allocated += restored
	TEST_ASSERT(restored.deserialize(json_decode(json_encode(state.serialize()))), "An overworld record did not survive a JSON round trip.")

	TEST_ASSERT_EQUAL(length(restored.discovered_cells), discovered_count, "A restored region forgot ground the colony had walked.")
	TEST_ASSERT_EQUAL(restored.get_site_state(emptied.site_id()), OVERWORLD_SITE_STATE_DEPLETED, "A restored region forgot that a deposit had been emptied.")
	TEST_ASSERT_EQUAL(restored.options["extent"], OVERWORLD_EXTENT_COMPACT, "A restored region came back a different size.")
	TEST_ASSERT_EQUAL(restored.region_fingerprint, region.fingerprint, "A restored region did not remember which world it described.")

	// The options must still rebuild the same region, or every stored id now points somewhere else.
	var/datum/overworld_region/rebuilt = new(planet, restored.options)
	allocated += rebuilt
	TEST_ASSERT_EQUAL(rebuilt.fingerprint, region.fingerprint, "Rebuilding from the stored options produced a different region.")


/// Records come off disk, so anything that makes their ids meaningless is refused outright.
/datum/unit_test/rimstation_overworld_state_validation

/datum/unit_test/rimstation_overworld_state_validation/Run()
	var/datum/overworld_state/state = new
	allocated += state
	var/list/valid = state.serialize()

	TEST_ASSERT(!state.deserialize(null), "A null overworld record was accepted.")
	TEST_ASSERT(!state.deserialize(list()), "An empty overworld record was accepted.")

	var/list/future_schema = valid.Copy()
	future_schema["schema_version"] = COLONY_OVERWORLD_SCHEMA_VERSION + 1
	TEST_ASSERT(!state.deserialize(future_schema), "An overworld record from an unknown schema was accepted.")

	// A newer generator builds a different region, so its cell ids describe somewhere this build cannot make.
	var/list/future_generator = valid.Copy()
	future_generator["generation_version"] = OVERWORLD_GENERATION_VERSION + 1
	TEST_ASSERT(!state.deserialize(future_generator), "An overworld record from a newer generator was accepted, so its cell ids would describe a region this build cannot build.")

	var/list/bad_options = valid.Copy()
	bad_options["options"] = list("extent" = "enormous", "roughness" = OVERWORLD_ROUGHNESS_VARIED, "abundance" = OVERWORLD_ABUNDANCE_NORMAL)
	TEST_ASSERT(!state.deserialize(bad_options), "An overworld record naming options this build cannot generate was accepted.")

	// A single corrupted entry costs that entry, not the whole record.
	var/list/messy = valid.Copy()
	messy["site_states"] = list(
		"resource:1" = list("state" = "haunted"),
		"resource:2" = list("state" = OVERWORLD_SITE_STATE_DEPLETED, "reason" = "mined out"),
	)
	TEST_ASSERT(state.deserialize(messy), "A record with one unusable site state was refused outright.")
	TEST_ASSERT_EQUAL(state.get_site_state("resource:1"), OVERWORLD_SITE_STATE_AVAILABLE, "A site in an impossible state was restored anyway.")
	TEST_ASSERT_EQUAL(state.get_site_state("resource:2"), OVERWORLD_SITE_STATE_DEPLETED, "Dropping one bad site state also dropped a valid one.")


/// Discovery is checked against the region, so the record can never describe ground that does not exist.
/datum/unit_test/rimstation_overworld_state_discovery

/datum/unit_test/rimstation_overworld_state_discovery/Run()
	var/datum/planet_definition/planet = new("state-test-seed", "state-test-planet")
	allocated += planet
	var/datum/overworld_region/region = new(planet, default_overworld_options())
	allocated += region

	var/datum/overworld_state/state = new(default_overworld_options())
	allocated += state

	TEST_ASSERT(!state.discover_cell(region, "999,999"), "A cell that does not exist was discovered.")
	TEST_ASSERT(!state.discover_cell(region, "not a cell"), "Nonsense was accepted as a cell id.")
	TEST_ASSERT(!state.is_discovered("0,0"), "A fresh region already knew where the colony was.")

	TEST_ASSERT(state.discover_cell(region, "0,0"), "The colony's own cell could not be discovered.")
	TEST_ASSERT(state.is_discovered("0,0"), "Discovering a cell did not record it.")
	TEST_ASSERT(!state.discover_cell(region, "0,0"), "The same cell was discovered twice.")

	// Entering somewhere shows you the ring around it, which is what makes travel reveal the map.
	var/datum/overworld_state/walker = new(default_overworld_options())
	allocated += walker
	var/revealed = walker.discover_around(region, "3,0")
	TEST_ASSERT(revealed > 1, "Entering a cell revealed only itself, so travelling would never open the map up.")
	TEST_ASSERT(walker.is_discovered("3,0"), "Entering a cell did not reveal the cell itself.")

	var/neighbours_found = 0
	var/list/directions = OVERWORLD_AXIAL_DIRECTIONS
	for(var/list/step as anything in directions)
		if(walker.is_discovered("[3 + step[1]],[0 + step[2]]"))
			neighbours_found++
	TEST_ASSERT_EQUAL(neighbours_found, 6, "Entering a cell did not reveal all six of its neighbours.")


/**
 * A lost generation keeps the choices and loses the world.
 *
 * The options are a preference about how somebody wants to play, so they survive. Everything discovered
 * described ground that no longer exists, so none of it can.
 */
/datum/unit_test/rimstation_overworld_state_generation_reset

/datum/unit_test/rimstation_overworld_state_generation_reset/Run()
	var/datum/planet_definition/planet = new("state-test-seed", "state-test-planet")
	allocated += planet
	var/list/options = list(
		"extent" = OVERWORLD_EXTENT_EXPANSIVE,
		"roughness" = OVERWORLD_ROUGHNESS_GENTLE,
		"abundance" = OVERWORLD_ABUNDANCE_SPARSE,
	)
	var/datum/overworld_region/region = new(planet, options)
	allocated += region

	var/datum/overworld_state/state = new(options)
	allocated += state
	state.reveal_initial(region)
	state.region_fingerprint = region.fingerprint
	var/list/deposits = region.sites_of_kind(OVERWORLD_SITE_RESOURCE)
	if(length(deposits))
		var/datum/overworld_site/site = deposits[1]
		state.set_site_state(region, site.site_id(), OVERWORLD_SITE_STATE_DEPLETED, "mined out")

	state.reset_for_new_generation()

	TEST_ASSERT(!length(state.discovered_cells), "A new generation inherited the last one's discoveries.")
	TEST_ASSERT(!length(state.site_states), "A new generation inherited deposits the last colony had emptied.")
	TEST_ASSERT_NULL(state.region_fingerprint, "A new generation still claimed to describe the old world.")
	TEST_ASSERT_EQUAL(state.options["extent"], OVERWORLD_EXTENT_EXPANSIVE, "A new generation lost the region size the player chose.")
	TEST_ASSERT_EQUAL(state.options["abundance"], OVERWORLD_ABUNDANCE_SPARSE, "A new generation lost the resource setting the player chose.")


/**
 * A campaign from before the overworld still loads, and gains a region.
 *
 * Every campaign currently on disk predates this. Migration is what stops "the colony has a map now" from
 * meaning "the colony you already have can no longer be opened".
 */
/datum/unit_test/campaign_failure_path/rimstation_overworld_manifest_migration

/datum/unit_test/campaign_failure_path/rimstation_overworld_manifest_migration/Run()
	test_campaign_id = "unit-test-overworld-migration"
	take_campaign()

	var/datum/campaign_manifest/manifest = new(test_campaign_id, "generation-1")
	allocated += manifest

	// A schema-5 campaign: everything the colonist roster added, and nothing about a region.
	var/list/older_campaign = manifest.serialize()
	older_campaign["schema_version"] = 5
	older_campaign -= "overworld_record"

	var/datum/campaign_manifest/migrated = new
	allocated += migrated
	TEST_ASSERT(migrated.deserialize(older_campaign), "A campaign from before the overworld could no longer be loaded.")
	TEST_ASSERT_EQUAL(migrated.schema_version, CAMPAIGN_MANIFEST_SCHEMA_VERSION, "Loading an older campaign did not bring it up to the current schema.")
	TEST_ASSERT_NOTNULL(migrated.overworld_record, "A migrated campaign has no overworld field at all.")
	TEST_ASSERT(!length(migrated.overworld_record), "A campaign from before the overworld was given discoveries it never made.")

	// And migration must not have touched the caller's copy.
	TEST_ASSERT_EQUAL(older_campaign["schema_version"], 5, "Migration modified the record it was given instead of a copy.")
