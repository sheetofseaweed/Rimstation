/**
 * The colony's food store, and the only thing that puts food into the campaign.
 *
 * The settlement ledger tracks food as a number, but until this existed nothing anywhere produced that number
 * - every use of it was a spend, so it sat at zero forever and anything gated on it could never happen. This
 * is the producer: a place to put food, which is what makes the number mean something.
 *
 * The larder is authoritative and the ledger mirrors it. That direction matters: food you can see in a box is
 * the thing players reason about, and a stored number that disagreed with the box would be the version that
 * was wrong. Anything that spends food takes it out of here and then re-syncs, so the two can only agree.
 */

/// Every larder in the colony. Small, and only ever walked when food is counted or spent.
GLOBAL_LIST_EMPTY(colony_larders)

/obj/structure/closet/crate/freezer/colony_larder
	name = "colony larder"
	desc = "The settlement's food store. What is in here is what the colony has to live on, and what an \
		expedition eats on the road."

/obj/structure/closet/crate/freezer/colony_larder/Initialize(mapload)
	. = ..()
	GLOB.colony_larders += src
	// Contents can change without the crate being touched - somebody reaching in, an item decomposing, a
	// bluespace bag emptying into it - so the count is refreshed from the contents rather than tallied on the
	// way in. Registering here just means the common cases update immediately instead of at the next read.
	RegisterSignal(src, COMSIG_ATOM_ENTERED, PROC_REF(on_stock_changed))
	RegisterSignal(src, COMSIG_ATOM_EXITED, PROC_REF(on_stock_changed))

/obj/structure/closet/crate/freezer/colony_larder/Destroy()
	GLOB.colony_larders -= src
	return ..()

/obj/structure/closet/crate/freezer/colony_larder/proc/on_stock_changed(datum/source, atom/movable/thing)
	SIGNAL_HANDLER
	// Deferred: this fires mid-move, and the contents are only settled once that has finished.
	INVOKE_ASYNC(GLOBAL_PROC, GLOBAL_PROC_REF(sync_colony_food_to_ledger))

/obj/structure/closet/crate/freezer/colony_larder/examine(mob/user)
	. = ..()
	. += span_notice("It holds [count_colony_food()] units of food.")

/// The larder the colony stocks, or null if nobody has built one.
/proc/get_colony_larder()
	RETURN_TYPE(/obj/structure/closet/crate/freezer/colony_larder)
	for(var/obj/structure/closet/crate/freezer/colony_larder/larder in GLOB.colony_larders)
		if(!QDELETED(larder))
			return larder
	return null

/**
 * What one item is worth as stored food.
 *
 * Measured in nutriment rather than counted per item, so a loaf is worth more than a slice of it and nobody
 * can stock the colony with a hundred pieces of bait. Every nutriment subtype counts - protein, vitamin and
 * fat are all food.
 */
/proc/food_units_in(obj/item/thing)
	if(!istype(thing) || !thing.reagents)
		return 0

	var/nutriment = 0
	for(var/datum/reagent/held as anything in thing.reagents.reagent_list)
		if(istype(held, /datum/reagent/consumable/nutriment))
			nutriment += held.volume

	return round(nutriment / COLONY_FOOD_UNIT_NUTRIMENT)

/// How much food the colony is holding, counted from the larder itself.
/proc/count_colony_food()
	var/obj/structure/closet/crate/freezer/colony_larder/larder = get_colony_larder()
	if(!larder)
		return 0

	var/total = 0
	for(var/obj/item/stored in larder.contents)
		total += food_units_in(stored)
	return total

/**
 * Makes the ledger's food figure equal what is actually in the larder.
 *
 * The larder wins every time. That is the whole contract: if something ever debits the ledger's food without
 * taking it out of the larder, this will put it back, so food must always be spent through
 * `consume_colony_food()` rather than through `adjust_resource()` directly.
 */
