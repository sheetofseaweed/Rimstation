/**
 * Carrying what a colonist learned from one chapter to the next.
 *
 * Skill is the one part of a colonist a player genuinely cannot bring back themselves. Their name and face
 * arrive from preferences every round and the people they played with remember the rest, but a mind is built
 * untrained every time - so a colony that does not write this down has nobody who is visibly better at
 * building than they were six chapters ago.
 *
 * All ten skills in this build are stored. None of them is secret or round-only, so an allowlist would be
 * maintenance for no benefit; if a round-only skill is ever added, this is where it would be excluded.
 */

/**
 * Reads a mind's skills into a record. Returns TRUE if anything was written.
 *
 * Only trained skills are stored. A record should describe what somebody learned rather than listing the nine
 * things they never touched, and an absent entry restores as untrained anyway.
 *
 * Reads the live mind every time rather than adjusting what is already in the record, which is what makes this
 * safe to call twice: a retried commit recomputes the same answer instead of decaying an already-decayed one.
 */
/proc/capture_colonist_skills(datum/colonist_record/record, datum/mind/mind)
	if(!istype(record) || !istype(mind))
		return FALSE

	var/decay = CONFIG_GET(number/campaign_skill_decay_per_chapter)
	var/list/captured = list()
	for(var/skill_type in GLOB.skill_types)
		var/experience = decay_colonist_experience(mind.get_skill_exp(skill_type), decay)
		if(experience > 0)
			captured["[skill_type]"] = experience

	record.skills = captured
	return TRUE

/**
 * Puts a record's skills back into a mind. Returns TRUE if the record was usable.
 *
 * Restored through set_experience() rather than by assigning the numbers, because level, the traits a level
 * grants, and the status effects some skills apply on level-up are all derived by that call. It is given a
 * fresh mind in practice - a returning colonist gets a new body every chapter - which matters, because
 * set_experience() passes the *old experience* where adjust_experience() expects an old level, and only
 * behaves on a mind whose experience is still zero.
 *
 * A stored skill this build no longer has costs the colonist that skill, not their whole history.
 */
/proc/restore_colonist_skills(datum/colonist_record/record, datum/mind/mind)
	if(!istype(record) || !istype(mind))
		return FALSE

	for(var/stored_path in record.skills)
		var/experience = record.skills[stored_path]
		if(!isnum(experience) || experience <= 0)
			continue

		var/skill_type = text2path(stored_path)
		// Checked against the live list rather than with ispath(), so a typepath that exists but is not a skill
		// - or an abstract parent nobody can hold - is refused rather than written into known_skills.
		if(!skill_type || !(skill_type in GLOB.skill_types))
			log_game("Colonist [record.colonist_id] carried skill '[stored_path]', which this build no longer has.")
			continue

		mind.set_experience(skill_type, experience, silent = TRUE)

	return TRUE

/**
 * How much of `experience` survives one chapter at `decay`.
 *
 * Decay is the counterweight to carryover: without one, a colonist only ever ratchets upward, because nothing
 * in a campaign ever takes skill away. The right rate cannot be judged before several chapters have actually
 * been played, so the shipped default is zero - and zero has to mean exactly nothing happens.
 *
 * A rate off a config file is clamped rather than trusted: a negative one would hand out experience nobody
 * earned, and one above 1 would owe a colonist negative skill.
 */
/proc/decay_colonist_experience(experience, decay)
	if(!isnum(experience) || experience <= 0)
		return 0
	if(!isnum(decay) || decay <= 0)
		return experience

	return round(max(0, experience * (1 - min(decay, 1))))
