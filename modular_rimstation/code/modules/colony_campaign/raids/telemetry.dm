/**
 * The record of what one raid actually did.
 *
 * Balance for a colony raid cannot be reasoned about from the budget alone - what matters is whether the
 * warning was long enough, whether the composition that arrived matched what was paid for, and what the
 * settlement looked like afterwards. All of that has to be captured while it happens.
 *
 * Settlement damage is measured against a list of structures registered at warning time rather than by
 * scanning the world at resolution. Scanning would be both expensive and wrong: it cannot tell a wall the
 * raiders broke from a wall the colonists never built.
 */
/datum/colony_raid_telemetry
	/// The raid this describes.
	var/raid_id
	/// Budget the raid was allowed to spend.
	var/offered_budget = 0
	/// Budget the composition actually cost.
	var/spent_budget = 0
	/// Assoc of mob type to count, as actually fielded.
	var/list/composition
	/// Compass direction the attackers arrived from.
	var/insertion_direction = "unknown"
	/// Attackers who died.
	var/attacker_casualties = 0
	/// Colonists who died.
	var/defender_casualties = 0
	/// How far the core got toward being taken, 0 to 1.
	var/core_capture_progress = 0
	/// Attackers driven by players rather than AI.
	var/controlled_units = 0
	/// Attackers left to their own AI.
	var/ai_units = 0
	/// How many things the attackers actually carried off the map. Picking loot up does not count.
	var/items_stolen = 0
	/// Final outcome, copied from the raid.
	var/outcome

	/// world.time at each lifecycle state, keyed by state name.
	var/list/state_timestamps
	/// Structures whose condition is being tracked.
	var/list/datum/weakref/tracked_structures
	/// Combined integrity of the tracked structures when first sampled.
	var/baseline_integrity = 0

/datum/colony_raid_telemetry/New(raid_id)
	. = ..()
	src.raid_id = raid_id
	composition = list()
	state_timestamps = list()
	tracked_structures = list()

/datum/colony_raid_telemetry/Destroy(force)
	tracked_structures = null
	return ..()

/// Stamps when the raid entered a lifecycle state, which is what makes warning and duration measurable.
/datum/colony_raid_telemetry/proc/record_state(state)
	state_timestamps[state] = world.time

/datum/colony_raid_telemetry/proc/record_composition(list/fielded, cost)
	composition = fielded?.Copy() || list()
	spent_budget = cost

/// Counts goods that left the map. Only extraction reaches here; loot dropped on the way out was never lost.
/datum/colony_raid_telemetry/proc/record_theft(count)
	items_stolen += count

/datum/colony_raid_telemetry/proc/record_casualty(is_attacker)
	if(is_attacker)
		attacker_casualties++
	else
		defender_casualties++

/// Adds a structure to the settlement damage sample.
/datum/colony_raid_telemetry/proc/register_settlement_structure(obj/structure/tracked)
	if(!istype(tracked))
		return
	tracked_structures += WEAKREF(tracked)

/// Records the settlement's condition before the fight, so damage can be a difference rather than a guess.
/datum/colony_raid_telemetry/proc/sample_settlement_integrity()
	baseline_integrity = current_settlement_integrity()

/datum/colony_raid_telemetry/proc/current_settlement_integrity()
	var/total = 0
	for(var/datum/weakref/structure_ref as anything in tracked_structures)
		var/obj/structure/tracked = structure_ref.resolve()
		// A structure that no longer resolves was destroyed, and contributes nothing. That is the damage.
		if(!tracked)
			continue
		total += tracked.get_integrity()
	return total

/// How much integrity the tracked settlement lost since the baseline sample.
/datum/colony_raid_telemetry/proc/settlement_damage_sample()
	return max(0, baseline_integrity - current_settlement_integrity())

/// Seconds of warning the colony actually got between the alert and the assault.
/datum/colony_raid_telemetry/proc/warning_seconds()
	var/warned_at = state_timestamps[COLONY_RAID_WARNING]
	var/assaulted_at = state_timestamps[COLONY_RAID_ASSAULTING]
	if(!warned_at || !assaulted_at)
		return 0
	return (assaulted_at - warned_at) / (1 SECONDS)

/// Seconds from the first recorded state to the last.
/datum/colony_raid_telemetry/proc/duration_seconds()
	var/earliest = INFINITY
	var/latest = 0
	for(var/state in state_timestamps)
		earliest = min(earliest, state_timestamps[state])
		latest = max(latest, state_timestamps[state])
	if(earliest == INFINITY)
		return 0
	return (latest - earliest) / (1 SECONDS)

/// The flat record handed to blackbox. Keys here are a contract; the schema test asserts each one.
/datum/colony_raid_telemetry/proc/build_payload()
	RETURN_TYPE(/list)
	var/list/readable_composition = list()
	for(var/mob_type in composition)
		readable_composition["[mob_type]"] = composition[mob_type]

	return list(
		"raid_id" = raid_id,
		"offered_budget" = offered_budget,
		"spent_budget" = spent_budget,
		"composition" = readable_composition,
		"warning_seconds" = warning_seconds(),
		"insertion_direction" = insertion_direction,
		"attacker_casualties" = attacker_casualties,
		"defender_casualties" = defender_casualties,
		"core_capture_progress" = core_capture_progress,
		"duration_seconds" = duration_seconds(),
		"controlled_units" = controlled_units,
		"ai_units" = ai_units,
		"items_stolen" = items_stolen,
		"settlement_damage" = settlement_damage_sample(),
		"outcome" = outcome,
	)

/// Sends exactly one record, at resolution.
/datum/colony_raid_telemetry/proc/submit()
	SSblackbox.record_feedback("associative", "colony_raid", 1, build_payload())
