/**
 * The colony's food store: the one thing that puts food into the campaign.
 *
 * Before the larder existed, every use of food was a spend and nothing anywhere was a source, so the figure
 * sat at zero forever and anything gated on it could never happen. These are mostly about the two rules that
 * keeps honest: the larder is what the number counts, and spending is all or nothing.
 */
/datum/unit_test/rimstation_colony_larder
	abstract_type = /datum/unit_test/rimstation_colony_larder

/// A larder on the test floor, with the ledger ready to mirror it.
/datum/unit_test/rimstation_colony_larder/proc/build_larder()
	RETURN_TYPE(/obj/structure/closet/crate/freezer/colony_larder)
	return allocate(/obj/structure/closet/crate/freezer/colony_larder, run_loc_floor_bottom_left)

/// Puts one loaf in and returns it. A loaf is ten nutriment, which is five units.
/datum/unit_test/rimstation_colony_larder/proc/stock_loaf(obj/structure/closet/crate/freezer/colony_larder/larder)
	RETURN_TYPE(/obj/item/food/bread/plain)
	var/obj/item/food/bread/plain/loaf = allocate(/obj/item/food/bread/plain)
	loaf.forceMove(larder)
	return loaf


/// Food is counted by what is in it, measured in nutriment rather than in objects.
/datum/unit_test/rimstation_colony_larder/counts_what_is_in_it

/datum/unit_test/rimstation_colony_larder/counts_what_is_in_it/Run()
	TEST_ASSERT_EQUAL(count_colony_food(), 0, "A colony with no larder reported food anyway.")

	var/obj/structure/closet/crate/freezer/colony_larder/larder = build_larder()
	TEST_ASSERT_EQUAL(count_colony_food(), 0, "An empty larder reported food in it.")
	TEST_ASSERT_EQUAL(get_colony_larder(), larder, "The colony could not find the larder that was just built.")

	// A loaf is ten nutriment and a unit is two, so a loaf stocks five.
	var/obj/item/food/bread/plain/loaf = stock_loaf(larder)
	TEST_ASSERT_EQUAL(food_units_in(loaf), 5, "A loaf of bread was not worth five units of food.")
	TEST_ASSERT_EQUAL(count_colony_food(), 5, "Putting a loaf in the larder did not stock the colony.")

	stock_loaf(larder)
	TEST_ASSERT_EQUAL(count_colony_food(), 10, "A second loaf did not add to the stores.")

	// Counted by nutriment, so nobody stocks a colony by filling it with things that are not food.
	var/obj/item/wrench/tool = allocate(/obj/item/wrench)
	tool.forceMove(larder)
	TEST_ASSERT_EQUAL(food_units_in(tool), 0, "A wrench was counted as food.")
	TEST_ASSERT_EQUAL(count_colony_food(), 10, "Putting a wrench in the larder fed the colony.")

	// Taking it back out is allowed: this is a box, not a one-way conversion.
	loaf.forceMove(run_loc_floor_bottom_left)
	TEST_ASSERT_EQUAL(count_colony_food(), 5, "Taking a loaf out of the larder did not reduce the stores.")


/// Spending food is all or nothing, and reaches for the scraps before the loaves.
/datum/unit_test/rimstation_colony_larder/spends_all_or_nothing

