/// How long a breach must persist before each infection roll.
#define QUARIAN_BREACH_ROLL_INTERVAL (10 SECONDS)
/// Chance per roll of catching something through an open suit.
#define QUARIAN_BREACH_INFECTION_CHANCE 15
/// The same chance while quarian antibodies are in the bloodstream.
#define QUARIAN_BREACH_INFECTION_CHANCE_TREATED 1

/// The four slots that together make a sealed suit, as list(slot, required type).
/// A flat list of pairs, not an assoc one: DM treats a numeric assoc key as a list index.
GLOBAL_LIST_INIT(quarian_suit_pieces, list(
	list(ITEM_SLOT_HEAD, /obj/item/clothing/head/helmet/space/quarian),
	list(ITEM_SLOT_ICLOTHING, /obj/item/clothing/under/quarian),
	list(ITEM_SLOT_GLOVES, /obj/item/clothing/gloves/quarian),
	list(ITEM_SLOT_FEET, /obj/item/clothing/shoes/quarian),
))

/**
 * Watches a quarian's enviro-suit and makes them ill while it is open.
 *
 * One component on the mob rather than hooks on each garment: the source build copy-pasted the same
 * pickup/dropped/equipped bodies into all four, and its infection timer rescheduled itself forever,
 * surviving death and species change. This starts and stops with the seal and dies with its mob.
 */
/datum/component/quarian_suit_integrity
	/// Whether all four pieces were on at the last check.
	var/sealed = TRUE
	/// Seconds of open suit banked since the last infection roll.
	var/exposure = 0

/datum/component/quarian_suit_integrity/Initialize()
	if(!ishuman(parent))
		return COMPONENT_INCOMPATIBLE

/datum/component/quarian_suit_integrity/RegisterWithParent()
	RegisterSignal(parent, COMSIG_MOB_EQUIPPED_ITEM, PROC_REF(on_item_equipped))
	RegisterSignal(parent, COMSIG_MOB_UNEQUIPPED_ITEM, PROC_REF(on_item_unequipped))
	RegisterSignal(parent, COMSIG_LIVING_DEATH, PROC_REF(on_death))
	RegisterSignal(parent, COMSIG_LIVING_REVIVE, PROC_REF(on_revive))
	check_seal(silent = TRUE)

/datum/component/quarian_suit_integrity/UnregisterFromParent()
	UnregisterSignal(parent, list(COMSIG_MOB_EQUIPPED_ITEM, COMSIG_MOB_UNEQUIPPED_ITEM, COMSIG_LIVING_DEATH, COMSIG_LIVING_REVIVE))
	STOP_PROCESSING(SSprocessing, src)

/datum/component/quarian_suit_integrity/Destroy(force)
	STOP_PROCESSING(SSprocessing, src)
	return ..()

/datum/component/quarian_suit_integrity/proc/on_item_equipped(datum/source, obj/item/thing, slot)
	SIGNAL_HANDLER
	check_seal()

/datum/component/quarian_suit_integrity/proc/on_item_unequipped(datum/source, obj/item/thing)
	SIGNAL_HANDLER
	// /mob/living/carbon/human/doUnEquip() sends this from its parent call and only nulls the slot var
	// afterwards, so the garment is still in its slot right now. Discount it explicitly.
	check_seal(ignoring = thing)

/datum/component/quarian_suit_integrity/proc/on_death(datum/source)
	SIGNAL_HANDLER
	STOP_PROCESSING(SSprocessing, src)

/datum/component/quarian_suit_integrity/proc/on_revive(datum/source)
	SIGNAL_HANDLER
	check_seal(silent = TRUE)

/// TRUE only while every one of the four slots holds its quarian piece.
/// `ignoring` is a garment on its way out that still reads as worn.
/datum/component/quarian_suit_integrity/proc/is_sealed(obj/item/ignoring)
	var/mob/living/carbon/human/quarian = parent
	for(var/list/piece as anything in GLOB.quarian_suit_pieces)
		var/obj/item/worn = quarian.get_item_by_slot(piece[1])
		if(worn == ignoring || !istype(worn, piece[2]))
			return FALSE
	return TRUE

/// Recomputes the seal and starts or stops the exposure clock to match.
/datum/component/quarian_suit_integrity/proc/check_seal(silent = FALSE, obj/item/ignoring)
	var/mob/living/carbon/human/quarian = parent
	var/now_sealed = is_sealed(ignoring)
	if(now_sealed == sealed)
		return

	sealed = now_sealed
	if(sealed)
		exposure = 0
		STOP_PROCESSING(SSprocessing, src)
		if(!silent)
			to_chat(quarian, span_notice("Your suit seals. The air stops tasting of other people."))
		return

	if(!silent)
		to_chat(quarian, span_userdanger("Your suit is open!"))
	if(quarian.stat != DEAD)
		START_PROCESSING(SSprocessing, src)

/datum/component/quarian_suit_integrity/process(seconds_per_tick)
	var/mob/living/carbon/human/quarian = parent
	if(sealed || quarian.stat == DEAD)
		return PROCESS_KILL

	exposure += seconds_per_tick * 1 SECONDS
	if(exposure < QUARIAN_BREACH_ROLL_INTERVAL)
		return

	exposure = 0
	roll_infection()

/// Percent chance of catching something on a single roll. Antibodies are what move it.
/datum/component/quarian_suit_integrity/proc/get_infection_chance()
	var/mob/living/carbon/human/quarian = parent
	if(quarian.has_reagent(/datum/reagent/medicine/quarian_antibodies))
		return QUARIAN_BREACH_INFECTION_CHANCE_TREATED
	return QUARIAN_BREACH_INFECTION_CHANCE

/// One infection roll. Returns TRUE if something was caught.
/datum/component/quarian_suit_integrity/proc/roll_infection()
	if(!prob(get_infection_chance()))
		return FALSE

	return infect()

/// Gives the quarian a fresh illness of their own. Split out so tests can force one.
/datum/component/quarian_suit_integrity/proc/infect()
	var/mob/living/carbon/human/quarian = parent
	var/datum/disease/advance/random/illness = new(3, 3)
	illness.carrier = TRUE
	// A quarian's own weak immune system is the story here, not a station plague, so it does not spread.
	illness.update_spread_flags(DISEASE_SPREAD_NON_CONTAGIOUS)
	return quarian.ForceContractDisease(illness, make_copy = FALSE, del_on_fail = TRUE)


/datum/species/quarian/on_species_gain(mob/living/carbon/human/human_who_gained_species, datum/species/old_species, pref_load, regenerate_icons = TRUE, replace_missing = TRUE)
	. = ..()
	// Preview dummies live in the character menu for the whole round, so they get no infection clock.
	if(isdummy(human_who_gained_species))
		return
	human_who_gained_species.AddComponent(/datum/component/quarian_suit_integrity)

/datum/species/quarian/on_species_loss(mob/living/carbon/human/human, datum/species/new_species, pref_load)
	. = ..()
	qdel(human.GetComponent(/datum/component/quarian_suit_integrity))

#undef QUARIAN_BREACH_ROLL_INTERVAL
#undef QUARIAN_BREACH_INFECTION_CHANCE
#undef QUARIAN_BREACH_INFECTION_CHANCE_TREATED
