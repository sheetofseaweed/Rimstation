/**
 * Puts an arriving player into the roster and moves them where they belong.
 *
 * Called with the player's ckey rather than their client so it can be driven without one. Returns the record
 * they were settled into, or null when there is no campaign - in which case the colonist is left standing
 * wherever the job put them, because an ordinary round has no colony to arrive at.
 */
/proc/settle_colonist(mob/living/body, player_ckey)
	RETURN_TYPE(/datum/colonist_record)
	if(!istype(body))
		return null

	var/datum/colonist_roster/colony = SScampaign.get_roster()
	if(!colony)
		return null

	var/datum/campaign_manifest/manifest = SScampaign.manifest
	var/datum/colonist_record/record = colony.find_or_create(
		player_ckey,
		body.real_name,
		generation_number = manifest.generation_number,
		chapter = manifest.chapter,
	)
	if(!record)
		return null

	// Read before binding, which is what credits attendance for this chapter and would otherwise make everybody
	// look like a returner from the moment they arrived.
	var/returning = record.chapters_attended > 0
	SScampaign.bind_colonist(body, record)

	// Before anything else touches them: the job has already dressed this body, and somebody who owns a
	// wardrobe must not be handed a second one.
	if(returning)
		withdraw_issued_outfit(body, record)

	// Onto the fresh mind the body was just built with, which is the only state set_experience() handles
	// correctly - see restore_colonist_skills().
	restore_colonist_skills(record, body.mind)

	// Somebody who was out on the road when the last chapter ended is still out there. Their belongings come
	// back here rather than at their locker, because they are about to be put somewhere they cannot walk to a
	// locker from.
	var/on_expedition = is_travelling_member(record.colonist_id)
	if(on_expedition)
		restore_traveller_belongings(body, record)

	var/turf/arrival = get_colonist_arrival_turf(record, returning)
	if(arrival)
		body.forceMove(arrival)
		log_game("Colony campaign [manifest.campaign_id]: [record.display_name] ([record.colonist_id]) arrived as a [returning ? "returning colonist" : "newcomer"] at [AREACOORD(arrival)].")
	else
		log_game("Colony campaign [manifest.campaign_id]: [record.display_name] ([record.colonist_id]) had nowhere to arrive; they are wherever the job put them.")

	// Only now, with a body standing somewhere real. Bringing an expedition's scene up sleeps, and doing this
	// before the arrival above would race it - the load can finish first and be undone by the arrival move.
	if(on_expedition)
		SSoverworld.resume_traveller(record.colonist_id)

	return record

/**
 * Where a colonist starts the chapter.
 *
 * Newcomers walk in from the edge of the map; people who already live here wake up at home. The chain falls
 * back rather than failing, because every step of it can legitimately be missing - a home whose bed was taken
 * apart, a core that was destroyed, a map without the landmark placed yet.
 */
/proc/get_colonist_arrival_turf(datum/colonist_record/record, returning)
	RETURN_TYPE(/turf)
	if(returning)
		var/turf/home = get_colonist_home_turf(record)
		if(home)
			return home

		var/turf/core_turf = get_turf(get_colony_core())
		if(core_turf)
			// Beside the core rather than on it, so a chapter with several returners does not stack them all
			// on one tile.
			var/turf/beside = get_step(core_turf, pick(GLOB.cardinals))
			return (beside && !beside.is_blocked_turf(TRUE)) ? beside : core_turf

	if(length(GLOB.rimstation_colony_spawns))
		var/obj/effect/landmark/rimstation_colony_spawn/landmark = pick(GLOB.rimstation_colony_spawns)
		return get_turf(landmark)

	return null

/**
 * The turf a colonist has claimed as home, or null if they have not claimed one or it is gone.
 *
 * Home points are claimed at a bed and stored as coordinates plus the type that was there. Both are checked on
 * arrival, because the map they were recorded against is not necessarily the map that loaded - a recovered
 * checkpoint can predate the bed entirely.
 */
/proc/get_colonist_home_turf(datum/colonist_record/record)
	RETURN_TYPE(/turf)
	var/list/home = record?.home_point
	if(!islist(home) || !length(home))
		return null

	var/turf/claimed = locate(home["x"], home["y"], home["z"])
	if(!claimed)
		return null

	var/expected_type = text2path(home["bed_type"])
	if(!ispath(expected_type) || !(locate(expected_type) in claimed))
		log_game("Colonist [record.colonist_id] has a home point at [home["x"]],[home["y"]],[home["z"]] with no [home["bed_type"]] on it; falling back.")
		return null

	return claimed
