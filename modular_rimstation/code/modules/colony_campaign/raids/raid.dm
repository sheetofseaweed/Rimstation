/**
 * One telegraphed, finite assault on the colony.
 *
 * The raid owns *when and where*; the mobs it spawns keep their own local combat AI. Strategy deliberately
 * does not live in /datum/component/spawner, which is a unit emitter and should stay one.
 *
 * The lifecycle is strictly forward. A raid that could skip from queued to assaulting would remove the
 * preparation window the colony is promised, which is the whole difference between a crisis and an ambush.
 */
/datum/colony_raid
	/// Identifies this raid in logs, telemetry and the chapter outcome.
	var/raid_id
	/// Current lifecycle state.
	var/state = COLONY_RAID_QUEUED
	/// Recorded once, when the raid stops mattering.
	var/outcome
	/// Why it ended that way.
	var/outcome_reason

	/// Total points this raid may spend.
	var/threat_budget = 100
	/// Most attackers alive at once, independent of budget.
	var/live_cap = 12
	/// Faction the attackers belong to.
	var/faction = "rimstation_raiders"
	/// Fraction of the roster that must die before the survivors give up.
	var/casualty_threshold = 0.6

	/// Weakrefs to spawned attackers, so a dead raid does not pin mobs in memory.
	var/list/datum/weakref/roster
	/// Turfs the attackers will arrive on.
	var/list/turf/insertion_turfs
	/// The core this raid is trying to take.
	var/datum/weakref/objective_ref
	/// Chapter result this raid reports into.
	var/datum/colony_chapter_outcome/chapter_outcome

	/// Seconds of warning before the assault begins.
	var/warning_duration = 2 MINUTES
	/// Stoppable timer that starts the assault.
	var/assault_timer_id
	/// Record of what this raid did, submitted once at resolution.
	var/datum/colony_raid_telemetry/telemetry

/datum/colony_raid/New()
	. = ..()
	raid_id = "raid-[world.time]-[rand(1000, 9999)]"
	roster = list()
	insertion_turfs = list()
	telemetry = new(raid_id)

/datum/colony_raid/Destroy(force)
	cancel_timers()
	QDEL_NULL(telemetry)
	roster = null
	insertion_turfs = null
	objective_ref = null
	chapter_outcome = null
	return ..()

/**
 * Moves the raid to `new_state` if that transition is legal. Returns TRUE when it happened.
 *
 * Legal means the next step forward, or a jump straight to resolved. The jump exists because a raid can be
 * cancelled before it deploys, and a cancelled raid still has to reach a terminal state to be cleaned up.
 */
/datum/colony_raid/proc/set_state(new_state)
	var/list/order = COLONY_RAID_STATE_ORDER
	var/current_index = order.Find(state)
	var/new_index = order.Find(new_state)
	if(!new_index)
		log_game("Colony raid [raid_id] refused unknown state '[new_state]'.")
		return FALSE
	if(state == COLONY_RAID_RESOLVED)
		return FALSE
	if(new_state != COLONY_RAID_RESOLVED && new_index != current_index + 1)
		log_game("Colony raid [raid_id] refused transition [state] -> [new_state].")
		return FALSE

	state = new_state
	telemetry?.record_state(new_state)
	return TRUE

/**
 * Buys attackers until the budget, the live cap or the per-unit maximums run out.
 *
 * Minimums are purchased first so a raid always arrives with its intended shape. The weighted fill then
 * spends what is left, and stops the moment nothing affordable remains rather than spinning on leftovers.
 */
