/**
 * A raider must not cut through an ally that stands between it and its prey.
 * Raiders land stacked, and the obstacle-smashing step used to hit whoever was in the way.
 */
/datum/unit_test/rimstation_raid_raider_spares_ally_in_path

/datum/unit_test/rimstation_raid_raider_spares_ally_in_path/Run()
	var/datum/colony_raid/raid = new
	allocated += raid
	var/turf/here = run_loc_floor_bottom_left
	var/mob/living/basic/trooper/pirate/melee/rimstation_raider/attacker = allocate(/mob/living/basic/trooper/pirate/melee/rimstation_raider, here)
	var/mob/living/basic/trooper/pirate/melee/rimstation_raider/ally = allocate(/mob/living/basic/trooper/pirate/melee/rimstation_raider, locate(here.x + 1, here.y, here.z))
	var/mob/living/carbon/human/colonist = allocate(/mob/living/carbon/human/consistent, locate(here.x + 3, here.y, here.z))
	attacker.set_faction(list(raid.faction))
	ally.set_faction(list(raid.faction))
	ally.ai_controller.force_ai_off()
	// Held in place, so the ally stays in the way.
	ADD_TRAIT(attacker, TRAIT_IMMOBILIZED, TRAIT_SOURCE_UNIT_TESTS)
	raid.keep_awake(attacker)

	sleep(4 SECONDS)
	TEST_ASSERT_EQUAL(attacker.ai_controller.blackboard[BB_CURRENT_TARGET], colonist, "A raider never went for the colonist, so nothing tested the ally in its way.")
	TEST_ASSERT_EQUAL(ally.health, ally.maxHealth, "A raider attacked an ally that stood between it and its prey.")

/// A raider whose prey shares its tile must fight the prey. The obstacle step used to make it hit itself.
/datum/unit_test/rimstation_raid_raider_spares_itself

/datum/unit_test/rimstation_raid_raider_spares_itself/Run()
	var/datum/colony_raid/raid = new
	allocated += raid
	var/turf/here = run_loc_floor_bottom_left
	var/mob/living/basic/trooper/pirate/melee/rimstation_raider/attacker = allocate(/mob/living/basic/trooper/pirate/melee/rimstation_raider, here)
	var/mob/living/carbon/human/colonist = allocate(/mob/living/carbon/human/consistent, here)
	attacker.set_faction(list(raid.faction))
	ADD_TRAIT(attacker, TRAIT_IMMOBILIZED, TRAIT_SOURCE_UNIT_TESTS)
	raid.keep_awake(attacker)

	sleep(4 SECONDS)
	TEST_ASSERT_EQUAL(attacker.health, attacker.maxHealth, "A raider attacked itself when its prey stood on its tile.")
	TEST_ASSERT(colonist.health < colonist.maxHealth, "A raider never fought a colonist that stood on its tile.")

/**
 * Raiders walk past wildlife, but fight an animal that attacks one of them.
 * Colonists and wildlife are both `neutral`, and raiders used to leave their route to chase rabbits.
 */
/datum/unit_test/rimstation_raid_raider_ignores_wildlife

/datum/unit_test/rimstation_raid_raider_ignores_wildlife/Run()
	var/datum/colony_raid/raid = new
	allocated += raid
	var/turf/here = run_loc_floor_bottom_left
	var/mob/living/basic/trooper/pirate/melee/rimstation_raider/raider = allocate(/mob/living/basic/trooper/pirate/melee/rimstation_raider, here)
	var/mob/living/basic/rabbit/rabbit = allocate(/mob/living/basic/rabbit, locate(here.x + 2, here.y, here.z))
	raider.set_faction(list(raid.faction))
	rabbit.ai_controller.force_ai_off()
	// Out of reach, so the raider can only show what it targets.
	ADD_TRAIT(raider, TRAIT_IMMOBILIZED, TRAIT_SOURCE_UNIT_TESTS)
	raid.keep_awake(raider)

	sleep(3 SECONDS)
	TEST_ASSERT_NULL(raider.ai_controller.blackboard[BB_CURRENT_TARGET], "A raider went after a rabbit that left it alone.")

	// The same rabbit turning on the raid is a fight.
	rabbit.ai_controller.set_blackboard_key(BB_CURRENT_TARGET, raider)
	var/give_up_at = world.time + 5 SECONDS
	while(raider.ai_controller.blackboard[BB_CURRENT_TARGET] != rabbit && world.time < give_up_at)
		sleep(0.5 SECONDS)
	TEST_ASSERT_EQUAL(raider.ai_controller.blackboard[BB_CURRENT_TARGET], rabbit, "A raider ignored an animal that was attacking it.")