/datum/unit_test/rimstation_colony_larder/spends_all_or_nothing/Run()
	var/obj/structure/closet/crate/freezer/colony_larder/larder = build_larder()
	stock_loaf(larder)
	stock_loaf(larder)
	TEST_ASSERT_EQUAL(count_colony_food(), 10, "The test could not stock the larder.")

	// More than the colony has takes nothing at all, rather than emptying it and coming up short.
	TEST_ASSERT(!consume_colony_food(11, "test"), "The colony spent food it did not have.")
	TEST_ASSERT_EQUAL(count_colony_food(), 10, "A refused spend still ate the colony's food.")

	TEST_ASSERT(consume_colony_food(5, "test"), "The colony could not spend food it had.")
	TEST_ASSERT_EQUAL(count_colony_food(), 5, "Spending five units did not take five units.")

	TEST_ASSERT(consume_colony_food(5, "test"), "The colony could not spend the rest of its food.")
	TEST_ASSERT_EQUAL(count_colony_food(), 0, "The larder still held food after everything was spent.")

	// Smallest first, so a small bill does not break into a loaf while scraps are sitting there.
	var/obj/item/food/bread/plain/whole = stock_loaf(larder)
	var/obj/item/food/breadslice/plain/slice = allocate(/obj/item/food/breadslice/plain)
	slice.forceMove(larder)
	TEST_ASSERT_EQUAL(food_units_in(slice), 1, "A slice of bread was not worth one unit of food.")

	TEST_ASSERT(consume_colony_food(1, "test"), "The colony could not spend a single unit.")
	TEST_ASSERT(QDELETED(slice), "Spending one unit did not take the slice that covered it.")
	TEST_ASSERT(!QDELETED(whole), "Spending one unit broke into a whole loaf while a slice was available.")


/// The ledger's figure follows the larder, so anything reading the ledger reads the truth.
/datum/unit_test/rimstation_colony_larder/ledger_mirrors_the_larder

/datum/unit_test/rimstation_colony_larder/ledger_mirrors_the_larder/Run()
	var/datum/campaign_manifest/manifest = new("unit-test-larder", "generation-1")
	allocated += manifest
	var/saved_manifest = SScampaign.manifest
	var/datum/settlement_ledger/saved_ledger = SScampaign.ledger
	SScampaign.manifest = manifest
	SScampaign.ledger = new

	var/obj/structure/closet/crate/freezer/colony_larder/larder = build_larder()
	stock_loaf(larder)
	stock_loaf(larder)

	sync_colony_food_to_ledger()
	TEST_ASSERT_EQUAL(SScampaign.ledger.get_resource(COLONY_FOOD_RESOURCE), 10, "The ledger did not learn what the larder holds.")

	// Spending goes through the larder, and the ledger follows it down without being told separately.
	TEST_ASSERT(consume_colony_food(4, "test"), "The colony could not spend its food.")
	TEST_ASSERT_EQUAL(SScampaign.ledger.get_resource(COLONY_FOOD_RESOURCE), count_colony_food(), "The ledger and the larder disagree about how much food there is.")

	// The larder wins. A ledger figure that drifted for any reason is corrected to what is in the box, which is
	// the contract that makes the larder the only place food has to be kept right.
	SScampaign.adjust_resource(COLONY_FOOD_RESOURCE, 500, LEDGER_CATEGORY_ADMIN, "drift")
	TEST_ASSERT(SScampaign.ledger.get_resource(COLONY_FOOD_RESOURCE) > count_colony_food(), "The test could not create the drift it meant to correct.")
	sync_colony_food_to_ledger()
	TEST_ASSERT_EQUAL(SScampaign.ledger.get_resource(COLONY_FOOD_RESOURCE), count_colony_food(), "A recount did not put the ledger back to what the larder actually holds.")

	QDEL_NULL(SScampaign.ledger)
	SScampaign.manifest = saved_manifest
	SScampaign.ledger = saved_ledger


/**
 * Food that comes back has to come back as food.
 *
 * This is the bug the larder's own contract creates and that the first version of the expedition refund walked
 * straight into: the larder is authoritative, so anything that hands rations back by incrementing the ledger's
 * figure is handing back something the next recount deletes.
 */
/datum/unit_test/rimstation_colony_larder/returns_food_as_food

