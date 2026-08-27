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
	/// How many generations this campaign has had, this one included. Names the next one without reading it.
	var/generation_number = 1
	/// Committed checkpoint this generation loads from. Null once the generation is closed.
	var/active_checkpoint_id
	/// Serialized /datum/planet_definition for this generation's world.
	var/list/planet_record
	/// Serialized /datum/colony_research_record. What this colony has researched and banked.
	var/list/research_record
	/// Serialized /datum/settlement_ledger. What the settlement owns and how it came to own it.
	var/list/ledger_record
	/// Serialized /datum/colonist_roster. Everyone this generation has known.
	var/list/roster_record
	/// Serialized /datum/overworld_state. The region's options, and what play changed about it.
	var/list/overworld_record
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
	research_record = list()
	ledger_record = list()
	roster_record = list()
	overworld_record = list()
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

	if(!isnum(generation_number) || generation_number < 1)
		log_game("Campaign manifest rejected: invalid generation number '[generation_number]'.")
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
		"generation_number" = generation_number,
		"active_checkpoint_id" = active_checkpoint_id,
		"planet_record" = planet_record?.Copy() || list(),
		"research_record" = research_record?.Copy() || list(),
		"ledger_record" = ledger_record?.Copy() || list(),
		"roster_record" = roster_record?.Copy() || list(),
		"overworld_record" = overworld_record?.Copy() || list(),
		"chapter" = chapter,
		"campaign_clock" = campaign_clock,
		"storyteller_state" = storyteller_state?.Copy() || list(),
		"record_references" = record_references?.Copy() || list(),
		"last_outcome" = last_outcome,
		"generation_closed" = generation_closed,
		"closure_reason" = closure_reason,
	)

/**
 * Brings a record up to the current schema, one version at a time.
 *
 * Returns a migrated copy, or null if the record cannot be brought forward. Versions are never skipped: a
 * campaign written several versions ago arrives at the current shape by passing through every step, rather
 * than through a shortcut somebody has to remember to update when a new version lands.
 *
 * The caller's record is never touched. A migration that stops halfway must leave the original exactly as it
 * was on disk, because that original is still the only copy of the campaign.
 */
/proc/migrate_campaign_manifest_record(list/data)
	RETURN_TYPE(/list)
	if(!islist(data))
		return null

	var/incoming_version = data["schema_version"]
	if(!isnum(incoming_version) || incoming_version < 1 || incoming_version != round(incoming_version))
		log_game("Campaign manifest rejected: '[incoming_version]' is not a schema version.")
		return null

	// Fail closed on the future. A record from a newer build carries fields this one cannot preserve, and
	// loading it would mean writing it back with those fields silently dropped.
	if(incoming_version > CAMPAIGN_MANIFEST_SCHEMA_VERSION)
		log_game("Campaign manifest rejected: schema version [incoming_version] is newer than this build understands ([CAMPAIGN_MANIFEST_SCHEMA_VERSION]).")
		return null

	// deep_copy_list() does not handle associative lists nested inside plain ones - it turns each element into
	// an associative key and loses the rest. Ledger entries are exactly that shape, so the copy has to be the
	// variant written for it, or a campaign quietly loses its history every time it is loaded.
	var/list/record = deep_copy_list_alt(data)
	while(record["schema_version"] < CAMPAIGN_MANIFEST_SCHEMA_VERSION)
		var/from_version = record["schema_version"]
		switch(from_version)
			if(1)
				record = migrate_campaign_manifest_v1_to_v2(record)
			if(2)
				record = migrate_campaign_manifest_v2_to_v3(record)
			if(3)
				record = migrate_campaign_manifest_v3_to_v4(record)
			if(4)
				record = migrate_campaign_manifest_v4_to_v5(record)
			if(5)
				record = migrate_campaign_manifest_v5_to_v6(record)
			else
				log_game("Campaign manifest rejected: no migration exists from schema version [from_version].")
				return null

		if(!islist(record))
			log_game("Campaign manifest rejected: the migration from schema version [from_version] failed.")
			return null
		if(record["schema_version"] != from_version + 1)
			log_game("Campaign manifest rejected: the migration from schema version [from_version] did not advance the version.")
			return null

	return record

/**
 * Schema 1 to 2: generations are counted.
 *
 * Version 1 stored no generation number, because a campaign only ever read the generation it was on. Naming
 * the *next* one without consulting older generations needs a count. A version 1 record describes whichever
 * generation it is on, so it becomes the first unless it already carries a usable number - which records
 * written between the field appearing and this version bump do.
 */
