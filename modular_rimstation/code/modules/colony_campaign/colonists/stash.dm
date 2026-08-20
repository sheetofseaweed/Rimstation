/**
 * Keeping what a colonist was wearing, without ever taking it off them.
 *
 * `/mob/living/carbon` is on the map save's blacklist, so the writer reaches a colonist, refuses them, and
 * never walks their contents - everything worn or carried is deleted at the end of every chapter. Anything
 * already inside a container survives fine, so the loss is specific to what is on a person.
 *
 * The fix uses a hook the serializer already has. `save_stored_contents()` takes an `extra_contents` list and
 * handles objects that are *not* in the container - it explicitly skips ones that are. Each declared object
 * gets a parent/child id pair and its own map block, and `link_loaded_containers()` moves it inside on load.
 *
 * So a container **declares** what its colonists are wearing rather than being packed with it. Nobody is
 * undressed, by a commit or by an admin's mid-round snapshot, and the clothes stay on the body throughout.
 * Saving must never be something a player can feel.
 */

/// Every colonist container that exists, so one can be found without scanning the world for it.
GLOBAL_LIST_EMPTY(colonist_storage_containers)

/// Which container is answerable for each colonist this write. See ensure_colonist_stash_assignment().
GLOBAL_LIST_EMPTY(colonist_stash_assignment)
/// TRUE once the assignment above has been worked out for the write in progress. An empty assignment is valid.
GLOBAL_VAR_INIT(colonist_stash_assignment_ready, FALSE)
/// Everything already declared this write. The guard against a colonist's belongings being written twice.
GLOBAL_LIST_EMPTY(colonist_declared_items)


/**
 * Anywhere a colonist's belongings can be kept.
 *
 * A closet subtype because that inherits contents persistence, opening, closing and deconstruction whole - the
 * only new behaviour is declaring what is on people who are still wearing it.
 */
/obj/structure/closet/colonist_storage
	name = "colonist storage"
	/// Whose this is, or null for shared storage. Survives a save; see get_save_vars().
	var/colonist_id

/obj/structure/closet/colonist_storage/Initialize(mapload)
	. = ..()
	GLOB.colonist_storage_containers += src

/obj/structure/closet/colonist_storage/Destroy()
	GLOB.colonist_storage_containers -= src
	// The assignment holds containers by reference, so one destroyed mid-write would be kept alive by it until
	// the write ended - a hard delete rather than a leak that resolves itself.
	for(var/colonist_id in GLOB.colonist_stash_assignment)
		if(GLOB.colonist_stash_assignment[colonist_id] == src)
			GLOB.colonist_stash_assignment -= colonist_id
	return ..()

/**
 * `name` and `colonist_id` are declared here because the base `/atom/get_save_vars()` does not include `name`
 * - the same gap behind the label defect - and because a locker that came back having forgotten whose it was
 * would hand its owner's belongings to the shared stash on the next save.
 */
/obj/structure/closet/colonist_storage/get_save_vars(save_flags = ALL)
	. = ..()
	. += NAMEOF(src, name)
	. += NAMEOF(src, colonist_id)
	return .

/obj/structure/closet/colonist_storage/on_object_saved(map_string, turf/current_loc, list/obj_blacklist)
	save_stored_contents(
		map_string,
		current_loc,
		obj_blacklist,
		declare_colonist_belongings(src),
		include_ids = FALSE,
	)


/// The colony's shared stash. Takes anybody who has not claimed a locker of their own.
/obj/structure/closet/colonist_storage/stash
	name = "colony stash"
	desc = "Where the settlement keeps what it is not carrying. Anything you are wearing ends up here between one day and the next."

/// One colonist's own locker. Their belongings go here instead of the shared stash.
/obj/structure/closet/colonist_storage/locker
	name = "colonist's locker"
	desc = "A locker with space for one person's life. Claim it and what you are wearing will be waiting here tomorrow."


/// The shared stash, or null if the colony has not built one.
/proc/get_main_colony_stash()
	RETURN_TYPE(/obj/structure/closet/colonist_storage/stash)
	for(var/obj/structure/closet/colonist_storage/stash/shared in GLOB.colonist_storage_containers)
		return shared
	return null

/// The locker `colonist_id` has claimed, or null.
/proc/get_personal_colonist_locker(colonist_id)
	RETURN_TYPE(/obj/structure/closet/colonist_storage/locker)
	if(!istext(colonist_id) || !length(colonist_id))
		return null

	for(var/obj/structure/closet/colonist_storage/locker/personal in GLOB.colonist_storage_containers)
		if(personal.colonist_id == colonist_id)
			return personal
	return null

/**
 * Decides once, for the whole write, which container is answerable for each colonist.
 *
 * Resolved centrally rather than by each container deciding for itself, because two containers that both
 * believed they held a colonist would each write a map block for the same worn items - and the colony would
 * come back with two of everything. Resolution is a pure function of the roster and the world, so it gives
 * the same answer no matter which container asks first.
 */