/datum/unit_test/rimstation_colony_larder/returns_food_as_food/Run()
	var/datum/campaign_manifest/manifest = new("unit-test-larder-return", "generation-1")
	allocated += manifest
	var/saved_manifest = SScampaign.manifest
	var/datum/settlement_ledger/saved_ledger = SScampaign.ledger
	SScampaign.manifest = manifest
	SScampaign.ledger = new

	var/obj/structure/closet/crate/freezer/colony_larder/larder = build_larder()
	stock_loaf(larder)
	stock_loaf(larder)
	sync_colony_food_to_ledger()
	TEST_ASSERT_EQUAL(count_colony_food(), 10, "The test could not stock the larder.")

	// Out for a journey, back at the end of it. A whole loaf is spent, because a party that needs five units
	// takes the loaf rather than five units out of the middle of it.
	TEST_ASSERT(consume_colony_food(5, "test expedition"), "The colony could not pack rations.")
	var/after_packing = count_colony_food()
	TEST_ASSERT_EQUAL(after_packing, 5, "Packing rations did not take them out of the larder.")

	TEST_ASSERT(return_colony_food(5, "test expedition returned"), "Unspent rations could not be returned.")
	TEST_ASSERT_EQUAL(count_colony_food(), 10, "Returned rations did not come back as food in the larder.")

	// The whole point: a recount must not undo the refund. An amount handed back as a ledger figure would
	// vanish exactly here.
	sync_colony_food_to_ledger()
	TEST_ASSERT_EQUAL(count_colony_food(), 10, "A recount deleted the rations that were handed back.")
	TEST_ASSERT_EQUAL(SScampaign.ledger.get_resource(COLONY_FOOD_RESOURCE), 10, "The ledger and the larder disagree after a refund.")

	// Coming back is exact even when the amount is not a whole loaf: loaves for the bulk, slices for the rest.
	// This is the half that has to be precise, because it is the half the colony is owed.
	var/before_odd_refund = count_colony_food()
	TEST_ASSERT(return_colony_food(3, "test"), "An awkward amount could not be returned.")
	TEST_ASSERT_EQUAL(count_colony_food(), before_odd_refund + 3, "An amount that is not a whole loaf did not come back exactly.")

	TEST_ASSERT(return_colony_food(7, "test"), "A mixed amount could not be returned.")
	TEST_ASSERT_EQUAL(count_colony_food(), before_odd_refund + 10, "Loaves and slices together did not add up to what was returned.")

	QDEL_NULL(SScampaign.ledger)
	SScampaign.manifest = saved_manifest
	SScampaign.ledger = saved_ledger


/// With no larder to put it in, food comes back as the money it would have been bought for.
/datum/unit_test/rimstation_colony_larder/returns_food_as_money_with_no_larder

/datum/unit_test/rimstation_colony_larder/returns_food_as_money_with_no_larder/Run()
	var/datum/campaign_manifest/manifest = new("unit-test-larder-nolarder", "generation-1")
	allocated += manifest
	var/saved_manifest = SScampaign.manifest
	var/datum/settlement_ledger/saved_ledger = SScampaign.ledger
	SScampaign.manifest = manifest
	SScampaign.ledger = new

	var/datum/bank_account/account = get_settlement_account()
	var/saved_balance = account?.account_balance
	if(account)
		account.account_balance = 1000

	TEST_ASSERT_NULL(get_colony_larder(), "This test needs a colony with no larder and found one.")
	TEST_ASSERT(return_colony_food(5, "test"), "Food could not be returned to a colony with no larder.")

	// Refunded at the rate it would have been bought in at, so the money ends up where it came from rather
	// than the rations quietly evaporating.
	TEST_ASSERT_EQUAL(account.account_balance, 1000 + (5 * COLONY_FOOD_CREDIT_PRICE), "Rations returned to a larderless colony were not refunded as credits.")

	if(account && !isnull(saved_balance))
		account.account_balance = saved_balance
	QDEL_NULL(SScampaign.ledger)
	SScampaign.manifest = saved_manifest
	SScampaign.ledger = saved_ledger
