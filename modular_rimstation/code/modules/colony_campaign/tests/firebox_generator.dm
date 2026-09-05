/**
 * The firebox burns what a colony can actually get, and looks like the generator it is built from.
 *
 * The sprite is inherited rather than declared, which makes it the kind of thing a later tidy-up removes
 * without noticing. Asserted here so that removal is a failing test rather than an invisible machine.
 */
/datum/unit_test/rimstation_firebox_generator_contract

/datum/unit_test/rimstation_firebox_generator_contract/Run()
	var/obj/machinery/power/port_gen/pacman/firebox/wood_burner = allocate(/obj/machinery/power/port_gen/pacman/firebox, run_loc_floor_bottom_left)
	var/obj/machinery/power/port_gen/pacman/firebox/coal/coal_burner = allocate(/obj/machinery/power/port_gen/pacman/firebox/coal, run_loc_floor_top_right)

	TEST_ASSERT_EQUAL(wood_burner.sheet_path, /obj/item/stack/sheet/mineral/wood, "The firebox generator does not burn wood.")
	TEST_ASSERT_EQUAL(coal_burner.sheet_path, /obj/item/stack/sheet/mineral/coal, "The coal firebox generator does not burn coal.")

	// Both are meant to be worse than the plasma generator they are built from, and coal better than wood.
	var/obj/machinery/power/port_gen/pacman/plasma_burner = allocate(/obj/machinery/power/port_gen/pacman, run_loc_floor_bottom_left)
	TEST_ASSERT(wood_burner.power_gen < coal_burner.power_gen, "Wood does not produce less power than coal.")
	TEST_ASSERT(coal_burner.power_gen < plasma_burner.power_gen, "A coal firebox out-produces the plasma generator it is built from.")
	TEST_ASSERT(wood_burner.time_per_sheet < plasma_burner.time_per_sheet, "A plank of wood lasts as long as a sheet of plasma.")

	// The P.A.C.M.A.N. sprite, inherited. Nothing here draws its own.
	TEST_ASSERT_EQUAL(wood_burner.icon, plasma_burner.icon, "The firebox generator no longer uses the generator icon file.")
	TEST_ASSERT_EQUAL(wood_burner.base_icon_state, plasma_burner.base_icon_state, "The firebox generator no longer uses the generator sprite.")
	TEST_ASSERT_EQUAL(coal_burner.base_icon_state, plasma_burner.base_icon_state, "The coal firebox generator no longer uses the generator sprite.")


/**
 * A colony that has researched nothing can still build both fireboxes.
 *
 * The point of a wood burner is the first night, so it has to sit in a starting node rather than behind the
 * plasma research P.A.C.M.A.N. lives under. It also has to be printable where a colony actually prints things.
 */
/datum/unit_test/rimstation_firebox_generator_is_reachable

/datum/unit_test/rimstation_firebox_generator_is_reachable/Run()
	var/list/wanted = list("firebox_generator", "firebox_generator_coal")

	for(var/design_id in wanted)
		var/datum/design/design = SSresearch.techweb_design_by_id(design_id)
		TEST_ASSERT_NOTNULL(design, "There is no design with the id '[design_id]', so nothing can ever build one.")
		TEST_ASSERT(design.build_type & COLONY_FABRICATOR, "Design '[design_id]' cannot be printed at a colony fabricator.")

	// Instantiated rather than read off the type, because design_ids is added to in New().
	var/list/starting_nodes_holding = list()
	for(var/node_type as anything in subtypesof(/datum/techweb_node))
		var/datum/techweb_node/node = new node_type()
		if(node.starting_node)
			for(var/design_id in wanted)
				if(design_id in node.design_ids)
					starting_nodes_holding[design_id] = node.id
		qdel(node)

	for(var/design_id in wanted)
		TEST_ASSERT(starting_nodes_holding[design_id], "Design '[design_id]' is in no starting techweb node, so a colony would have to research it before it could burn wood.")
