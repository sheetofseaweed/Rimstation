/**
 * Cards that come back from a checkpoint point at accounts that no longer exist.
 *
 * A bank account is built fresh every round and cannot be saved: a card holds a datum reference and a map file
 * holds text. So every ID card loaded from a checkpoint reads as registered to nobody, and the colonist holding
 * it cannot be paid, cannot pay, and cannot use a vendor.
 *
 * Relinking by hand through an ID console is one step too many for a colony to reliably do, so the card links
 * itself as soon as its owner is carrying it. The name printed on the card is the test - the card says whose it
 * is - so nobody can quietly point a stranger's card at their own account.
 *
 * This is the general path. A card collected out of a colonist's own stash takes [relink_colonist_id] instead,
 * which needs no name match because the locker already established whose it is.
 */

/**
 * Points an unlinked card at its owner's account for this round, when the carrier is the owner.
 *
 * Cards that already point somewhere are left alone: a card registered to a live account is either correct or
 * somebody's deliberate forgery, and neither is this proc's business.
 */
/proc/try_relink_carried_id(obj/item/card/id/card, mob/living/carbon/human/carrier)
	if(!istype(card) || !ishuman(carrier))
		return FALSE
	if(card.registered_account || !card.registered_name)
		return FALSE
	if(card.registered_name != carrier.real_name)
		return FALSE

	var/datum/bank_account/account = SSeconomy.bank_accounts_by_id["[carrier.account_id]"]
	if(!account)
		return FALSE

	card.set_account(account)
	log_game("Colony ID card '[card.registered_name]' was relinked to the account of [key_name(carrier)].")
	return TRUE

/**
 * Relinks every card an item carries, for one carrier.
 *
 * A PDA is checked as well as a bare card because that is where most cards are. Without it the relink would
 * miss the case the colony actually hits.
 */
/proc/relink_ids_carried_in(obj/item/carried, mob/living/carbon/human/carrier)
	if(!istype(carried))
		return FALSE

	if(istype(carried, /obj/item/card/id))
		return try_relink_carried_id(carried, carrier)

	var/obj/item/modular_computer/computer = carried
	if(!istype(computer))
		return FALSE

	. = try_relink_carried_id(computer.stored_id, carrier)
	return try_relink_carried_id(computer.alt_stored_id, carrier) || .

/// Relinks every card a colonist is already carrying, wherever on them it is.
/proc/relink_all_carried_ids(mob/living/carbon/human/carrier)
	if(!ishuman(carrier))
		return FALSE

	. = FALSE
	for(var/obj/item/carried in carrier.get_all_contents())
		. = relink_ids_carried_in(carried, carrier) || .
	return .