/proc/sync_colony_food_to_ledger()
	var/datum/settlement_ledger/settlement = SScampaign.get_ledger()
	if(!settlement)
		return FALSE

	var/counted = count_colony_food()
	var/recorded = settlement.get_resource(COLONY_FOOD_RESOURCE)
	var/difference = counted - recorded
	if(!difference)
		return FALSE

	SScampaign.adjust_resource(
		COLONY_FOOD_RESOURCE,
		difference,
		LEDGER_CATEGORY_UPKEEP,
		difference > 0 ? "food stored" : "food taken from stores",
	)
	return TRUE

/**
 * Takes food out of the larder. Returns TRUE only if the whole amount was there.
 *
 * All or nothing, and checked before anything is destroyed: half-eating a journey's rations would leave the
 * colony poorer for a trip that never happened.
 *
 * Smallest items go first, so a request for four units spends four slices of bread before it spends a whole
 * loaf. Overshooting is accepted rather than refused - food does not divide - but taking the least of it that
 * covers the bill keeps the waste down.
 */
/proc/consume_colony_food(units, reason_code, related_id)
	if(!isnum(units) || units <= 0)
		return TRUE
	if(count_colony_food() < units)
		return FALSE

	var/obj/structure/closet/crate/freezer/colony_larder/larder = get_colony_larder()
	if(!larder)
		return FALSE

	var/list/edible = list()
	for(var/obj/item/stored in larder.contents)
		if(food_units_in(stored) > 0)
			edible += stored
	sortTim(edible, GLOBAL_PROC_REF(cmp_food_units_asc))

	var/taken = 0
	for(var/obj/item/stored as anything in edible)
		if(taken >= units)
			break
		taken += food_units_in(stored)
		qdel(stored)

	sync_colony_food_to_ledger()
	log_game("Colony larder: [taken] units of food taken([reason_code || "no reason"], [related_id || "nothing"]).")
	return TRUE

/// Smallest first, so spending food reaches for the scraps before the loaves.
/proc/cmp_food_units_asc(obj/item/first, obj/item/second)
	return food_units_in(first) - food_units_in(second)

/**
 * What buying in the shortfall would cost, in credits.
 *
 * A colony that has not stocked its larder is not stopped from travelling, it just pays merchant prices for
 * rations instead of eating its own. The rate matches what the refugee incident already charges for the same
 * thing, so food has one price across the campaign.
 */
/proc/colony_food_shortfall_price(units)
	var/short = max(0, units - count_colony_food())
	return short * COLONY_FOOD_CREDIT_PRICE

/**
 * Pays for `units` of food however the colony can: out of the larder first, then out of its budget.
 *
 * Returns TRUE only if the whole amount was covered. Nothing is taken unless everything can be.
 */
/proc/pay_for_colony_food(units, reason_code, related_id)
	if(!isnum(units) || units <= 0)
		return TRUE

	var/stored = count_colony_food()
	if(stored >= units)
		return consume_colony_food(units, reason_code, related_id)

	// Short. Buy the difference first, because credits are the part that can fail - taking the food out and
	// then discovering the colony cannot afford the rest would leave it with neither.
	var/shortfall = units - stored
	var/price = shortfall * COLONY_FOOD_CREDIT_PRICE
	if(!SScampaign.try_debit(price, LEDGER_CATEGORY_UPKEEP, reason_code || "bought in rations", null, related_id))
		return FALSE

	if(stored > 0 && !consume_colony_food(stored, reason_code, related_id))
		// Could not take what it said it had. Give the money back rather than charging for nothing.
		SScampaign.credit(price, LEDGER_CATEGORY_UPKEEP, "rations refunded", null, related_id)
		return FALSE

	log_game("Colony larder: bought in [shortfall] units of food for [price] credits([reason_code || "no reason"]).")
	return TRUE

/// Why the colony cannot put this much food together, or null if it can.
/proc/colony_food_problem(units)
	if(!isnum(units) || units <= 0)
		return null

	var/stored = count_colony_food()
	if(stored >= units)
		return null

	var/price = (units - stored) * COLONY_FOOD_CREDIT_PRICE
	var/datum/bank_account/account = get_settlement_account()
	if(!account || account.account_balance < price)
		return "The colony has [stored] of the [units] food this needs, and cannot afford the [price] credits to buy in the rest."
	return null
