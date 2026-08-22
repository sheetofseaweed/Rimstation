/**
 * Taking things, and getting away with them.
 *
 * Theft is only a loss if the goods leave. A raider standing on your locker with their arms full has taken
 * nothing yet - kill them and it all falls on the floor, still yours. That single rule is what makes a theft
 * raid something you can fight rather than something that simply happens to you, and it is why extraction
 * exists as a separate step rather than the moment of picking something up being the moment it is gone.
 *
 * Loot rides in the raider's `contents` rather than its hands, because basic mobs have no hands - `held_items`
 * is an empty list on everything that is not a carbon. Contents work regardless and survive being dragged
 * around, which is all this needs.
 */

/// Everything a raider is carrying off. Their own equipment is not in contents, so this is only stolen goods.
/proc/get_raider_loot(mob/living/raider)
	RETURN_TYPE(/list)
	var/list/carried = list()
	if(!isliving(raider))
		return carried
	for(var/obj/item/stolen in raider.contents)
		carried += stolen
	return carried

/// TRUE when this raider has no more room. Bounded so one attacker cannot empty a settlement by itself.
/proc/is_raider_loaded(mob/living/raider)
	return length(get_raider_loot(raider)) >= COLONY_RAID_LOOT_CAPACITY

/**
 * Moves what it can from `container` into `raider`. Returns how many things were taken.
 *
 * Takes whole items rather than counting an abstract value, so what the colony lost is exactly what it can see
 * missing, and exactly what it gets back if it kills the thief.
 *
 * Capacity counts objects, and a stack is one object however deep it is - a raider that grabs the sheets takes
 * the whole pile. That is deliberate rather than overlooked: what is worth taking is whatever the colony chose
 * to store, and a thief walking off with the iron is the point rather than an exploit.
 */
/proc/loot_container(mob/living/raider, obj/structure/closet/colonist_storage/container)
	if(!isliving(raider) || !istype(container))
		return 0

	var/taken = 0
	for(var/obj/item/valuables in container.contents)
		if(is_raider_loaded(raider))
			break
		valuables.forceMove(raider)
		taken++

	if(taken)
		raider.visible_message(span_warning("[raider] ransacks [container]!"))
	return taken

/**
 * Drops everything a raider was carrying where they fell.
 *
 * Registered on death rather than done at cleanup, because troopers carry DEL_ON_DEATH - the mob is deleted
 * the moment it dies, and anything still inside it would be deleted with it. The death signal fires from
 * /mob/living/death() before that qdel, which is the only window where the goods can still be saved.
 */
/proc/drop_raider_loot(mob/living/raider)
	var/turf/spilled_at = get_turf(raider)
	var/dropped = 0
	for(var/obj/item/stolen as anything in get_raider_loot(raider))
		if(spilled_at)
			stolen.forceMove(spilled_at)
		else
			// Nowhere to fall means nowhere to recover it from either; better gone than in a deleted mob.
			qdel(stolen)
		dropped++
	return dropped


/// Watches one attacker so that what it stole falls out of it when it dies.
/datum/component/raider_loot
	dupe_mode = COMPONENT_DUPE_UNIQUE

/datum/component/raider_loot/Initialize()
	. = ..()
	if(!isliving(parent))
		return COMPONENT_INCOMPATIBLE
	RegisterSignal(parent, COMSIG_LIVING_DEATH, PROC_REF(on_raider_died))

/datum/component/raider_loot/proc/on_raider_died(mob/living/source, gibbed)
	SIGNAL_HANDLER
	drop_raider_loot(source)


/**
 * Somewhere worth robbing.
 *
 * Read from the colony storage registry rather than by looking at the map, so raid planning never walks a
 * z-level. It also means what a raid can steal is exactly what the colony chose to put somewhere - a stash or
 * a locker - which is the same stake the storage system was built with.
 */