/proc/ensure_colonist_stash_assignment()
	if(GLOB.colonist_stash_assignment_ready)
		return

	GLOB.colonist_stash_assignment_ready = TRUE
	GLOB.colonist_stash_assignment = list()

	if(!CONFIG_GET(flag/campaign_equipment_persistence))
		return

	var/datum/colonist_roster/colony = SScampaign.get_roster()
	if(!colony)
		return

	var/obj/structure/closet/colonist_storage/stash/shared = get_main_colony_stash()
	for(var/colonist_id in colony.records)
		var/obj/structure/closet/colonist_storage/destination = get_personal_colonist_locker(colonist_id) || shared
		if(!destination)
			var/datum/colonist_record/record = colony.records[colonist_id]
			log_game("Colony campaign: [record.display_name] ([colonist_id]) has neither a locker nor a colony stash, so anything they are wearing will not survive this chapter.")
			continue
		GLOB.colonist_stash_assignment[colonist_id] = destination

/// Clears the per-write state above. Called from reset_write_map_state(), which bounds a single map write.
/proc/reset_colonist_stash_write_state()
	GLOB.colonist_stash_assignment_ready = FALSE
	GLOB.colonist_stash_assignment.Cut()
	GLOB.colonist_declared_items.Cut()

/**
 * Everything worn, pocketed or held by the colonists `container` is answerable for.
 *
 * Enumerated with get_equipped_items(), which returns top-level items only - so a backpack is declared as a
 * backpack and keeps its contents, where get_all_gear() would flatten it into loose items.
 *
 * The guard is independent of the assignment on purpose. Exclusive assignment is only correct while the
 * assignment logic is correct, and a bug there would silently double the colony's belongings; refusing to
 * declare anything twice makes that impossible even when the assignment is wrong, and says so out loud.
 */
/proc/declare_colonist_belongings(obj/structure/closet/colonist_storage/container)
	RETURN_TYPE(/list)
	var/list/declared = list()
	if(!istype(container))
		return declared

	ensure_colonist_stash_assignment()
	for(var/colonist_id in GLOB.colonist_stash_assignment)
		if(GLOB.colonist_stash_assignment[colonist_id] != container)
			continue

		var/mob/living/body = SScampaign.get_colonist_body(colonist_id)
		if(!body)
			continue

		for(var/obj/item/belonging as anything in body.get_equipped_items(INCLUDE_POCKETS|INCLUDE_HELD))
			if(GLOB.colonist_declared_items[belonging])
				stack_trace("[belonging] was declared for saving twice; the colonist stash assignment is wrong and would have duplicated it.")
				continue
			GLOB.colonist_declared_items[belonging] = TRUE
			declared += belonging

	return declared


/**
 * Takes back the starting kit from a colonist who already owns one. Returns how many items were withdrawn.
 *
 * The job dresses every arrival, because dress_up_as_job() runs long before anything knows who arrived - so a
 * returning colonist is handed a second uniform, a second bag and a second ID while their own are folded in a
 * locker. Left alone, a colony gains a spare set per person per chapter, forever.
 *
 * Called from settle_colonist(), which runs immediately after the job equips them and before they can pick
 * anything up, so everything they are wearing at that moment is the kit and nothing of their own.
 *
 * Nothing is issued to a returner and nothing accumulates: what they own is exactly what they stored. The one
 * exception is a returner with nothing waiting anywhere, who keeps the kit - losing a locker to a raid should
 * cost what was in it, not leave somebody with no way to play the chapter.
 */
/proc/withdraw_issued_outfit(mob/living/carbon/human/colonist, datum/colonist_record/record)
	if(!ishuman(colonist) || !istype(record))
		return 0
	// With persistence off nothing was ever stored, so the kit is all they will have.
	if(!CONFIG_GET(flag/campaign_equipment_persistence))
		return 0
	if(!colonist_has_belongings_waiting(record))
		return 0

	var/withdrawn = 0
	for(var/obj/item/issued in colonist.get_equipped_items(INCLUDE_POCKETS|INCLUDE_HELD))
		qdel(issued)
		withdrawn++

	if(withdrawn)
		log_game("Colony campaign: [record.display_name] ([record.colonist_id]) returned to a wardrobe of their own, so [withdrawn] issued items were withheld.")
	return withdrawn

/**
 * TRUE when there is something for `record` to get dressed from.
 *
 * A colonist with a locker owns what is in it and nothing else - an empty locker means they have nothing,
 * whatever else the colony is sitting on. Without one they draw from the shared stash, which is communal by
 * definition, so anything in it counts.
 */
