/**
 * What the colony has been through, and how much slack it needs.
 *
 * The storyteller is good at pacing a shift and has no idea what happened last chapter. This is the memory it
 * is missing: how old the campaign is, what has gone wrong lately, and how long since the last real threat.
 *
 * It lives in the manifest's `storyteller_state`, which has been carried and migrated since Phase 2 with
 * nothing reading it. So this needs no new schema - it fills a field that was already being preserved.
 *
 * The two scores are deliberately different things. **Loss** is what just went wrong, and it fades on its own.
 * **Recovery** is how much the colony is owed, and it only comes down through quiet chapters that went well -
 * so a settlement cannot be battered, handed one good round, and immediately thrown back into the fire.
 */
/datum/colony_story_state
	var/schema_version = COLONY_STORY_SCHEMA_VERSION
	/// Chapters completed across the whole campaign, generations included.
	var/campaign_age = 0
	/// Chapters completed by the generation currently standing.
	var/chapter_age = 0
	/// What has gone wrong recently, 0 to 100. Fades with time.
	var/recent_loss = 0
	/// How much easier the colony's next chapter should be, 0 to 100. Falls only through quiet success.
	var/recovery = 0
	/// Campaign age at which the colony last faced something serious.
	var/last_major_threat_chapter = 0
	/// Recent incident results, newest last. Bounded, because pacing should not read ancient history.
	var/list/recent_incidents
	/// Incident categories the storyteller has recently been given, newest last.
	var/list/storyteller_history

/datum/colony_story_state/New()
	. = ..()
	recent_incidents = list()
	storyteller_history = list()

/**
 * Records that something cost the colony.
 *
 * Severity is the incident's own pressure change, so an incident says how hard it was rather than this having
 * to work it out from the outside. Both scores are clamped, so no run of disasters can push them somewhere the
 * multipliers cannot come back from.
 */
/datum/colony_story_state/proc/record_loss(severity)
	if(!isnum(severity) || severity <= 0)
		return FALSE

	recent_loss = clamp(recent_loss + (severity * 8), 0, 100)
	recovery = clamp(recovery + (severity * 6), 0, 100)
	return TRUE

/// Records that the colony came out of something ahead. Relief is smaller than damage, deliberately.
/datum/colony_story_state/proc/record_relief(severity)
	if(!isnum(severity) || severity >= 0)
		return FALSE

	recent_loss = clamp(recent_loss + (severity * 4), 0, 100)
	return TRUE

/// Notes that the colony faced something serious, so pacing knows how long it has been since the last one.
/datum/colony_story_state/proc/record_major_threat()
	last_major_threat_chapter = campaign_age
	return TRUE

/// Files an incident result and keeps the window short.
/datum/colony_story_state/proc/record_incident(list/record)
	if(!islist(record))
		return FALSE

	recent_incidents += list(record)
	while(length(recent_incidents) > COLONY_STORY_INCIDENT_WINDOW)
		recent_incidents.Cut(1, 2)

	var/pressure = record["pressure_change"]
	if(isnum(pressure))
		if(pressure > 0)
			record_loss(pressure)
		else
			record_relief(pressure)
	return TRUE

/// Notes which category the storyteller was given, so the campaign can see its own recent shape.
/datum/colony_story_state/proc/record_storyteller_choice(incident_category)
	if(!incident_category)
		return FALSE

	storyteller_history += incident_category
	while(length(storyteller_history) > COLONY_STORY_INCIDENT_WINDOW)
		storyteller_history.Cut(1, 2)
	return TRUE

/**
 * Closes a chapter and ages the campaign.
 *
 * Recovery falls only when a chapter both succeeded and stayed quiet. A chapter that was won at the cost of a
 * serious fight was not a rest, and treating it as one is how a colony ends up permanently on the back foot.
 */
/datum/colony_story_state/proc/advance_chapter(outcome, faced_major_threat = FALSE)
	campaign_age++
	chapter_age++

	// Loss fades on its own; it is a memory of the last thing, not a debt.
	recent_loss = clamp(recent_loss - 20, 0, 100)

	if(faced_major_threat)
		record_major_threat()
		return TRUE

	if(outcome == COLONY_OUTCOME_SUCCESS)
		recovery = clamp(recovery - 25, 0, 100)
	return TRUE

