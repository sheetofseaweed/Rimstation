/**
 * The post a caravan musters at, and the reminder that you signed on to meet there.
 *
 * An expedition used to leave the moment everybody clicked ready, wherever in the colony they happened to be
 * standing. That reads as teleporting away rather than setting out, and it gives the rest of the colony no
 * warning that four of its people are about to vanish. So departure now has a place: everyone signed on has to
 * be standing at the post before the caravan will move.
 *
 * The gathering rule is deliberately generous - three tiles, not one - because a departure that fails on
 * somebody being one step out of position is a departure nobody can work out how to fix.
 */

/// Every muster point in the colony. Small; only walked when a departure is being checked.
GLOBAL_LIST_EMPTY(caravan_hitching_posts)

/obj/structure/caravan_hitching_post
	name = "hitching post"
	desc = "A weathered rail for tying up pack animals. Expeditions muster here before setting out."
	icon = 'modular_rimstation/icons/obj/structures/caravan.dmi'
	icon_state = "hitching_post"
	anchored = TRUE
	density = FALSE
	max_integrity = 200
	/// TRUE while the whole party is standing close enough to leave, so the lantern can say so.
	var/mustered = FALSE

/obj/structure/caravan_hitching_post/Initialize(mapload)
	. = ..()
	GLOB.caravan_hitching_posts += src

/obj/structure/caravan_hitching_post/Destroy()
	GLOB.caravan_hitching_posts -= src
	return ..()

/obj/structure/caravan_hitching_post/examine(mob/user)
	. = ..()
	var/datum/overworld_party/party = SScampaign.get_active_party()
	if(!party || !party.is_planning())
		. += span_notice("Nothing is mustering here.")
		return

	var/gathered = length(party_members_at_post(party))
	. += span_notice("[gathered] of [length(party.member_ids)] signed on are gathered here.")
	if(gathered < length(party.member_ids))
		. += span_warning("The caravan will not leave until everyone is within [OVERWORLD_GATHER_RADIUS] paces.")

/**
 * Setting out.
 *
 * The post is the departure control rather than the table, because the table can be anywhere and the party is
 * required to be here. A caravan that had to be sent from a console across the colony needed somebody who was
 * not going to press the button - and a lone traveller could never leave at all, since one person cannot stand
 * in two rooms.
 */
/obj/structure/caravan_hitching_post/attack_hand(mob/living/user, list/modifiers)
	. = ..()
	if(.)
		return
	return set_out(user)

/// Sends the caravan, if the person asking is on it and everything it needs is true.
/obj/structure/caravan_hitching_post/proc/set_out(mob/living/user)
	var/datum/overworld_party/party = SScampaign.get_active_party()
	if(!party)
		to_chat(user, span_warning("No expedition is mustering here. Sign one on at an expedition table first."))
		return TRUE
	if(!party.is_planning())
		to_chat(user, span_warning("This expedition has already left."))
		return TRUE

	// Only somebody who is going may give the word. A bystander sending other people out of the colony is how
	// the old console button worked, and it was never what anybody meant by it.
	var/datum/colonist_record/traveller = SScampaign.get_colonist_record_for_body(user)
	if(!traveller || !(traveller.colonist_id in party.member_ids))
		to_chat(user, span_warning("You are not signed on to this expedition."))
		return TRUE

	var/refused = SScampaign.depart_party()
	if(refused)
		to_chat(user, span_warning(refused))
		return TRUE

	visible_message(span_notice("[user] gives the word, and the caravan moves off."))
	party.announce_departure()
	return TRUE

/// Lights the lantern once everybody is here, so the post itself says whether the caravan can leave.
/obj/structure/caravan_hitching_post/proc/set_mustered(new_mustered)
	if(mustered == new_mustered)
		return FALSE
	mustered = new_mustered
	icon_state = mustered ? "hitching_post_ready" : "hitching_post"
	update_appearance()
	return TRUE

/// The post the colony musters at, or null if nobody has built one.
/proc/get_caravan_hitching_post()
	RETURN_TYPE(/obj/structure/caravan_hitching_post)
	for(var/obj/structure/caravan_hitching_post/post in GLOB.caravan_hitching_posts)
		if(!QDELETED(post))
			return post
	return null

/**
 * Which of a party's members are standing at the post.
 *
 * Returns colonist ids rather than bodies, because that is what every caller wants to compare against the
 * membership - and because a body is a thing that can stop existing between being found and being used.
 */
/proc/party_members_at_post(datum/overworld_party/party)
	RETURN_TYPE(/list)
	var/list/gathered = list()
	var/obj/structure/caravan_hitching_post/post = get_caravan_hitching_post()
	if(!post || !party)
		return gathered

	for(var/colonist_id in party.member_ids)
		var/mob/living/body = SScampaign.get_colonist_body(colonist_id)
		if(!body || body.stat == DEAD)
			continue
		if(get_dist(body, post) <= OVERWORLD_GATHER_RADIUS)
			gathered += colonist_id
	return gathered

/**
 * Keeps everyone's sign-on reminder in step with who is actually on the party.
 *
 * Driven from the one funnel every party edit already goes through, so there is no path that changes the
 * membership without the alerts following. Somebody who withdrew stops being reminded; somebody who joined
 * starts being.
 */
/proc/refresh_caravan_alerts(datum/overworld_party/party)
	var/datum/colonist_roster/roster = SScampaign.get_roster()
	if(!roster)
		return FALSE

	// Only while the party is still gathering. Once it has left, the people on it are somewhere else entirely
	// and a reminder to go and stand by a post would be nonsense.
	var/gathering = party?.is_planning()

	for(var/colonist_id in roster.records)
		var/mob/living/body = SScampaign.get_colonist_body(colonist_id)
		if(!body)
			continue

		var/should_have_it = gathering && (colonist_id in party.member_ids)
		if(should_have_it)
			body.apply_status_effect(/datum/status_effect/caravan_signed_on)
		else
			body.remove_status_effect(/datum/status_effect/caravan_signed_on)
	return TRUE

/// Updates the post's lantern to match whether the party could leave right now.
/proc/refresh_hitching_post(datum/overworld_party/party)
	var/obj/structure/caravan_hitching_post/post = get_caravan_hitching_post()
	if(!post)
		return FALSE

	var/ready = party?.is_planning() && length(party.member_ids) && !length(party.member_ids - party_members_at_post(party))
	return post.set_mustered(ready)


/**
 * The reminder that you have signed on to an expedition.
 *
 * Exists because signing on happens at a table and departing happens at a post, which can be a long way apart
 * and a long time later. Without it, the commonest way for a caravan to fail to leave is one person having
 * forgotten they were on it.
 */
/datum/status_effect/caravan_signed_on
	id = "caravan_signed_on"
	duration = STATUS_EFFECT_PERMANENT
	status_type = STATUS_EFFECT_UNIQUE
	alert_type = /atom/movable/screen/alert/status_effect/caravan_signed_on

/atom/movable/screen/alert/status_effect/caravan_signed_on
	name = "Signed On"
	desc = "You have signed on to an expedition. Gather at the hitching post; the caravan will not leave without you."