/proc/colonist_has_belongings_waiting(datum/colonist_record/record)
	if(!istype(record))
		return FALSE

	var/obj/structure/closet/colonist_storage/locker/personal = get_personal_colonist_locker(record.colonist_id)
	if(personal)
		return length(personal.contents) > 0

	var/obj/structure/closet/colonist_storage/stash/shared = get_main_colony_stash()
	return shared && length(shared.contents) > 0

/**
 * Claims a locker, or hands back what is in it. Returns TRUE if anything happened.
 *
 * One locker per colonist: claiming a second releases the first, which is also the only way to give one up.
 */
/proc/claim_colonist_locker(mob/living/claimant, obj/structure/closet/colonist_storage/locker/target)
	if(!istype(claimant) || !istype(target))
		return FALSE

	var/datum/colonist_record/record = SScampaign.get_colonist_record_for_body(claimant)
	if(!record)
		to_chat(claimant, span_warning("You are not one of this colony's people."))
		return FALSE

	if(target.colonist_id == record.colonist_id)
		return return_colonist_belongings(target, claimant)

	if(target.colonist_id)
		var/datum/colonist_roster/colony = SScampaign.get_roster()
		var/datum/colonist_record/owner = colony?.get_record(target.colonist_id)
		to_chat(claimant, span_warning("This one is [owner ? owner.display_name : "somebody"]'s."))
		return FALSE

	var/obj/structure/closet/colonist_storage/locker/previous = get_personal_colonist_locker(record.colonist_id)
	if(previous)
		previous.colonist_id = null
		previous.name = initial(previous.name)

	target.colonist_id = record.colonist_id
	target.name = "[record.display_name]'s locker"
	to_chat(claimant, span_notice("You take [target] for your own[previous ? ", and give up your old one" : ""]."))
	log_game("Colony campaign: [record.display_name] ([record.colonist_id]) claimed a locker at [AREACOORD(target)].")
	return TRUE

/// Puts everything in `container` back on `colonist`, which is the point of storing it in the first place.
/proc/return_colonist_belongings(obj/structure/closet/colonist_storage/container, mob/living/colonist)
	if(!istype(container) || !istype(colonist))
		return FALSE

	var/returned = 0
	var/left_behind = 0
	for(var/obj/item/belonging in container.contents)
		relink_colonist_id(belonging, colonist)
		if(colonist.equip_to_appropriate_slot(belonging))
			returned++
		else
			left_behind++

	if(!returned && !left_behind)
		to_chat(colonist, span_notice("[container] is empty."))
		return FALSE

	to_chat(colonist, span_notice("You collect your things[left_behind ? ", though not everything fits" : ""]."))
	return TRUE


/**
 * Points a stored ID card at its owner's account for this round.
 *
 * Bank accounts are made fresh every round and are not saved anywhere, so a card that came off disk is
 * registered to an account that no longer exists. The account for the person collecting it does exist - it was
 * created when the job equipped them, and the id of it sits on the mob rather than on the card they were
 * issued, which is why deleting that card does not take the account with it.
 *
 * Cards that already point somewhere are left alone: somebody else's card in your locker stays theirs.
 */
/proc/relink_colonist_id(obj/item/card/id/card, mob/living/carbon/human/colonist)
	if(!istype(card) || !ishuman(colonist))
		return FALSE
	if(card.registered_account)
		return FALSE

	var/datum/bank_account/account = SSeconomy.bank_accounts_by_id["[colonist.account_id]"]
	if(!account)
		return FALSE

	card.set_account(account)
	return TRUE

/obj/structure/closet/colonist_storage/locker/click_alt(mob/living/user)
	if(!isliving(user) || !SScampaign.is_campaign_active())
		return NONE
	if(!SScampaign.get_colonist_record_for_body(user))
		return NONE

	claim_colonist_locker(user, src)
	return CLICK_ACTION_SUCCESS

/obj/structure/closet/colonist_storage/stash/click_alt(mob/living/user)
	if(!isliving(user) || !SScampaign.is_campaign_active())
		return NONE
	if(!SScampaign.get_colonist_record_for_body(user))
		return NONE

	return_colonist_belongings(src, user)
	return CLICK_ACTION_SUCCESS

/obj/structure/closet/colonist_storage/locker/examine(mob/user)
	. = ..()
	if(!SScampaign.is_campaign_active())
		return

	if(!colonist_id)
		. += span_notice("Nobody has claimed this. <b>Alt-click</b> to make it yours.")
		return

	var/datum/colonist_record/record = SScampaign.get_colonist_record_for_body(user)
	if(record?.colonist_id == colonist_id)
		. += span_notice("This one is yours. <b>Alt-click</b> to collect your things.")

/obj/structure/closet/colonist_storage/stash/examine(mob/user)
	. = ..()
	if(SScampaign.is_campaign_active() && SScampaign.get_colonist_record_for_body(user))
		. += span_notice("<b>Alt-click</b> to collect your things.")
