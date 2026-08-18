/**
 * Everyone the colony has known this generation.
 *
 * The roster is what makes a settlement a place people come back to rather than a map that happens to reload.
 * It is owned by the campaign and stored inside the manifest, so it is committed, rolled back and lost exactly
 * alongside the world it describes - a colony that falls takes its people with it, and the next generation
 * starts with strangers. That is what makes a long attendance record mean anything.
 *
 * It is keyed by campaign-issued id, never by ckey. Player association is a field on a record, so that a
 * colonist can outlive a player's absence rather than depending on it.
 */
/datum/colonist_roster
	var/schema_version = COLONY_ROSTER_SCHEMA_VERSION
	/// Colonist id to /datum/colonist_record.
	var/list/records
	/// Counter behind the next issued id. Stored, so a reload cannot hand out an id that is already taken.
	var/next_colonist_number = 1

/datum/colonist_roster/New()
	. = ..()
	records = list()

/datum/colonist_roster/Destroy()
	QDEL_LIST_ASSOC_VAL(records)
	records = null
	return ..()

/datum/colonist_roster/proc/get_record(colonist_id)
	RETURN_TYPE(/datum/colonist_record)
	return records[colonist_id]

/**
 * Recognises a returning colonist, or writes down a new one.
 *
 * Generation and chapter are passed in rather than read from the campaign, because a roster describes people
 * and should not also have to know what the campaign is currently doing. They are only used when somebody is
 * new: a returning colonist keeps the arrival they already have.
 */
/datum/colonist_roster/proc/find_or_create(ckey, name, generation_number = 1, chapter = 1)
	RETURN_TYPE(/datum/colonist_record)
	var/datum/colonist_record/existing = find_by_identity(ckey, name)
	if(existing)
		return existing

	if(isnull(colonist_identity_key(ckey, name)))
		return null

	var/datum/colonist_record/record = new(issue_colonist_id(), trim(name), ckey)
	record.generation_joined = generation_number
	record.chapter_joined = chapter
	if(!add_record(record))
		qdel(record)
		return null
	return record

/// The record for this player and character name, or null if the colony has not met them.
/datum/colonist_roster/proc/find_by_identity(ckey, name)
	RETURN_TYPE(/datum/colonist_record)
	var/wanted = colonist_identity_key(ckey, name)
	if(isnull(wanted))
		return null

	for(var/colonist_id in records)
		var/datum/colonist_record/record = records[colonist_id]
		if(record.identity_key() == wanted)
			return record
	return null

/// Adds a record the roster does not already have. Returns FALSE if its id is taken, leaving the holder alone.
/datum/colonist_roster/proc/add_record(datum/colonist_record/record)
	if(!istype(record) || !istext(record.colonist_id) || !length(record.colonist_id))
		return FALSE
	if(records[record.colonist_id])
		return FALSE

	records[record.colonist_id] = record
	return TRUE

/**
 * Issues an id nobody on this roster holds.
 *
 * A counter would be enough on its own within one roster. The random suffix is there for the day two rosters
 * meet - a colonist copied into a memorial, or a campaign merged by hand - where two separate counters would
 * otherwise both be confidently holding "colonist-3".
 */
/datum/colonist_roster/proc/issue_colonist_id()
	var/issued
	do
		issued = "colonist-[next_colonist_number]-[random_string(4, GLOB.hex_characters)]"
		next_colonist_number++
	while(records[issued])
	return issued

/// Flat list form for JSON storage. Keep in step with deserialize().
/datum/colonist_roster/proc/serialize()
	RETURN_TYPE(/list)
	var/list/stored = list()
	for(var/colonist_id in records)
		var/datum/colonist_record/record = records[colonist_id]
		stored += list(record.serialize())

	return list(
		"schema_version" = schema_version,
		"next_colonist_number" = next_colonist_number,
		"records" = stored,
	)

/**
 * Loads a roster produced by serialize(). Returns TRUE on success.
 *
 * A single unusable record is dropped rather than taken as grounds to refuse the roster. Refusing would mean a
 * colony forgets everybody because one entry was edited badly, which is a far worse answer than forgetting the
 * one person whose entry no longer makes sense. The drop is logged either way.
 */
/datum/colonist_roster/proc/deserialize(list/data)
	if(!islist(data))
		return FALSE

	var/incoming_version = data["schema_version"]
	if(!isnum(incoming_version) || incoming_version != COLONY_ROSTER_SCHEMA_VERSION)
		log_game("Colonist roster rejected: unsupported schema version '[incoming_version]'.")
		return FALSE

	var/list/incoming_records = list()
	if(islist(data["records"]))
		for(var/list/entry as anything in data["records"])
			if(!islist(entry))
				continue

			var/datum/colonist_record/record = new
			if(!record.deserialize(entry))
				qdel(record)
				continue
			if(incoming_records[record.colonist_id])
				log_game("Colonist roster dropped a second record claiming id '[record.colonist_id]'.")
				qdel(record)
				continue

			incoming_records[record.colonist_id] = record

	// The counter has to be at least past everyone already here, or the next colonist admitted after a reload
	// collides with somebody the colony already remembers.
	var/incoming_number = data["next_colonist_number"]
	if(!is_stored_whole_number(incoming_number, 1))
		incoming_number = 1
	incoming_number = max(incoming_number, length(incoming_records) + 1)

	QDEL_LIST_ASSOC_VAL(records)
	records = incoming_records
	next_colonist_number = incoming_number
	schema_version = COLONY_ROSTER_SCHEMA_VERSION
	return TRUE

/// Every record, as a plain list. For readouts and counting; the roster keeps ownership.
/datum/colonist_roster/proc/all_records()
	RETURN_TYPE(/list)
	var/list/everyone = list()
	for(var/colonist_id in records)
		everyone += records[colonist_id]
	return everyone

/// How many colonists are in a given status right now.
/datum/colonist_roster/proc/count_by_status(wanted_status)
	var/tally = 0
	for(var/colonist_id in records)
		var/datum/colonist_record/record = records[colonist_id]
		if(record.status == wanted_status)
			tally++
	return tally