/datum/colony_raid/proc/find_loot_targets()
	RETURN_TYPE(/list)
	var/list/worth_robbing = list()
	for(var/obj/structure/closet/colonist_storage/container as anything in GLOB.colonist_storage_containers)
		if(!length(container.contents))
			continue
		if(!get_turf(container))
			continue
		worth_robbing += container
	return worth_robbing

/// TRUE while any attacker still has stolen goods on them. Loot in the colony is not lost yet.
/datum/colony_raid/proc/any_raider_carrying()
	for(var/datum/weakref/attacker_ref as anything in roster)
		var/mob/living/attacker = attacker_ref.resolve()
		if(attacker && length(get_raider_loot(attacker)))
			return TRUE
	return FALSE

/**
 * Drives a theft raid: rob what is in reach, then leave with it.
 *
 * Attackers are sent at storage while their arms are empty and at the map edge once they are full, so a thief
 * walks in, takes what it can carry and turns around. Nobody is ordered to fight - the inherited combat AI
 * already answers anyone who shoots at them, which is the difference between a robbery and a massacre.
 */
/datum/colony_raid/proc/work_the_theft()
	var/list/targets = find_loot_targets()

	for(var/datum/weakref/attacker_ref as anything in roster)
		var/mob/living/attacker = attacker_ref.resolve()
		if(!attacker || attacker.stat == DEAD || !attacker.ai_controller)
			continue

		// Full arms means one destination: away.
		if(is_raider_loaded(attacker) || !length(targets))
			send_raider_home(attacker)
			continue

		var/obj/structure/closet/colonist_storage/nearest = get_closest_atom(/obj/structure/closet/colonist_storage, targets, attacker)
		if(!nearest)
			send_raider_home(attacker)
			continue

		// Close enough to reach into: take what fits, then head out if that filled them.
		if(get_dist(attacker, nearest) <= 1)
			loot_container(attacker, nearest)
			if(is_raider_loaded(attacker))
				send_raider_home(attacker)
			continue

		// Routed in short legs rather than pointed at the stash directly. A raider given a destination beyond
		// AI_MAX_PATH_LENGTH stands still instead of walking as far as it can, which looks exactly like broken
		// pathfinding and is how this was found.
		route_attacker_to(attacker, nearest)

/// Points one attacker back at the way everybody came in, in legs it can actually walk.
/datum/colony_raid/proc/send_raider_home(mob/living/attacker)
	var/turf/exit_point = get_shared_exit()
	if(!exit_point)
		return FALSE
	return route_attacker_to(attacker, exit_point)

/**
 * How a theft raid is judged.
 *
 * On whether anything actually left, not on whether the attackers died doing it. A colony that killed every
 * thief but lost its stores was still robbed, and one that lost the fight while keeping its goods was not.
 */
/datum/colony_raid/proc/finish_theft_outcome()
	return extracted_loot ? COLONY_RAID_OUTCOME_SUCCEEDED : COLONY_RAID_OUTCOME_REPELLED

/**
 * Records what actually left the map, and destroys it.
 *
 * Called when a raider reaches the edge still carrying something. The goods are written into the ledger as a
 * loss the colony can read back later rather than simply going missing, and the items themselves are removed -
 * they are somewhere else now, and that somewhere is not modelled.
 */
/datum/colony_raid/proc/extract_raider(mob/living/raider)
	var/list/carried = get_raider_loot(raider)
	if(!length(carried))
		return 0

	var/list/taken_names = list()
	for(var/obj/item/stolen as anything in carried)
		taken_names += stolen.name
		qdel(stolen)

	extracted_loot += length(carried)
	telemetry?.record_theft(length(carried))
	SScampaign.record_nonfinancial(
		LEDGER_CATEGORY_THEFT,
		"raid_theft",
		actor_id = faction,
		related_id = raid_id,
	)
	log_game("Colony raid [raid_id]: extracted [length(carried)] items ([taken_names.Join(", ")]).")
	return length(carried)
