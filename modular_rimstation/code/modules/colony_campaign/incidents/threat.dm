/**
 * Somebody comes to take what the colony has.
 *
 * A raid is not scheduled by machinery of its own. The storyteller already decides when the colony should be
 * tested and what that costs, and the incident bridge already turns "buy something threatening" into a
 * concrete piece of content - so a raid is an incident whose effect happens to be a raid, and it inherits
 * pacing, budget, repetition weighting and the rule that a colony still recovering is left alone.
 *
 * Everything about how the raid is fought belongs to `/datum/colony_raid`. This owns only the decision that
 * one happens now, and the reporting of how it went.
 */
/datum/colony_incident/raid
	name = "raid"
	category = COLONY_INCIDENT_CATEGORY_THREAT
	tags = list(INCIDENT_TAG_RAIDERS)
	// The raid runs its own telegraph, so the incident's warning is only the moment it is announced.
	warning_duration = 5 SECONDS
	// Long enough to cover a raid's own warning and the fight after it. The incident resolves itself the moment
	// the raid does, so this is a ceiling rather than a duration.
	active_duration = 30 MINUTES
	// A raid is not something you answer. It is something you survive.
	answer_sources = NONE
	/// The raid this incident is carrying.
	var/datum/colony_raid/raid

/datum/colony_incident/raid/Destroy(force)
	if(raid)
		UnregisterSignal(raid, COMSIG_COLONY_RAID_RESOLVED)
		raid = null
	return ..()

/**
 * Refuses when there is nothing to raid, or a raid already happening.
 *
 * Two raids at once is not twice the story, it is one incoherent one - and the second would compete with the
 * first for the same insertion points and the same core.
 */
/datum/colony_incident/raid/can_begin()
	if(!..())
		return FALSE
	if(!get_colony_core())
		return FALSE
	if(is_colony_raid_running())
		return FALSE
	return TRUE

/datum/colony_incident/raid/announce_warning()
	// Deliberately quiet. The raid announces its own approach with the direction attackers are coming from,
	// and two warnings for one attack would teach players to ignore the first.
	return TRUE

/**
 * Starts the raid and follows it rather than guessing at a duration.
 *
 * The budget comes from the campaign so a young colony is not handed a veteran army, and the raid's own
 * warning is what the settlement actually reacts to.
 */
/datum/colony_incident/raid/execute()
	raid = new()
	raid.threat_budget = SScampaign.get_raid_threat_budget()
	raid.goal = pick_raid_goal(raid)
	RegisterSignal(raid, COMSIG_COLONY_RAID_RESOLVED, PROC_REF(on_raid_resolved))

	if(!raid.begin_warning())
		// The raid refused to deploy - no landing ground, or the world is being written. Nothing arrives, and
		// the colony is told nothing, because nothing happened to it.
		UnregisterSignal(raid, COMSIG_COLONY_RAID_RESOLVED)
		raid = null
		resolve(COLONY_INCIDENT_OUTCOME_IGNORED)
		return FALSE

	return TRUE

/**
 * Decides what this raid came for.
 *
 * Theft is the common case and taking the core is the rare escalation, which is the opposite of how a raid
 * system usually grows. The reasoning is that losing the core ends the campaign: a threat that can delete a
 * colony should be the exception, or the storyteller is repeatedly rolling for whether the whole thing
 * continues. Being robbed costs a colony something it can rebuild, which is a story rather than an ending.
 *
 * A colony with nothing stored anywhere cannot be robbed, so those raids come for the core instead - there is
 * nothing else to come for.
 */
/datum/colony_incident/raid/proc/pick_raid_goal(datum/colony_raid/planning)
	if(!length(planning?.find_loot_targets()))
		return COLONY_RAID_GOAL_CORE
	return prob(COLONY_RAID_THEFT_CHANCE) ? COLONY_RAID_GOAL_THEFT : COLONY_RAID_GOAL_CORE

/// The raid is the incident. When it finishes, so does this.
/datum/colony_incident/raid/proc/on_raid_resolved(datum/source, outcome, reason)
	SIGNAL_HANDLER
	if(is_finished())
		return

	switch(outcome)
		if(COLONY_RAID_OUTCOME_REPELLED)
			// Beaten off. The colony earns a lighter next chapter for it.
			resolve(COLONY_INCIDENT_OUTCOME_SUCCEEDED, -3)
		if(COLONY_RAID_OUTCOME_SUCCEEDED)
			resolve(COLONY_INCIDENT_OUTCOME_FAILED, 5)
		else
			// Cancelled before it landed. Nothing happened to the colony, so nothing is owed either way.
			resolve(COLONY_INCIDENT_OUTCOME_IGNORED)

/datum/colony_incident/raid/build_result(datum/colony_incident_result/building)
	if(!raid)
		return TRUE

	building.record_telemetry("raid_id", raid.raid_id)
	building.record_telemetry("raid_outcome", raid.outcome)
	building.record_telemetry("offered_budget", raid.threat_budget)

	switch(raid.outcome)
		if(COLONY_RAID_OUTCOME_REPELLED)
			building.add_reward("the settlement held")
		if(COLONY_RAID_OUTCOME_SUCCEEDED)
			building.add_consequence("the colony core was taken")
		else
			building.add_consequence("the attack never arrived")
	return TRUE
