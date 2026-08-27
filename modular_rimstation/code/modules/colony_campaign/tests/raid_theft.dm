/**
 * Loot only counts once it has left the map.
 *
 * This is the rule the whole objective rests on. A raider standing in your settlement with its arms full has
 * taken nothing yet - kill it and the goods fall on the floor, still yours. Without that, theft would be
 * something that simply happens to a colony rather than something it can fight.
 */
/datum/unit_test/rimstation_raid_loot_is_recoverable

/datum/unit_test/rimstation_raid_loot_is_recoverable/Run()
	var/datum/colony_raid/raid = new
	allocated += raid

	var/obj/structure/closet/colonist_storage/stash/stash = allocate(/obj/structure/closet/colonist_storage/stash, run_loc_floor_bottom_left)
	var/obj/item/storage/backpack/valuables = allocate(/obj/item/storage/backpack)
	valuables.forceMove(stash)

	var/mob/living/basic/trooper/pirate/melee/rimstation_raider/thief = allocate(/mob/living/basic/trooper/pirate/melee/rimstation_raider, run_loc_floor_bottom_left)
	thief.AddComponent(/datum/component/raider_loot)

	TEST_ASSERT_EQUAL(loot_container(thief, stash), 1, "A raider could not take anything out of a colony stash.")
	TEST_ASSERT_EQUAL(valuables.loc, thief, "Looted goods did not end up on the raider carrying them.")
	TEST_ASSERT(!length(stash.contents), "Looting left the goods in the stash as well as on the raider.")

	// Killed before it got out: the colony gets its things back.
	thief.death()
	TEST_ASSERT(!QDELETED(valuables), "Killing a thief destroyed what it had stolen instead of dropping it.")
	TEST_ASSERT_EQUAL(get_turf(valuables), run_loc_floor_bottom_left, "A killed thief's goods did not fall where it died.")


/// A raider can only carry so much, or one attacker would empty a settlement on its own.
/datum/unit_test/rimstation_raid_loot_is_bounded

/datum/unit_test/rimstation_raid_loot_is_bounded/Run()
	var/obj/structure/closet/colonist_storage/stash/stash = allocate(/obj/structure/closet/colonist_storage/stash, run_loc_floor_bottom_left)
	// Distinct items rather than stacks: sheets of the same material merge into one object on entering the
	// same container, so a stash "full of iron" is a single thing to pick up, not a pile of them.
	for(var/i in 1 to COLONY_RAID_LOOT_CAPACITY + 4)
		var/obj/item/wrench/tool = allocate(/obj/item/wrench)
		tool.forceMove(stash)

	var/mob/living/basic/trooper/pirate/melee/rimstation_raider/thief = allocate(/mob/living/basic/trooper/pirate/melee/rimstation_raider, run_loc_floor_bottom_left)

	var/taken = loot_container(thief, stash)
	TEST_ASSERT_EQUAL(taken, COLONY_RAID_LOOT_CAPACITY, "A raider carried away more than its capacity in one go.")
	TEST_ASSERT(is_raider_loaded(thief), "A raider holding its capacity did not report itself as full.")
	TEST_ASSERT_EQUAL(length(stash.contents), 4, "Looting took more out of the stash than the raider could carry.")

	// A full raider takes nothing further, however much is left.
	TEST_ASSERT_EQUAL(loot_container(thief, stash), 0, "A full raider kept taking things.")


/**
 * Extraction is what turns carried goods into a campaign loss.
 *
 * The colony's record of what it lost has to be the goods that actually left, so that a chapter can say "they
 * got away with four things" rather than "some things are missing".
 */
/datum/unit_test/campaign_failure_path/rimstation_raid_extraction_records_the_loss