/// A new generation is a new colony. It inherits the campaign's age and none of its scars.
/datum/colony_story_state/proc/reset_for_new_generation()
	chapter_age = 0
	recent_loss = 0
	recovery = 0
	last_major_threat_chapter = campaign_age
	recent_incidents = list()
	storyteller_history = list()
	return TRUE

/// How long since the colony last faced something serious, in chapters.
/datum/colony_story_state/proc/chapters_since_major_threat()
	return max(0, campaign_age - last_major_threat_chapter)

/**
 * How much more or less likely an event with these tags should be right now.
 *
 * Pure: same state and same tags always give the same answer, so pacing can be reasoned about and tested
 * without running a round. Bounded at both ends - a multiplier that can reach zero silently retires an event,
 * and one that can grow without limit crowds out everything else.
 */
/datum/colony_story_state/proc/get_event_weight_multiplier(list/event_tags)
	if(!length(event_tags))
		return 1

	var/scale = clamp(recovery, 0, 100) / 100
	if(!scale)
		return 1

	var/multiplier = 1
	if((TAG_COMBAT in event_tags) || (TAG_DESTRUCTIVE in event_tags))
		// A battered colony gets fewer disasters, but never none at all.
		multiplier = 1 - (0.7 * scale)
	else if((TAG_POSITIVE in event_tags) || (TAG_NEUTRAL in event_tags))
		multiplier = 1 + (1 * scale)

	return clamp(multiplier, COLONY_STORY_MIN_MULTIPLIER, COLONY_STORY_MAX_MULTIPLIER)

/// The same judgement for an incident category rather than a tag set.
/datum/colony_story_state/proc/get_category_multiplier(incident_category)
	switch(incident_category)
		if(COLONY_INCIDENT_CATEGORY_ENVIRONMENTAL)
			return get_event_weight_multiplier(list(TAG_DESTRUCTIVE))
		if(COLONY_INCIDENT_CATEGORY_POSITIVE)
			return get_event_weight_multiplier(list(TAG_POSITIVE))
		if(COLONY_INCIDENT_CATEGORY_NEUTRAL, COLONY_INCIDENT_CATEGORY_SOCIAL, COLONY_INCIDENT_CATEGORY_RESOURCE)
			return get_event_weight_multiplier(list(TAG_NEUTRAL))
	return 1

/// TRUE when the colony is too battered to be handed another disaster.
/datum/colony_story_state/proc/is_recovering_hard()
	return recovery >= COLONY_STORY_HARD_RECOVERY

/datum/colony_story_state/proc/serialize()
	RETURN_TYPE(/list)
	return list(
		"schema_version" = schema_version,
		"campaign_age" = campaign_age,
		"chapter_age" = chapter_age,
		"recent_loss" = recent_loss,
		"recovery" = recovery,
		"last_major_threat_chapter" = last_major_threat_chapter,
		"recent_incidents" = recent_incidents.Copy(),
		"storyteller_history" = storyteller_history.Copy(),
	)

/**
 * Loads a story state. Returns TRUE on success.
 *
 * Scores come off disk, so they are clamped rather than trusted. A hand-edited record must not be able to put
 * the colony permanently beyond the reach of any event.
 */
/datum/colony_story_state/proc/deserialize(list/data)
	if(!islist(data))
		return FALSE

	var/incoming_version = data["schema_version"]
	if(!isnum(incoming_version) || incoming_version != COLONY_STORY_SCHEMA_VERSION)
		log_game("Colony story state rejected: unsupported schema version '[incoming_version]'.")
		return FALSE

	campaign_age = max(0, isnum(data["campaign_age"]) ? data["campaign_age"] : 0)
	chapter_age = max(0, isnum(data["chapter_age"]) ? data["chapter_age"] : 0)
	recent_loss = clamp(isnum(data["recent_loss"]) ? data["recent_loss"] : 0, 0, 100)
	recovery = clamp(isnum(data["recovery"]) ? data["recovery"] : 0, 0, 100)
	last_major_threat_chapter = max(0, isnum(data["last_major_threat_chapter"]) ? data["last_major_threat_chapter"] : 0)
	recent_incidents = islist(data["recent_incidents"]) ? data["recent_incidents"] : list()
	storyteller_history = islist(data["storyteller_history"]) ? data["storyteller_history"] : list()
	return TRUE
