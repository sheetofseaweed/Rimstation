/**
 * Claiming a bed as the place a colonist wakes up.
 *
 * Chosen rather than remembered, deliberately. Recording where somebody logged off would put them back inside
 * a wall the first time a checkpoint rolled back past the room they were standing in, and there would be no
 * way to tell a good coordinate from a stale one. A claimed bed is a thing the colony can look for before it
 * sends anybody anywhere, and a colonist decides where home is rather than discovering it.
 *
 * The record stores coordinates plus the type that was standing on them. Reading it back lives with arrival,
 * in get_colonist_home_turf().
 */

/**
 * Claims `target` as `claimant`'s home, moves their existing claim, or gives it up. Returns TRUE if anything
 * changed.
 *
 * Claiming the bed they already live in releases it, because otherwise there is no way to stop having a home
 * short of destroying the bed.
 */
/proc/claim_colonist_home(mob/living/claimant, obj/structure/bed/target)
	if(!istype(claimant) || !istype(target))
		return FALSE

	var/datum/colonist_record/record = SScampaign.get_colonist_record_for_body(claimant)
	if(!record)
		to_chat(claimant, span_warning("You are not one of this colony's people, so you have nowhere to make a home."))
		return FALSE

	var/turf/spot = get_turf(target)
	if(!spot)
		return FALSE

	if(is_colonist_home_turf(record, spot))
		record.home_point = null
		SScampaign.sync_roster()
		to_chat(claimant, span_notice("You gather your things. [target] is no longer yours."))
		return TRUE

	var/datum/colonist_record/occupant = find_colonist_home_holder(spot)
	if(occupant && occupant != record)
		to_chat(claimant, span_warning("[occupant.display_name] already sleeps here."))
		return FALSE

	record.home_point = list(
		"x" = spot.x,
		"y" = spot.y,
		"z" = spot.z,
		"bed_type" = "[target.type]",
	)
	SScampaign.sync_roster()
	to_chat(claimant, span_notice("You make up [target]. This is where you will wake up."))
	log_game("Colony campaign: [record.display_name] ([record.colonist_id]) claimed a home at [AREACOORD(spot)].")
	return TRUE

/// TRUE when `record` already calls `spot` home. Compared by coordinates, which is what a home point stores.
/proc/is_colonist_home_turf(datum/colonist_record/record, turf/spot)
	var/list/home = record?.home_point
	if(!islist(home) || !length(home) || !isturf(spot))
		return FALSE
	return home["x"] == spot.x && home["y"] == spot.y && home["z"] == spot.z

/// Which colonist, if any, has claimed `spot`. Scanned rather than indexed - a roster is a handful of people.
/proc/find_colonist_home_holder(turf/spot)
	RETURN_TYPE(/datum/colonist_record)
	var/datum/colonist_roster/colony = SScampaign.get_roster()
	if(!colony)
		return null

	for(var/colonist_id in colony.records)
		var/datum/colonist_record/record = colony.records[colonist_id]
		if(is_colonist_home_turf(record, spot))
			return record
	return null


// A colony's beds are somebody's, and the game already puts alt-click and a screentip on this object - so the
// claim goes where a player is already looking rather than into a verb nobody would find.
/obj/structure/bed/click_alt(mob/living/user)
	if(!isliving(user) || !SScampaign.is_campaign_active())
		return NONE
	if(!SScampaign.get_colonist_record_for_body(user))
		return NONE

	claim_colonist_home(user, src)
	return CLICK_ACTION_SUCCESS

/obj/structure/bed/examine(mob/user)
	. = ..()
	if(!SScampaign.is_campaign_active())
		return

	var/datum/colonist_record/occupant = find_colonist_home_holder(get_turf(src))
	if(occupant)
		. += span_notice("[occupant.display_name] sleeps here.")
	else if(SScampaign.get_colonist_record_for_body(user))
		. += span_notice("Nobody has made this their own. <b>Alt-click</b> to claim it.")

/obj/structure/bed/add_context(atom/source, list/context, obj/item/held_item, mob/living/user)
	. = ..()
	if(held_item || !SScampaign.is_campaign_active())
		return .

	var/datum/colonist_record/record = SScampaign.get_colonist_record_for_body(user)
	if(!record)
		return .

	context[SCREENTIP_CONTEXT_ALT_LMB] = is_colonist_home_turf(record, get_turf(src)) ? "Give up home" : "Claim as home"
	return CONTEXTUAL_SCREENTIP_SET
