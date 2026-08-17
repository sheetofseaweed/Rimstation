/**
 * What an incident did, recorded once it is over.
 *
 * Separate from the incident so that the account of what happened outlives the object that made it happen: the
 * storyteller's pacing (Task 6) reads results to decide what the colony has been through lately, and an
 * incident datum is gone by then.
 *
 * Everything here is plain values. A result is written into the campaign record, so it has to survive being
 * JSON and being read by a build that no longer has the incident type that produced it.
 */
/datum/colony_incident_result
	/// Which incident this belongs to.
	var/incident_id
	/// The incident type that produced it, as text so it survives a build that no longer has the type.
	var/incident_type
	/// The tags it carried, so pacing can tell one flavour of story from another.
	var/list/tags
	/// One of the COLONY_INCIDENT_OUTCOME_* values.
	var/outcome = COLONY_INCIDENT_OUTCOME_IGNORED
	/// Human-readable account of what the colony ended up living with.
	var/list/consequences
	/// What the colony gained, as reason-code strings. The ledger holds the actual amounts.
	var/list/rewards
	/// How much this moved the colony's recent pressure. Positive is harder, negative is relief.
	var/pressure_change = 0
	/// Numbers worth keeping for balancing, rather than for play.
	var/list/telemetry
	/// Campaign clock at which the result was recorded.
	var/resolved_at_clock = 0

/datum/colony_incident_result/New(incident_id)
	. = ..()
	src.incident_id = incident_id
	consequences = list()
	rewards = list()
	telemetry = list()
	tags = list()

/datum/colony_incident_result/proc/add_consequence(text)
	if(text)
		consequences += text

/datum/colony_incident_result/proc/add_reward(reason_code)
	if(reason_code)
		rewards += reason_code

/datum/colony_incident_result/proc/record_telemetry(key, value)
	if(key)
		telemetry[key] = value

/datum/colony_incident_result/proc/serialize()
	RETURN_TYPE(/list)
	return list(
		"incident_id" = incident_id,
		"incident_type" = incident_type,
		"tags" = tags.Copy(),
		"outcome" = outcome,
		"consequences" = consequences.Copy(),
		"rewards" = rewards.Copy(),
		"pressure_change" = pressure_change,
		"telemetry" = telemetry.Copy(),
		"resolved_at_clock" = resolved_at_clock,
	)
