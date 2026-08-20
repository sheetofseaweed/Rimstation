/**
 * One person the colony remembers.
 *
 * Deliberately thin. A player's preferences already carry their character's name, face, species and quirks into
 * every round, and the other players in the round remember who did what - so the campaign stores only what
 * neither of those can supply: what a colonist learned, how long they have been here, and whether they are
 * still alive. Appearance, bodies, minds, inventories and round secrets are all somebody else's business.
 *
 * Thinness is the feature. Because this record never claims to know what a colonist looks like, a player may
 * freely redesign their character between chapters, skip a chapter, or come back as somebody new, and there is
 * no conflict to resolve. Widen it and those conflicts appear, along with the rules needed to settle them.
 */
/datum/colonist_record
	/// Campaign-issued identity. Everything else keys on this, never on the player's ckey.
	var/colonist_id
	/// The name the colony knows them by, as first written down.
	var/display_name
	/// Which player usually plays them. A lookup field so a returning player is recognised - never the key.
	var/owner_ckey
	/**
	 * Which generation they first arrived in.
	 *
	 * Constant for every colonist in a given roster today, since a roster dies with its generation. Kept
	 * because a record that is read on its own - copied into a memorial, or inspected in a file by hand -
	 * should say which world it belonged to rather than requiring the surrounding manifest to explain it.
	 */
	var/generation_joined = 1
	/// Which chapter of that generation they first arrived in.
	var/chapter_joined = 1
	/// How many chapters they have actually been played in.
	var/chapters_attended = 0
	/// One of COLONIST_STATUSES.
	var/status = COLONIST_STATUS_ACTIVE
	/// Skill experience, keyed by skill typepath as text. Filled by the skill adapters.
	var/list/skills
	/// Where they sleep, or null if they have not claimed anywhere. Shape belongs to the home-point code.
	var/list/home_point

/datum/colonist_record/New(colonist_id, display_name, owner_ckey)
	. = ..()
	src.colonist_id = colonist_id
	src.display_name = display_name
	src.owner_ckey = owner_ckey
	skills = list()

/// The value that decides whether two sightings are the same person. See colonist_identity_key().
/datum/colonist_record/proc/identity_key()
	return colonist_identity_key(owner_ckey, display_name)

/// Flat list form for JSON storage. Keep in step with deserialize() and COLONIST_RECORD_FIELDS.
/datum/colonist_record/proc/serialize()
	RETURN_TYPE(/list)
	return list(
		"colonist_id" = colonist_id,
		"display_name" = display_name,
		"owner_ckey" = owner_ckey,
		"generation_joined" = generation_joined,
		"chapter_joined" = chapter_joined,
		"chapters_attended" = chapters_attended,
		"status" = status,
		"skills" = skills?.Copy() || list(),
		"home_point" = home_point?.Copy(),
	)

/**
 * Loads a record produced by serialize(). Returns TRUE on success.
 *
 * Two different failures, treated differently on purpose. A record whose identity does not make sense - no id,
 * no name, a status the campaign does not have - is refused outright, because there is no person there to
 * restore. A record whose *values* are wrong, like a negative skill, keeps the person and drops the value: a
 * colonist should not cease to exist because a number next to their name was edited badly.
 */
/datum/colonist_record/proc/deserialize(list/data)
	if(!islist(data))
		return FALSE

	var/incoming_id = data["colonist_id"]
	if(!istext(incoming_id) || !length(incoming_id))
		log_game("Colonist record rejected: no usable colonist id.")
		return FALSE

	var/incoming_name = data["display_name"]
	if(!istext(incoming_name) || !length(trim(incoming_name)))
		log_game("Colonist record rejected: colonist '[incoming_id]' has no name.")
		return FALSE

	var/incoming_status = data["status"]
	var/list/known_statuses = COLONIST_STATUSES
	if(!(incoming_status in known_statuses))
		log_game("Colonist record rejected: colonist '[incoming_id]' is in unknown state '[incoming_status]'.")
		return FALSE

	var/incoming_generation = data["generation_joined"]
	if(!is_stored_whole_number(incoming_generation, 1))
		log_game("Colonist record rejected: colonist '[incoming_id]' joined in impossible generation '[incoming_generation]'.")
		return FALSE

	var/incoming_chapter = data["chapter_joined"]
	if(!is_stored_whole_number(incoming_chapter, 1))
		log_game("Colonist record rejected: colonist '[incoming_id]' joined in impossible chapter '[incoming_chapter]'.")
		return FALSE

	var/incoming_attendance = data["chapters_attended"]
	if(!is_stored_whole_number(incoming_attendance, 0))
		log_game("Colonist record rejected: colonist '[incoming_id]' has attended '[incoming_attendance]' chapters.")
		return FALSE

	// Skills come off disk, so a corrupted entry must not leave a colonist worse than untrained at something.
	var/list/incoming_skills = list()
	if(islist(data["skills"]))
		for(var/skill_path in data["skills"])
			var/experience = data["skills"][skill_path]
			if(istext(skill_path) && isnum(experience) && experience >= 0)
				incoming_skills[skill_path] = experience

	colonist_id = incoming_id
	display_name = incoming_name
	owner_ckey = istext(data["owner_ckey"]) ? data["owner_ckey"] : null
	generation_joined = incoming_generation
	chapter_joined = incoming_chapter
	chapters_attended = incoming_attendance
	status = incoming_status
	skills = incoming_skills
	var/list/incoming_home = data["home_point"]
	home_point = (islist(incoming_home) && length(incoming_home)) ? incoming_home.Copy() : null
	return TRUE


/**
 * The value that decides whether two sightings are the same colonist.
 *
 * Player and character name together, because neither works alone: one player may live in the colony as several
 * people, and two players may independently pick the same name. Names arrive from a text field, so spacing and
 * capitalisation are normalised away - a player who types their own name slightly differently one evening is
 * still the same colonist. Returns null when there is not enough to identify anyone.
 */
/proc/colonist_identity_key(ckey, name)
	if(!istext(ckey) || !length(ckey))
		return null
	if(!istext(name))
		return null
	var/normalized = lowertext(trim(name))
	if(!length(normalized))
		return null
	return "[ckey]|[normalized]"

/// TRUE when `value` is a whole number no smaller than `minimum`. Records come off disk; floats and text do not.
/proc/is_stored_whole_number(value, minimum)
	return isnum(value) && value >= minimum && ISINTEGER(value)
