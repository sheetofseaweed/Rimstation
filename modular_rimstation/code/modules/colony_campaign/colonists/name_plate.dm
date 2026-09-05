/**
 * A name plate, and the only way a colonist gets a locker of their own.
 *
 * Nothing built or placed a personal locker before this, so the claim system in stash.dm was unreachable and
 * everybody shared the one stash. Made rather than mapped: which container somebody keeps their life in is the
 * colony's decision, not the mapper's.
 */
/obj/item/colonist_name_plate
	name = "name plate"
	desc = "A small board with room for one name. Nail it to a container and that container is yours - whatever you are wearing will be waiting in it tomorrow."
	icon = 'icons/obj/wallmounts.dmi'
	icon_state = "noticeboard"
	w_class = WEIGHT_CLASS_SMALL
	resistance_flags = FLAMMABLE
	custom_materials = list(/datum/material/wood = SHEET_MATERIAL_AMOUNT)

/datum/crafting_recipe/colonist_name_plate
	name = "Name Plate"
	result = /obj/item/colonist_name_plate
	reqs = list(/obj/item/stack/sheet/mineral/wood = 1)
	time = 2 SECONDS
	category = CAT_FURNITURE

/obj/item/colonist_name_plate/interact_with_atom(atom/interacting_with, mob/living/user, list/modifiers)
	if(!istype(interacting_with, /obj/structure/closet))
		return NONE

	var/obj/structure/closet/target = interacting_with
	var/refusal = why_container_cannot_be_claimed(target, user)
	if(refusal)
		balloon_alert(user, refusal)
		return ITEM_INTERACT_BLOCKING

	user.balloon_alert_to_viewers("nailing a plate on...")
	if(!do_after(user, 3 SECONDS, target = target))
		return ITEM_INTERACT_BLOCKING

	// Asked again: the container can be opened, welded or climbed into while somebody works on it.
	refusal = why_container_cannot_be_claimed(target, user)
	if(refusal)
		balloon_alert(user, refusal)
		return ITEM_INTERACT_BLOCKING

	var/obj/structure/closet/colonist_storage/locker/claimed = convert_closet_to_colonist_locker(target, user)
	if(!claimed)
		balloon_alert(user, "it won't take the plate!")
		return ITEM_INTERACT_BLOCKING

	claim_colonist_locker(user, claimed)
	qdel(src)
	return ITEM_INTERACT_SUCCESS

/**
 * Why `target` cannot be made into somebody's locker, as a balloon alert, or null when it can.
 *
 * One proc rather than a run of checks at the call site because the same question is asked twice - once to
 * refuse early, and once after the delay, when any of these answers may have changed.
 */
/proc/why_container_cannot_be_claimed(obj/structure/closet/target, mob/living/user)
	if(!istype(target) || QDELETED(target))
		return "not a container!"
	if(istype(target, /obj/structure/closet/colonist_storage))
		return "already the colony's!"
	if(!SScampaign.is_campaign_active())
		return "no colony to claim it from!"
	if(!SScampaign.get_colonist_record_for_body(user))
		return "not one of this colony!"
	if(target.welded || target.locked)
		return "it's sealed!"
	// Converting means replacing, and replacing a container with somebody inside it would move a person.
	if(locate(/mob/living) in target)
		return "someone's in there!"
	return null

/**
 * Replaces `target` with a colonist's locker standing in the same place, holding the same things.
 *
 * A replacement rather than a conversion because the storage behaviour is a closet subtype: what makes a locker
 * persist is `on_object_saved()`, which an ordinary closet does not have and cannot be given in place.
 */
/proc/convert_closet_to_colonist_locker(obj/structure/closet/target, mob/living/user)
	RETURN_TYPE(/obj/structure/closet/colonist_storage/locker)
	var/turf/spot = get_turf(target)
	if(!spot)
		return null

	var/was_open = target.opened
	var/obj/structure/closet/colonist_storage/locker/claimed = new(spot)

	// Carried over, not tipped onto the floor. A locker that emptied itself when claimed is worse than none.
	for(var/obj/item/kept in target.contents.Copy())
		kept.forceMove(claimed)

	log_game("Colony campaign: [key_name(user)] made [target] at [AREACOORD(spot)] into a colonist's locker.")
	qdel(target)

	if(was_open)
		claimed.open(user)
	return claimed
