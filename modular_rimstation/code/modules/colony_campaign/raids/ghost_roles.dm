/**
 * Letting ghosts fight in a raid that never needed them.
 *
 * The raid is assembled and deployed complete, under AI, before any of this runs. A volunteer replaces a unit
 * that was already going to attack, so nobody's arrival makes the raid larger and nobody's absence makes it
 * smaller - which is what lets a raid be scheduled by the storyteller without knowing whether anyone is
 * watching. A colony must never be safer because the server is empty.
 *
 * Almost none of this is new machinery. `/datum/component/ghost_direct_control` already offers a living mob to
 * ghosts and hands the body over, and the AI controller already stands down when a client arrives
 * (`on_sentience_gained`) and picks the mob back up when one leaves (`on_sentience_lost`). Disconnecting
 * mid-raid therefore returns a raider to the attack rather than abandoning it, and no code here has to notice.
 */

/**
 * Makes one attacker claimable by a ghost.
 *
 * Deliberately does not poll. A poll per raider would fire a dozen prompts at every ghost in the space of a
 * second and expire long before the fight got interesting; instead each attacker joins the spawners menu for
 * the whole raid, so a ghost can take one when the fighting reaches somewhere worth being.
 */
/datum/colony_raid/proc/offer_to_ghosts(mob/living/attacker)
	if(!istype(attacker))
		return FALSE

	// Backslashes because AddComponent is a macro, and a macro call cannot span lines without them.
	attacker.AddComponent(\
		/datum/component/ghost_direct_control,\
		ban_type = ROLE_TRAITOR,\
		poll_candidates = FALSE,\
		joinable_mobs_title = "Colony Raiders",\
		assumed_control_message = span_boldwarning("You are one of the raiders. Take what the colony has and get back out - the settlement remembers what it loses."),\
		after_assumed_control = CALLBACK(src, PROC_REF(on_attacker_claimed), attacker),\
	)
	return TRUE

/**
 * Tells ghosts once that there is a raid to join.
 *
 * One announcement for the whole attack rather than one per attacker. The raid has already deployed by the
 * time this runs, so nothing is waiting on an answer and an empty server changes nothing.
 */
/datum/colony_raid/proc/offer_raid_to_ghosts()
	var/living_attackers = living_attacker_count()
	if(!living_attackers)
		return FALSE

	notify_ghosts(
		"A raid is closing on the colony from the [telemetry?.insertion_direction || "distance"]. [living_attackers] attackers can be taken over from the spawners menu.",
		source = get_colony_core(),
		header = "Colony Raid",
		notify_flags = NOTIFY_CATEGORY_NOFLASH,
	)
	return TRUE

/**
 * Moves a unit from the AI column to the played one.
 *
 * Recorded rather than acted on: the unit keeps its objective, its faction and its orders, because a raider a
 * player is steering is still one of the raid's attackers and the director must not start treating it as a
 * separate thing.
 */
/datum/colony_raid/proc/on_attacker_claimed(mob/living/attacker)
	if(!telemetry)
		return FALSE

	telemetry.controlled_units++
	telemetry.ai_units = max(0, telemetry.ai_units - 1)
	log_game("Colony raid [raid_id]: [key_name(attacker)] took over [attacker].")
	return TRUE