/proc/migrate_campaign_manifest_v1_to_v2(list/record)
	RETURN_TYPE(/list)
	var/existing_number = record["generation_number"]
	if(!isnum(existing_number) || existing_number < 1 || existing_number != round(existing_number))
		record["generation_number"] = 1
	record["schema_version"] = 2
	return record

/**
 * Schema 2 to 3: the colony carries its research between chapters.
 *
 * A campaign from before research was persisted has none recorded, so it starts from whatever a fresh techweb
 * gives it. Nothing it has already built is affected; only what it keeps from here on changes.
 */
/proc/migrate_campaign_manifest_v2_to_v3(list/record)
	RETURN_TYPE(/list)
	if(!islist(record["research_record"]))
		record["research_record"] = list()
	record["schema_version"] = 3
	return record

/**
 * Schema 3 to 4: the settlement carries its ledger between chapters.
 *
 * A campaign from before the ledger existed has no recorded history, so it starts with an empty one rather
 * than an invented balance. What it owns physically is unaffected; only what is written down changes.
 */
/proc/migrate_campaign_manifest_v3_to_v4(list/record)
	RETURN_TYPE(/list)
	if(!islist(record["ledger_record"]))
		record["ledger_record"] = list()
	record["schema_version"] = 4
	return record

/**
 * Schema 4 to 5: the colony remembers who lives in it.
 *
 * A campaign from before the roster existed has never written anybody down, so it starts with an empty one.
 * Everyone already playing it becomes a newcomer on their next chapter, which is the honest answer - the colony
 * genuinely has no record of what they did before this.
 */
/proc/migrate_campaign_manifest_v4_to_v5(list/record)
	RETURN_TYPE(/list)
	if(!islist(record["roster_record"]))
		record["roster_record"] = list()
	record["schema_version"] = 5
	return record

/**
 * Schema 5 to 6: the colony has a region around it.
 *
 * A campaign from before the overworld gets the standard region options and no discoveries, so its first boot
 * generates a region and reveals only what a colony can see from its own doorstep. Nothing about the colony
 * itself changes - the region is new ground beside it, not a replacement for the map it is standing on.
 */
/proc/migrate_campaign_manifest_v5_to_v6(list/record)
	RETURN_TYPE(/list)
	if(!islist(record["overworld_record"]))
		record["overworld_record"] = list()
	record["schema_version"] = 6
	return record

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

	var/list/migrated = migrate_campaign_manifest_record(data)
	if(!islist(migrated))
		return FALSE

	var/datum/campaign_manifest/candidate = new
	candidate.schema_version = migrated["schema_version"]
	candidate.campaign_id = migrated["campaign_id"]
	candidate.generation_id = migrated["generation_id"]
	candidate.generation_number = migrated["generation_number"]
	candidate.active_checkpoint_id = migrated["active_checkpoint_id"]
	candidate.planet_record = islist(migrated["planet_record"]) ? migrated["planet_record"] : list()
	candidate.research_record = islist(migrated["research_record"]) ? migrated["research_record"] : list()
	candidate.ledger_record = islist(migrated["ledger_record"]) ? migrated["ledger_record"] : list()
	candidate.roster_record = islist(migrated["roster_record"]) ? migrated["roster_record"] : list()
	candidate.overworld_record = islist(migrated["overworld_record"]) ? migrated["overworld_record"] : list()
	candidate.chapter = migrated["chapter"]
	candidate.campaign_clock = migrated["campaign_clock"]
	candidate.storyteller_state = islist(migrated["storyteller_state"]) ? migrated["storyteller_state"] : list()
	candidate.record_references = islist(migrated["record_references"]) ? migrated["record_references"] : list()
	candidate.last_outcome = migrated["last_outcome"]
	candidate.generation_closed = !!migrated["generation_closed"]
	candidate.closure_reason = migrated["closure_reason"]

	if(!candidate.validate())
		qdel(candidate)
		return FALSE

	schema_version = candidate.schema_version
	campaign_id = candidate.campaign_id
	generation_id = candidate.generation_id
	generation_number = candidate.generation_number
	active_checkpoint_id = candidate.active_checkpoint_id
	planet_record = candidate.planet_record
	research_record = candidate.research_record
	ledger_record = candidate.ledger_record
	roster_record = candidate.roster_record
	overworld_record = candidate.overworld_record
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
