/**
 * Every selectable species hands the character menu a list for its description and its lore.
 *
 * This fork's SpeciesPage maps over both (`desc: string[]` in its types), but upstream's doc comment on
 * get_species_description() still says "Returns a string" and upstream species still return one. A string
 * gets through DM, through the JSON, and through every other test, then throws
 * "desc.map is not a function" inside React and takes the whole preferences window with it. There is no
 * runtime to find afterwards, which is why this is asserted here rather than left to be noticed in a round.
 */
/datum/unit_test/rimstation_species_ui_contract

/datum/unit_test/rimstation_species_ui_contract/Run()
	for(var/species_id in get_selectable_species())
		var/species_type = GLOB.species_list[species_id]
		var/datum/species/species = GLOB.species_prototypes[species_type]

		var/description = species.get_species_description()
		if(!islist(description))
			TEST_FAIL("Species [species_id] ([species_type]) returns a [description ? "string" : "null"] from get_species_description(). The character menu maps over it and will crash.")

		var/lore = species.get_species_lore()
		if(!islist(lore))
			TEST_FAIL("Species [species_id] ([species_type]) returns a [lore ? "string" : "null"] from get_species_lore(). The character menu maps over it and will crash.")