/datum/unit_test/campaign_failure_path/rimstation_raid_extraction_records_the_loss/Run()
	test_campaign_id = "unit-test-raid-theft"
	take_campaign()
	TEST_ASSERT(SScampaign.create_campaign(test_campaign_id, "admin-key"), "A campaign could not be created.")

	var/datum/colony_raid/raid = new
	allocated += raid
	raid.goal = COLONY_RAID_GOAL_THEFT

	var/mob/living/basic/trooper/pirate/melee/rimstation_raider/thief = allocate(/mob/living/basic/trooper/pirate/melee/rimstation_raider, run_loc_floor_bottom_left)
	var/obj/item/storage/backpack/valuables = allocate(/obj/item/storage/backpack)
	valuables.forceMove(thief)

	var/datum/settlement_ledger/ledger = SScampaign.get_ledger()
	var/entries_before = length(ledger.entries)

	TEST_ASSERT_EQUAL(raid.extract_raider(thief), 1, "Extracting a loaded raider carried nothing away.")
	TEST_ASSERT_EQUAL(raid.extracted_loot, 1, "The raid did not count what it carried off.")
	TEST_ASSERT_EQUAL(raid.telemetry.items_stolen, 1, "Stolen goods were not recorded in the raid's telemetry.")
	TEST_ASSERT(QDELETED(valuables), "Extracted goods still exist on the map.")
	TEST_ASSERT(length(ledger.entries) > entries_before, "The colony kept no ledger record of being robbed.")

	// An empty raider walking off the map is not a theft.
	var/mob/living/basic/trooper/pirate/melee/rimstation_raider/empty_handed = allocate(/mob/living/basic/trooper/pirate/melee/rimstation_raider, run_loc_floor_bottom_left)
	TEST_ASSERT_EQUAL(raid.extract_raider(empty_handed), 0, "A raider that stole nothing was recorded as having stolen something.")
	TEST_ASSERT_EQUAL(raid.extracted_loot, 1, "An empty-handed escape changed the raid's theft total.")


/**
 * Landing on the edge is not the same as leaving by it.
 *
 * Attackers arrive on insertion turfs, and insertion turfs are edge tiles by definition - that is how they are
 * validated. So a theft raid that treats "standing on the edge" as departure deletes its own attackers on the
 * first tick, empty-handed, on the ground they just landed on, and resolves as repelled before anybody has
 * moved. Departure means carrying something, or having been called off.
 */
/datum/unit_test/rimstation_raid_arrival_is_not_extraction

/datum/unit_test/rimstation_raid_arrival_is_not_extraction/Run()
	var/datum/colony_raid/raid = new
	allocated += raid
	raid.goal = COLONY_RAID_GOAL_THEFT
	raid.state = COLONY_RAID_ASSAULTING

	// Something worth robbing, or the raid correctly ends on its first tick for having nothing to do - which
	// would hide the thing this test is actually about.
	var/obj/structure/closet/colonist_storage/stash/stash = allocate(/obj/structure/closet/colonist_storage/stash, run_loc_floor_top_right)
	var/obj/item/wrench/worth_taking = allocate(/obj/item/wrench)
	worth_taking.forceMove(stash)

	// Standing on an edge tile with nothing to show for it: this raider has arrived, not left.
	var/turf/edge = locate(1 + COLONY_RAID_EDGE_BAND - 1, run_loc_floor_bottom_left.y, run_loc_floor_bottom_left.z)
	TEST_ASSERT_NOTNULL(edge, "The test could not find a turf inside the map-edge band.")
	TEST_ASSERT(raid.is_edge_band_turf(edge), "The turf the test picked is not in the edge band, so this proves nothing.")

	var/mob/living/basic/trooper/pirate/melee/rimstation_raider/arriving = allocate(/mob/living/basic/trooper/pirate/melee/rimstation_raider, edge)
	raid.roster += WEAKREF(arriving)

	// The controller is switched off for the duration, and this is load-bearing rather than tidiness.
	//
	// work_the_theft() runs inside process() and routes attackers, and building a route map runs CHECK_TICK -
	// which yields. A live controller takes that opening and walks the raider off the edge band before the
	// extraction sweep further down the same call ever looks at where it is standing. That made this test fail
	// roughly one run in three, on a rule that was working perfectly.
	arriving.ai_controller?.set_ai_status(AI_STATUS_OFF)

	raid.process(1)
	TEST_ASSERT(!QDELETED(arriving), "An empty-handed attacker standing on its own landing tile was extracted, so a theft raid would delete itself on arrival.")
	TEST_ASSERT(raid.state != COLONY_RAID_RESOLVED, "A theft raid resolved before its attackers had done anything.")
	TEST_ASSERT_EQUAL(raid.extracted_loot, 0, "An empty-handed attacker was recorded as having stolen something.")

	// Once it is carrying something, the same tile means gone.
	var/obj/item/wrench/stolen = allocate(/obj/item/wrench)
	stolen.forceMove(arriving)

	// Put it back on the edge before asking again. Belt and braces alongside the switched-off controller: this
	// test is about the rule that decides extraction, not about whether the mob happened to stay still.
	arriving.forceMove(edge)
	raid.process(1)
	TEST_ASSERT(QDELETED(arriving), "A loaded attacker on the map edge did not get away.")
	TEST_ASSERT_EQUAL(raid.extracted_loot, 1, "A loaded attacker that left was not recorded as stealing anything.")