/datum/colony_raid/proc/build_composition(budget, list/datum/colony_raid_unit/available, cap)
	RETURN_TYPE(/list)
	var/list/composition = list()
	var/remaining = budget
	var/head_count = 0

	for(var/datum/colony_raid_unit/unit as anything in available)
		for(var/i in 1 to unit.minimum_count)
			if(remaining < unit.point_cost || head_count >= cap)
				break
			composition[unit.mob_type] += 1
			remaining -= unit.point_cost
			head_count++

	while(head_count < cap)
		var/list/affordable = list()
		for(var/datum/colony_raid_unit/unit as anything in available)
			if(unit.point_cost > remaining)
				continue
			if(composition[unit.mob_type] >= unit.maximum_count)
				continue
			affordable[unit] = unit.weight
		if(!length(affordable))
			break
		var/datum/colony_raid_unit/picked = pick_weight(affordable)
		composition[picked.mob_type] += 1
		remaining -= picked.point_cost
		head_count++

	return composition

/// Total budget cost of a composition, used for verification and telemetry.
/datum/colony_raid/proc/composition_cost(list/composition, list/datum/colony_raid_unit/available)
	var/total = 0
	for(var/datum/colony_raid_unit/unit as anything in available)
		total += composition[unit.mob_type] * unit.point_cost
	return total

/**
 * Collects the turfs this raid is allowed to arrive on.
 *
 * Candidates come from mapped-in landmarks rather than a runtime search. A mapper placing the landmark is
 * the assertion that the tile is reachable and sane, which matters because SSpathfinder is asynchronous and
 * cannot answer a reachability question inline during selection.
 *
 * The cheap invariants are still re-checked here, because a landmark can end up buried by generated terrain.
 */
/datum/colony_raid/proc/find_insertion_turfs()
	RETURN_TYPE(/list)
	var/list/turf/valid = list()
	var/obj/effect/landmark/rimstation_settlement_center/centre = GLOB.rimstation_settlement_center
	for(var/obj/effect/landmark/rimstation_raid_insertion/candidate as anything in GLOB.rimstation_raid_insertion_points)
		var/turf/candidate_turf = get_turf(candidate)
		if(!candidate_turf || candidate_turf.density)
			continue
		// Arriving on top of the settlement is the failure this whole proc exists to prevent.
		if(centre && candidate_turf.z == centre.z && get_dist(candidate_turf, centre) < COLONY_RAID_EXCLUSION_RADIUS)
			continue
		if(!is_edge_band_turf(candidate_turf))
			continue
		valid += candidate_turf
	return valid

/// TRUE when the turf sits in the band along the map edge where arrivals are permitted.
/datum/colony_raid/proc/is_edge_band_turf(turf/candidate)
	if(candidate.x <= COLONY_RAID_EDGE_BAND || candidate.y <= COLONY_RAID_EDGE_BAND)
		return TRUE
	if(candidate.x >= world.maxx - COLONY_RAID_EDGE_BAND || candidate.y >= world.maxy - COLONY_RAID_EDGE_BAND)
		return TRUE
	return FALSE

/**
 * Starts the telegraph. Returns FALSE if the raid could not deploy and cancelled itself.
 *
 * Refusing to run is a real outcome. Spawning inside the town because no edge tile was available would be
 * worse than no raid at all.
 */
/datum/colony_raid/proc/begin_warning()
	if(state != COLONY_RAID_QUEUED)
		return FALSE

	insertion_turfs = find_insertion_turfs()
	if(!length(insertion_turfs))
		log_game("Colony raid [raid_id] cancelled: no validated insertion points.")
		resolve_raid(COLONY_RAID_OUTCOME_CANCELLED, "no validated insertion points existed")
		return FALSE

	set_state(COLONY_RAID_WARNING)
	telemetry.insertion_direction = describe_insertion_direction()
	// Sample the settlement before anything is shot at, so damage is a difference rather than a guess.
	telemetry.sample_settlement_integrity()
	announce_warning()
	assault_timer_id = addtimer(CALLBACK(src, PROC_REF(begin_assault)), warning_duration, TIMER_STOPPABLE)
	return TRUE

