/**
 * Raider AI: fight what is in front of you, otherwise walk at the colony.
 *
 * This is deliberately a thin layer over the inherited trooper AI. Local combat, obstacle breaking and target
 * selection already work; the only thing missing for a raid is somewhere to go when nothing is shooting at
 * them. Without that they arrive and mill around at the map edge, which is exactly what happened.
 *
 * The inherited trees do carry a travel subtree, but it is keyed on BB_BASIC_MOB_REINFORCEMENT_TARGET and
 * clears itself on arrival. This one reads BB_TRAVEL_DESTINATION and keeps it, so attackers that get pushed
 * off the objective turn around and come back rather than wandering.
 *
 * It sits where upstream's trooper trees put random_walk: below every combat branch, so a raider fights what
 * is in front of it and only walks at the colony when nothing is.
 *
 * It stops one tile short. JPS cannot end a path on a dense tile, and the core and every stash are dense.
 */
/datum/bt_node/subtree/rimstation_raid_travel
	behavior_tree_json = "modular_rimstation/code/modules/colony_campaign/raids/raid_travel.bt.json"

/**
 * Raiders path rather than shove.
 *
 * The inherited troopers use basic_avoidance, which is greedy stepping and not pathfinding at all - it walks
 * at the target until terrain blocks it and then stops. That is fine in a corridor and useless on a generated
 * cave surface, where a raider is separated from the colony by rock almost immediately.
 */
/datum/ai_movement/jps/rimstation_raider

/**
 * Points the running move loop at the new target. The parent JPS mover only repaths, toward the loop's old target.
 * A raider then shuffled at its first leg for good, because a one-tile stop never fails and never restarts the loop.
 */
/datum/ai_movement/jps/rimstation_raider/update_movement_target(datum/ai_controller/controller, atom/new_target)
	var/datum/move_loop/has_target/jps/loop = GLOB.move_manager.processing_on(controller.pawn, SSai_movement)
	// Other behaviours run their own loop types on the same subsystem.
	if(istype(loop) && loop.target != new_target)
		if(!isturf(loop.target))
			loop.UnregisterSignal(loop.target, COMSIG_QDELETING)
		loop.target = new_target
		if(!isturf(new_target))
			loop.RegisterSignal(new_target, COMSIG_QDELETING, TYPE_PROC_REF(/datum/move_loop/has_target, handle_no_target))
		loop.movement_path = null
	return ..()

/// A trooper's targeting that leaves wildlife alone. Colonists and wildlife are both `neutral`, so faction cannot tell them apart.
/datum/targeting_strategy/basic/rimstation_raider

/datum/targeting_strategy/basic/rimstation_raider/is_valid_target(mob/living/living_mob, atom/the_target, vision_range, datum/ai_controller/controller = null)
	if(is_ignored_wildlife(living_mob, the_target))
		return FALSE
	return ..()

/// TRUE for an AI-run animal that is not fighting the raid. One that attacks a raider is fought like anything else.
/datum/targeting_strategy/basic/rimstation_raider/proc/is_ignored_wildlife(mob/living/raider, atom/target)
	if(!isliving(target))
		return FALSE
	var/mob/living/animal = target
	if(!(animal.mob_biotypes & MOB_BEAST) || animal.client)
		return FALSE
	var/mob/living/animal_target = animal.ai_controller?.blackboard[BB_CURRENT_TARGET]
	return !(isliving(animal_target) && raider.faction_check_atom(animal_target))

/datum/ai_controller/basic_controller/trooper/rimstation_raider
	ai_movement = /datum/ai_movement/jps/rimstation_raider
	behavior_tree_json = "modular_rimstation/code/modules/colony_campaign/raids/raider.bt.json"
	// The trooper blackboard, with wildlife left alone.
	blackboard = list(
		BB_TARGETING_STRATEGY = /datum/targeting_strategy/basic/rimstation_raider,
		BB_TARGET_MINIMUM_STAT = HARD_CRIT,
		BB_REINFORCEMENTS_SAY = "411 in progress, requesting backup!",
	)

/datum/ai_controller/basic_controller/trooper/rimstation_raider/ranged
	ai_movement = /datum/ai_movement/jps/rimstation_raider
	behavior_tree_json = "modular_rimstation/code/modules/colony_campaign/raids/raider_ranged.bt.json"

/**
 * Raider mobs.
 *
 * Subtyped from pirates purely to swap the AI controller - Phase 5 is where these grow their own identity,
 * objectives and equipment.
 */
/mob/living/basic/trooper/pirate/melee/rimstation_raider
	name = "raider"
	desc = "Someone who decided your colony was easier than building one."
	ai_controller = /datum/ai_controller/basic_controller/trooper/rimstation_raider

/mob/living/basic/trooper/pirate/ranged/rimstation_raider
	name = "raider marksman"
	desc = "Someone who decided your colony was easier than building one, and brought a gun."
	ai_controller = /datum/ai_controller/basic_controller/trooper/rimstation_raider/ranged
