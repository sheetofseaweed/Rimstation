/**
 * Gibtonite has to be far rarer in colony rock than in the station table it inherits.
 *
 * Two separate ways this goes quiet. The thinning itself can be wrong, and the key it thins can stop existing:
 * the table is upstream's, so a merge that renames or drops gibtonite leaves this doing nothing at all. Either
 * way the only symptom is a detonation every few minutes of digging, an hour into a colony.
 */
/datum/unit_test/rimstation_colony_gibtonite_rarity

/datum/unit_test/rimstation_colony_gibtonite_rarity/Run()
	var/turf/closed/mineral/random/rimstation/colony_rock = /turf/closed/mineral/random/rimstation
	var/rarity = initial(colony_rock.gibtonite_rarity)
	TEST_ASSERT(rarity > 1, "Colony rock no longer thins gibtonite at all, so it spawns at station density.")

	var/list/station_table = list(
		/obj/item/stack/ore/iron = 18,
		/obj/item/stack/ore/gold = 8,
		/obj/item/stack/ore/bananium = 0,
		/turf/closed/mineral/gibtonite = 4,
	)
	var/list/thinned = thin_mineral_weight(station_table.Copy(), /turf/closed/mineral/gibtonite, 10)
	TEST_ASSERT_EQUAL(thinned[/turf/closed/mineral/gibtonite], 4, "Thinning changed gibtonite's own weight, which rounds it away to nothing rather than making it rare.")
	TEST_ASSERT_EQUAL(thinned[/obj/item/stack/ore/iron], 180, "Thinning did not scale the rest of the table, so gibtonite is no rarer than it was.")
	TEST_ASSERT_EQUAL(thinned[/obj/item/stack/ore/gold], 80, "Thinning scaled one entry of the table and not another.")
	TEST_ASSERT_EQUAL(thinned[/obj/item/stack/ore/bananium], 0, "Thinning gave weight to an entry the table had switched off.")

	// Gibtonite against everything else, which is the ratio a miner actually experiences.
	var/station_odds = station_table[/turf/closed/mineral/gibtonite] / (18 + 8)
	var/thinned_odds = thinned[/turf/closed/mineral/gibtonite] / (thinned[/obj/item/stack/ore/iron] + thinned[/obj/item/stack/ore/gold])
	TEST_ASSERT_EQUAL(round(station_odds / thinned_odds, 0.01), 10, "Thinned gibtonite came out [round(station_odds / thinned_odds, 0.01)] times rarer rather than ten.")

	// And the key is still in the real table. A table that no longer carries it would pass every check above.
	var/turf/original_type = run_loc_floor_bottom_left.type
	var/turf/closed/mineral/random/rimstation/sample = run_loc_floor_bottom_left.ChangeTurf(/turf/closed/mineral/random/rimstation)
	var/list/colony_table = sample.mineral_chances()
	// Put back before anything is asserted, and taken off the queue it joined on init. This is the test map's
	// own floor, and exposure-based rock hands itself to the ore subsystem the moment it exists.
	SSore_generation.ore_turfs -= sample
	sample.ChangeTurf(original_type)

	TEST_ASSERT(colony_table[/turf/closed/mineral/gibtonite] > 0, "The inherited mineral table no longer carries the gibtonite entry this thins, so nothing is being thinned.")
	TEST_ASSERT(colony_table[/obj/item/stack/ore/iron] > colony_table[/turf/closed/mineral/gibtonite] * rarity, "Colony rock's own table was not scaled past gibtonite, so gibtonite is at station density in play.")