/// Compass direction the attackers are arriving from, relative to the settlement.
/datum/colony_raid/proc/describe_insertion_direction()
	var/turf/sample = length(insertion_turfs) ? insertion_turfs[1] : null
	var/obj/effect/landmark/rimstation_settlement_center/centre = GLOB.rimstation_settlement_center
	if(!sample || !centre)
		return "unknown"
	return dir2text(get_dir(centre, sample))

/// Tells the colony what is coming, roughly from where, and how long it has.
/datum/colony_raid/proc/announce_warning()
	var/direction = describe_insertion_direction()
	priority_announce(
		"Hostile movement detected approaching from [direction]. Estimated contact in [DisplayTimeText(warning_duration)]. They are moving on the colony core.",
		"Colony Perimeter Alert",
	)

/datum/colony_raid/proc/begin_assault()
	assault_timer_id = null
	if(state != COLONY_RAID_WARNING)
		return
	set_state(COLONY_RAID_ASSEMBLING)
	set_state(COLONY_RAID_ARRIVING)
	deploy_attackers()
	set_state(COLONY_RAID_ASSAULTING)

/// Spawns the bought attackers across the validated arrival tiles.
/datum/colony_raid/proc/deploy_attackers()
	var/list/available = get_available_units()
	var/list/composition = build_composition(threat_budget, available, live_cap)
	telemetry.record_composition(composition, composition_cost(composition, available))
	for(var/mob_type in composition)
		for(var/i in 1 to composition[mob_type])
			var/turf/arrival = pick(insertion_turfs)
			var/mob/living/attacker = new mob_type(arrival)
			attacker.faction = list(faction)
			roster += WEAKREF(attacker)
			// Phase 1 raids are AI-complete by design; Phase 5 is what offers these to ghosts.
			telemetry.ai_units++

/**
 * The unit table this raid draws from. Phase 5 replaces this with per-faction rosters.
 *
 * Pirates are reused rather than given bespoke mobs because they already come with working melee and ranged
 * AI; the point of this phase is the budget and the lifecycle around them, not new combatants.
 */
/datum/colony_raid/proc/get_available_units()
	RETURN_TYPE(/list)
	return list(
		new /datum/colony_raid_unit(/mob/living/basic/trooper/pirate/melee, 20, 2, 8, "grunt", 5),
		new /datum/colony_raid_unit(/mob/living/basic/trooper/pirate, 35, 0, 4, "ranged", 2),
	)

/// How many of the spawned attackers are still alive.
/datum/colony_raid/proc/living_attacker_count()
	var/alive = 0
	for(var/datum/weakref/attacker_ref as anything in roster)
		var/mob/living/attacker = attacker_ref.resolve()
		if(attacker && attacker.stat != DEAD)
			alive++
	return alive

/**
 * Records how the raid ended and stops it doing anything further.
 *
 * First outcome wins: once the fight has been decided, later cleanup must not rewrite the story.
 */
/datum/colony_raid/proc/resolve_raid(new_outcome, reason)
	if(outcome)
		return FALSE
	outcome = new_outcome
	outcome_reason = reason
	cancel_timers()
	set_state(COLONY_RAID_RESOLVED)

	if(telemetry)
		telemetry.outcome = outcome
		// Captured here rather than at warning so that a raid cancelled before it deployed still records
		// what it was offered - "we budgeted 100 points and found nowhere to land" is worth knowing.
		telemetry.offered_budget = threat_budget
		var/obj/structure/colony_core/core = objective_ref?.resolve()
		if(core)
			telemetry.core_capture_progress = core.capture_duration ? (core.capture_progress / core.capture_duration) : 0
		telemetry.submit()

	log_game("Colony raid [raid_id] resolved as [outcome]: [reason].")
	message_admins("Colony raid [raid_id] resolved as [outcome]: [reason].")
	return TRUE

/datum/colony_raid/proc/cancel_timers()
	if(!assault_timer_id)
		return
	deltimer(assault_timer_id)
	assault_timer_id = null