/**
 * Nobody is ever handed a destination they cannot path to.
 *
 * Basic-mob JPS refuses any path longer than AI_MAX_PATH_LENGTH. A raider given a target beyond that does not
 * walk as far as it can and stop - it stands exactly still, which reads in game as broken pathfinding and is
 * how this was found twice. Every destination therefore has to arrive as a chain of short legs.
 */
/datum/unit_test/rimstation_raid_routes_in_walkable_legs

/datum/unit_test/rimstation_raid_routes_in_walkable_legs/Run()
	var/datum/colony_raid/raid = new
	allocated += raid

	var/turf/here = run_loc_floor_bottom_left
	var/mob/living/basic/trooper/pirate/melee/rimstation_raider/walker = allocate(/mob/living/basic/trooper/pirate/melee/rimstation_raider, here)
	raid.roster += WEAKREF(walker)

	var/obj/structure/closet/colonist_storage/stash/target = allocate(/obj/structure/closet/colonist_storage/stash, run_loc_floor_top_right)

	TEST_ASSERT(raid.route_attacker_to(walker, target), "A raider could not be routed to a destination on the same map.")

	var/destination = walker.ai_controller.blackboard[BB_TRAVEL_DESTINATION]
	TEST_ASSERT_NOTNULL(destination, "A routed raider was given nowhere to go.")
	TEST_ASSERT(get_dist(walker, destination) <= AI_MAX_PATH_LENGTH, "A raider was sent to a destination further than it can path, so it would stand still instead of walking.")

	// Routing is sticky: asking again for the same destination must not restart the journey every tick.
	var/datum/weakref/walker_ref = WEAKREF(walker)
	var/list/first_route = raid.attacker_routes[walker_ref]
	raid.route_attacker_to(walker, target)
	TEST_ASSERT_EQUAL(raid.attacker_routes[walker_ref], first_route, "Re-routing a raider to where it was already going rebuilt its route, so it would never finish a leg.")


/**
 * A theft raid is judged on what it took, not on who died.
 *
 * A colony that killed every thief but lost its stores was still robbed; one that lost the fight while keeping
 * its goods was not. Casualties are the wrong measure for somebody who came to steal.
 */
/datum/unit_test/rimstation_raid_theft_outcome

/datum/unit_test/rimstation_raid_theft_outcome/Run()
	var/datum/colony_raid/raid = new
	allocated += raid
	raid.goal = COLONY_RAID_GOAL_THEFT

	TEST_ASSERT_EQUAL(raid.finish_theft_outcome(), COLONY_RAID_OUTCOME_REPELLED, "A theft raid that took nothing was not counted as repelled.")

	raid.extracted_loot = 2
	TEST_ASSERT_EQUAL(raid.finish_theft_outcome(), COLONY_RAID_OUTCOME_SUCCEEDED, "A theft raid that carried goods away was not counted as succeeding.")


