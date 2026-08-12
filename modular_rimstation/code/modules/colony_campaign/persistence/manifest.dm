/**
 * The only pointer to a committed campaign checkpoint.
 *
 * Everything about which town loads next chapter reduces to this record. It is deliberately small and made of
 * plain strings and lists: it has to survive schema migration, be readable by an admin with a text editor,
 * and never depend on a datum graph that a future refactor could invalidate.
 *
 * Nothing here decides policy. SScampaign owns the state machine; this owns what is written down.
 */
/datum/campaign_manifest
	/// Layout version. Refuses to load anything it was not written to understand.
	var/schema_version = CAMPAIGN_MANIFEST_SCHEMA_VERSION
	/// Stable identity of the whole campaign, across generations.
	var/campaign_id
	/// The current generation. A new one is created when a generation is lost.
	var/generation_id
	/// Committed checkpoint this generation loads from. Null once the generation is closed.
	var/active_checkpoint_id
	/// Serialized /datum/planet_definition for this generation's world.
	var/list/planet_record
	/// Which chapter is next.
	var/chapter = 1
	/// Accumulated campaign time in deciseconds.
	var/campaign_clock = 0
	/// Storyteller continuity carried between chapters.
	var/list/storyteller_state
	/// References to colonist, faction and economy record files.
	var/list/record_references
	/// How the last completed chapter ended.
	var/last_outcome = COLONY_OUTCOME_PENDING
	/// TRUE once this generation has been closed by defeat. Terminal.
	var/generation_closed = FALSE
	/// Why it was closed.
	var/closure_reason

/datum/campaign_manifest/New(campaign_id, generation_id)
	. = ..()
	src.campaign_id = campaign_id
	src.generation_id = generation_id
	planet_record = list()
	storyteller_state = list()
	record_references = list()

/**
 * TRUE when `id` is safe to build a filesystem path from.
 *
 * Campaign IDs become directory names, so anything that could climb out of the campaign directory or address
 * a different one is refused at the door rather than escaped later.
 */
/proc/is_safe_campaign_id(id)
	if(!istext(id) || !length(id))
		return FALSE
	if(findtext(id, ".."))
		return FALSE
	// Whitelist rather than blacklist: separators, quotes and control characters are all excluded by omission.
	return !findtext(id, regex(@"[^A-Za-z0-9._-]"))

/**
 * TRUE when this manifest describes a campaign that could actually be loaded.
 *
 * The two contradictions worth naming: a checkpoint pointer without a generation to own it, and a closed
 * generation that still claims a live checkpoint. The second is the one that would resurrect a lost town.
 */
/datum/campaign_manifest/proc/validate()
	if(!isnum(schema_version) || schema_version != CAMPAIGN_MANIFEST_SCHEMA_VERSION)
		log_game("Campaign manifest rejected: unsupported schema version '[schema_version]'.")
		return FALSE

	if(!is_safe_campaign_id(campaign_id))
		log_game("Campaign manifest rejected: unusable campaign id '[campaign_id]'.")
		return FALSE

	if(!is_safe_campaign_id(generation_id))
		log_game("Campaign manifest rejected: unusable generation id '[generation_id]'.")
		return FALSE

	if(active_checkpoint_id)
		if(!is_safe_campaign_id(active_checkpoint_id))
			log_game("Campaign manifest rejected: unusable checkpoint id '[active_checkpoint_id]'.")
			return FALSE
		if(generation_closed)
			log_game("Campaign manifest rejected: closed generation [generation_id] still claims checkpoint [active_checkpoint_id].")
			return FALSE

	if(!isnum(chapter) || chapter < 1)
		log_game("Campaign manifest rejected: invalid chapter '[chapter]'.")
		return FALSE

	if(!isnum(campaign_clock) || campaign_clock < 0)
		log_game("Campaign manifest rejected: invalid campaign clock '[campaign_clock]'.")
		return FALSE

	return TRUE

/// Flat list form for JSON storage. Keep in step with deserialize().
/datum/campaign_manifest/proc/serialize()
	RETURN_TYPE(/list)
	return list(
		"schema_version" = schema_version,
		"campaign_id" = campaign_id,
		"generation_id" = generation_id,
		"active_checkpoint_id" = active_checkpoint_id,
		"planet_record" = planet_record?.Copy() || list(),
		"chapter" = chapter,
		"campaign_clock" = campaign_clock,
		"storyteller_state" = storyteller_state?.Copy() || list(),
		"record_references" = record_references?.Copy() || list(),
		"last_outcome" = last_outcome,
		"generation_closed" = generation_closed,
		"closure_reason" = closure_reason,
	)

/**
 * Loads a record produced by serialize(). Returns TRUE on success.
 *
 * Everything is validated before anything is assigned. A half-applied manifest is worse than no manifest,
 * because it would point at a checkpoint that does not match the generation around it.
 */
/datum/campaign_manifest/proc/deserialize(list/data)
	if(!islist(data))
		log_game("Campaign manifest rejected: record is not a list.")
		return FALSE

	var/datum/campaign_manifest/candidate = new
	candidate.schema_version = data["schema_version"]
	candidate.campaign_id = data["campaign_id"]
	candidate.generation_id = data["generation_id"]
	candidate.active_checkpoint_id = data["active_checkpoint_id"]
	candidate.planet_record = islist(data["planet_record"]) ? data["planet_record"] : list()
	candidate.chapter = data["chapter"]
	candidate.campaign_clock = data["campaign_clock"]
	candidate.storyteller_state = islist(data["storyteller_state"]) ? data["storyteller_state"] : list()
	candidate.record_references = islist(data["record_references"]) ? data["record_references"] : list()
	candidate.last_outcome = data["last_outcome"]
	candidate.generation_closed = !!data["generation_closed"]
	candidate.closure_reason = data["closure_reason"]

	if(!candidate.validate())
		qdel(candidate)
		return FALSE

	schema_version = candidate.schema_version
	campaign_id = candidate.campaign_id
	generation_id = candidate.generation_id
	active_checkpoint_id = candidate.active_checkpoint_id
	planet_record = candidate.planet_record
	chapter = candidate.chapter
	campaign_clock = candidate.campaign_clock
	storyteller_state = candidate.storyteller_state
	record_references = candidate.record_references
	last_outcome = candidate.last_outcome
	generation_closed = candidate.generation_closed
	closure_reason = candidate.closure_reason
	qdel(candidate)
	return TRUE

/// TRUE when both manifests point at the same campaign state.
/datum/campaign_manifest/proc/equals(datum/campaign_manifest/other)
	if(!istype(other))
		return FALSE
	return json_encode(serialize()) == json_encode(other.serialize())
