/**
 * Raider AI: fight what is in front of you, otherwise walk at the colony.
 *
 * This is deliberately a thin layer over the inherited trooper AI. Local combat, obstacle breaking and target
 * selection already work; the only thing missing for a raid is somewhere to go when nothing is shooting at
 * them. Without that they arrive and mill around at the map edge, which is exactly what happened.
 *
 * The inherited controllers do carry a travel subtree, but it is keyed on BB_BASIC_MOB_REINFORCEMENT_TARGET
 * and clears itself on arrival. These use BB_TRAVEL_DESTINATION and keep it, so attackers that get pushed off
 * the objective turn around and come back rather than wandering.
 */
/**
 * Raiders path rather than shove.
 *
 * The inherited troopers use basic_avoidance, which is greedy stepping and not pathfinding at all - it walks
 * at the target until terrain blocks it and then stops. That is fine in a corridor and useless on a generated
 * cave surface, where a raider is separated from the colony by rock almost immediately.
 */
/datum/ai_movement/jps/rimstation_raider

/datum/ai_controller/basic_controller/trooper/rimstation_raider
	ai_movement = /datum/ai_movement/jps/rimstation_raider
	planning_subtrees = list(
		/datum/ai_planning_subtree/escape_captivity,
		/datum/ai_planning_subtree/simple_find_target,
		/datum/ai_planning_subtree/attack_obstacle_in_path/trooper,
		/datum/ai_planning_subtree/basic_melee_attack_subtree/trooper,
		/datum/ai_planning_subtree/travel_to_point,
	)

/datum/ai_controller/basic_controller/trooper/rimstation_raider/ranged
	ai_movement = /datum/ai_movement/jps/rimstation_raider
	planning_subtrees = list(
		/datum/ai_planning_subtree/escape_captivity,
		/datum/ai_planning_subtree/simple_find_target,
		/datum/ai_planning_subtree/basic_ranged_attack_subtree/trooper,
		/datum/ai_planning_subtree/attack_obstacle_in_path/trooper,
		/datum/ai_planning_subtree/travel_to_point,
	)

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