/**
 * A colony with nothing stored is raided for its core, because there is nothing else to come for.
 *
 * The weighting the other way round is deliberate: losing the core ends the campaign, so a raid that can do
 * that should be the exception rather than the usual roll. But a raid must never come to rob a colony that has
 * nothing to rob, or it arrives, finds nothing, and leaves - which reads as the raid being broken.
 */
/datum/unit_test/campaign_failure_path/rimstation_raid_goal_selection

/datum/unit_test/campaign_failure_path/rimstation_raid_goal_selection/Run()
	test_campaign_id = "unit-test-raid-goal"
	take_campaign()
	TEST_ASSERT(SScampaign.create_campaign(test_campaign_id, "admin-key"), "A campaign could not be created.")

	var/datum/colony_incident/raid/incident = new
	allocated += incident
	var/datum/colony_raid/planning = new
	allocated += planning

	// Nothing stored anywhere: the only thing to come for is the core.
	TEST_ASSERT(!length(planning.find_loot_targets()), "The test colony already has something worth robbing.")
	for(var/attempt in 1 to 20)
		TEST_ASSERT_EQUAL(incident.pick_raid_goal(planning), COLONY_RAID_GOAL_CORE, "A raid set out to rob a colony that had nothing stored.")

	// With stores, both goals are reachable - theft usually, the core sometimes.
	var/obj/structure/closet/colonist_storage/stash/stash = allocate(/obj/structure/closet/colonist_storage/stash, run_loc_floor_bottom_left)
	var/obj/item/wrench/valuables = allocate(/obj/item/wrench)
	valuables.forceMove(stash)

	var/saw_theft = FALSE
	var/saw_core = FALSE
	for(var/attempt in 1 to 200)
		var/chosen = incident.pick_raid_goal(planning)
		TEST_ASSERT(chosen == COLONY_RAID_GOAL_THEFT || chosen == COLONY_RAID_GOAL_CORE, "A raid was given a goal that is not one of the two that exist.")
		if(chosen == COLONY_RAID_GOAL_THEFT)
			saw_theft = TRUE
		else
			saw_core = TRUE

	TEST_ASSERT(saw_theft, "Two hundred raids on a colony with stores never once came to rob it.")
	TEST_ASSERT(saw_core, "Two hundred raids never once came for the core, so that threat has stopped existing.")


/// Only storage with something in it is worth robbing, and finding it never walks the map.
/datum/unit_test/rimstation_raid_loot_targets

/datum/unit_test/rimstation_raid_loot_targets/Run()
	var/datum/colony_raid/raid = new
	allocated += raid

	var/obj/structure/closet/colonist_storage/stash/empty_stash = allocate(/obj/structure/closet/colonist_storage/stash, run_loc_floor_bottom_left)
	TEST_ASSERT(!length(raid.find_loot_targets()), "An empty stash was considered worth robbing.")

	var/obj/item/storage/backpack/valuables = allocate(/obj/item/storage/backpack)
	valuables.forceMove(empty_stash)
	TEST_ASSERT_EQUAL(length(raid.find_loot_targets()), 1, "A stocked stash was not a theft target.")

	// A locker counts too - anywhere the colony chose to keep things.
	var/obj/structure/closet/colonist_storage/locker/locker = allocate(/obj/structure/closet/colonist_storage/locker, run_loc_floor_top_right)
	var/obj/item/storage/backpack/more = allocate(/obj/item/storage/backpack)
	more.forceMove(locker)
	TEST_ASSERT_EQUAL(length(raid.find_loot_targets()), 2, "A stocked personal locker was not a theft target.")
