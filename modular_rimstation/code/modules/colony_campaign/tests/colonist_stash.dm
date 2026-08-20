/**
 * A colonist's belongings are declared for saving while they are still wearing them.
 *
 * The whole design rests on this: carbons are excluded from the map save, so worn items are deleted every
 * chapter unless something else claims them. Declaring rather than packing is what lets that happen without
 * anybody being undressed by a commit, an autosave, or an admin's mid-round snapshot.
 */
/datum/unit_test/rimstation_colonist_chapter/stash_declares_worn_items

/datum/unit_test/rimstation_colonist_chapter/stash_declares_worn_items/Run()
	begin_test_campaign()

	var/datum/colonist_record/vera = SScampaign.roster.find_or_create("playerone", "Vera Holt", generation_number = 1, chapter = 1)
	var/mob/living/carbon/human/vera_body = allocate(/mob/living/carbon/human/consistent, run_loc_floor_bottom_left)
	TEST_ASSERT(SScampaign.bind_colonist(vera_body, vera), "A colonist could not be bound to a body.")

	var/obj/item/storage/backpack/pack = allocate(/obj/item/storage/backpack, run_loc_floor_bottom_left)
	TEST_ASSERT(vera_body.equip_to_appropriate_slot(pack), "The test could not put a backpack on a colonist.")

	var/obj/structure/closet/colonist_storage/stash/shared = allocate(/obj/structure/closet/colonist_storage/stash, run_loc_floor_top_right)

	reset_colonist_stash_write_state()
	var/list/declared = declare_colonist_belongings(shared)
	TEST_ASSERT(pack in declared, "A colonist's backpack was not declared for saving, so it would be deleted with them.")

	// The point of declaring rather than packing: the colonist is still wearing it.
	TEST_ASSERT_EQUAL(pack.loc, vera_body, "Declaring a colonist's belongings took them off the colonist.")

	// A non-colonist in the same room contributes nothing.
	var/mob/living/carbon/human/stranger = allocate(/mob/living/carbon/human/consistent, run_loc_floor_bottom_left)
	var/obj/item/storage/backpack/not_ours = allocate(/obj/item/storage/backpack, run_loc_floor_bottom_left)
	TEST_ASSERT(stranger.equip_to_appropriate_slot(not_ours), "The test could not put a backpack on a non-colonist.")

	reset_colonist_stash_write_state()
	declared = declare_colonist_belongings(shared)
	TEST_ASSERT(!(not_ours in declared), "A stranger's belongings were declared by the colony's stash.")
	TEST_ASSERT(pack in declared, "Ignoring a stranger also dropped a colonist's own belongings.")


/**
 * The same item is never declared twice, whatever the assignment says.
 *
 * This is the failure that would quietly ruin a colony: two containers both believing they hold a colonist
 * would each write a map block for the same worn items, and the colony would come back with two of
 * everything. Exclusive assignment is only correct while the assignment logic is correct, so the guard does
 * not trust it.
 */
/datum/unit_test/rimstation_colonist_chapter/stash_never_duplicates

/datum/unit_test/rimstation_colonist_chapter/stash_never_duplicates/Run()
	begin_test_campaign()

	var/datum/colonist_record/vera = SScampaign.roster.find_or_create("playerone", "Vera Holt", generation_number = 1, chapter = 1)
	var/mob/living/carbon/human/vera_body = allocate(/mob/living/carbon/human/consistent, run_loc_floor_bottom_left)
	TEST_ASSERT(SScampaign.bind_colonist(vera_body, vera), "A colonist could not be bound to a body.")

	var/obj/item/storage/backpack/pack = allocate(/obj/item/storage/backpack, run_loc_floor_bottom_left)
	TEST_ASSERT(vera_body.equip_to_appropriate_slot(pack), "The test could not put a backpack on a colonist.")

	var/obj/structure/closet/colonist_storage/stash/shared = allocate(/obj/structure/closet/colonist_storage/stash, run_loc_floor_top_right)

	// A locker takes precedence over the shared stash, so exactly one of the two may claim her.
	var/obj/structure/closet/colonist_storage/locker/personal = allocate(/obj/structure/closet/colonist_storage/locker, run_loc_floor_bottom_left)
	personal.colonist_id = vera.colonist_id

	reset_colonist_stash_write_state()
	var/list/from_locker = declare_colonist_belongings(personal)
	var/list/from_stash = declare_colonist_belongings(shared)

	TEST_ASSERT(pack in from_locker, "A colonist with a locker did not have their belongings declared by it.")
	TEST_ASSERT(!(pack in from_stash), "The shared stash also declared belongings that a personal locker had already taken, which would duplicate them on load.")

	// The guard's ledger has to actually be keeping count, since that is what refuses a second declaration.
	// Tripping it is not tested here on purpose: it answers with stack_trace(), and a guard that trips is a
	// bug by definition - a test that deliberately caused one could not tell that apart from a real failure.
	TEST_ASSERT(GLOB.colonist_declared_items[pack], "The declaration guard did not record an item it had just declared, so nothing would stop it being declared again.")


/// A colonist with a locker uses it; one without falls back to the shared stash; one with neither is not lost silently.
/datum/unit_test/rimstation_colonist_chapter/stash_assignment_prefers_lockers

/datum/unit_test/rimstation_colonist_chapter/stash_assignment_prefers_lockers/Run()
	begin_test_campaign()

	var/datum/colonist_record/vera = SScampaign.roster.find_or_create("playerone", "Vera Holt", generation_number = 1, chapter = 1)
	var/datum/colonist_record/dan = SScampaign.roster.find_or_create("playertwo", "Dan Reyes", generation_number = 1, chapter = 1)

	// With nowhere to keep anything, nobody is assigned - and nothing pretends otherwise.
	reset_colonist_stash_write_state()
	ensure_colonist_stash_assignment()
	TEST_ASSERT(!length(GLOB.colonist_stash_assignment), "Colonists were assigned storage in a colony that has none.")

	var/obj/structure/closet/colonist_storage/stash/shared = allocate(/obj/structure/closet/colonist_storage/stash, run_loc_floor_top_right)
	reset_colonist_stash_write_state()
	ensure_colonist_stash_assignment()
	TEST_ASSERT_EQUAL(GLOB.colonist_stash_assignment[vera.colonist_id], shared, "A colonist with no locker was not assigned to the shared stash.")
	TEST_ASSERT_EQUAL(GLOB.colonist_stash_assignment[dan.colonist_id], shared, "A second colonist with no locker was not assigned to the shared stash.")

	var/obj/structure/closet/colonist_storage/locker/personal = allocate(/obj/structure/closet/colonist_storage/locker, run_loc_floor_bottom_left)
	personal.colonist_id = vera.colonist_id
	reset_colonist_stash_write_state()
	ensure_colonist_stash_assignment()
	TEST_ASSERT_EQUAL(GLOB.colonist_stash_assignment[vera.colonist_id], personal, "A colonist with a locker was not assigned to it.")
	TEST_ASSERT_EQUAL(GLOB.colonist_stash_assignment[dan.colonist_id], shared, "A colonist without a locker was moved when somebody else claimed one.")


/**
 * A colonist who already owns a wardrobe is not handed a second one.
 *
 * The job dresses everybody before anything knows who arrived, so without this a returning colonist collects
 * a spare uniform, bag and ID every single chapter and the colony fills up with copies of itself.
 */
/datum/unit_test/rimstation_colonist_chapter/returners_are_not_reissued_a_kit

/datum/unit_test/rimstation_colonist_chapter/returners_are_not_reissued_a_kit/Run()
	begin_test_campaign()

	var/datum/colonist_record/vera = SScampaign.roster.find_or_create("playerone", "Vera Holt", generation_number = 1, chapter = 1)
	var/mob/living/carbon/human/vera_body = allocate(/mob/living/carbon/human/consistent, run_loc_floor_bottom_left)
	TEST_ASSERT(SScampaign.bind_colonist(vera_body, vera), "A colonist could not be bound to a body.")

	var/obj/structure/closet/colonist_storage/locker/personal = allocate(/obj/structure/closet/colonist_storage/locker, run_loc_floor_bottom_left)
	personal.colonist_id = vera.colonist_id

	// An empty locker means they own nothing, so the kit they were just issued is all they have.
	var/obj/item/storage/backpack/issued = allocate(/obj/item/storage/backpack, run_loc_floor_bottom_left)
	TEST_ASSERT(vera_body.equip_to_appropriate_slot(issued), "The test could not issue a colonist a backpack.")
	TEST_ASSERT(!colonist_has_belongings_waiting(vera), "A colonist with an empty locker was treated as owning a wardrobe.")
	TEST_ASSERT_EQUAL(withdraw_issued_outfit(vera_body, vera), 0, "A colonist with nothing waiting had their only clothes taken away.")
	TEST_ASSERT(!QDELETED(issued), "A colonist with nothing waiting lost the kit they had just been issued.")

	// With their own things stored, the kit is withheld instead.
	var/obj/item/storage/backpack/stored = allocate(/obj/item/storage/backpack)
	stored.forceMove(personal)
	TEST_ASSERT(colonist_has_belongings_waiting(vera), "A colonist with a stocked locker was treated as owning nothing.")
	TEST_ASSERT(withdraw_issued_outfit(vera_body, vera) > 0, "A returning colonist was issued a second set of everything.")
	TEST_ASSERT(QDELETED(issued), "A withheld kit was left on the colonist anyway.")
	TEST_ASSERT(!QDELETED(stored), "Withholding the kit also destroyed what the colonist actually owned.")
	TEST_ASSERT_EQUAL(stored.loc, personal, "Withholding the kit moved the colonist's own belongings out of their locker.")

	// Without a locker a colonist draws from the shared stash, which is communal - anything in it counts.
	var/datum/colonist_record/dan = SScampaign.roster.find_or_create("playertwo", "Dan Reyes", generation_number = 1, chapter = 1)
	TEST_ASSERT(!colonist_has_belongings_waiting(dan), "A colonist was owed belongings by a colony with no storage at all.")

	var/obj/structure/closet/colonist_storage/stash/shared = allocate(/obj/structure/closet/colonist_storage/stash, run_loc_floor_top_right)
	TEST_ASSERT(!colonist_has_belongings_waiting(dan), "An empty shared stash was treated as a wardrobe.")

	var/obj/item/storage/backpack/communal = allocate(/obj/item/storage/backpack)
	communal.forceMove(shared)
	TEST_ASSERT(colonist_has_belongings_waiting(dan), "A colonist could not draw from a stocked shared stash.")

	// A locker owner is still judged by their own locker, not by what the colony is sitting on.
	stored.forceMove(run_loc_floor_bottom_left)
	TEST_ASSERT(!colonist_has_belongings_waiting(vera), "A colonist with an empty locker was fed from the communal stash instead.")


/// One locker per colonist, and claiming a second gives up the first.
/datum/unit_test/rimstation_colonist_chapter/locker_claim

/datum/unit_test/rimstation_colonist_chapter/locker_claim/Run()
	begin_test_campaign()

	var/datum/colonist_record/vera = SScampaign.roster.find_or_create("playerone", "Vera Holt", generation_number = 1, chapter = 1)
	var/datum/colonist_record/dan = SScampaign.roster.find_or_create("playertwo", "Dan Reyes", generation_number = 1, chapter = 1)

	var/mob/living/carbon/human/vera_body = allocate(/mob/living/carbon/human/consistent, run_loc_floor_bottom_left)
	var/mob/living/carbon/human/dan_body = allocate(/mob/living/carbon/human/consistent, run_loc_floor_bottom_left)
	TEST_ASSERT(SScampaign.bind_colonist(vera_body, vera), "A colonist could not be bound to a body.")
	TEST_ASSERT(SScampaign.bind_colonist(dan_body, dan), "A second colonist could not be bound to a body.")

	var/obj/structure/closet/colonist_storage/locker/first = allocate(/obj/structure/closet/colonist_storage/locker, run_loc_floor_bottom_left)
	var/obj/structure/closet/colonist_storage/locker/second = allocate(/obj/structure/closet/colonist_storage/locker, run_loc_floor_top_right)

	TEST_ASSERT(claim_colonist_locker(vera_body, first), "A colonist could not claim an unclaimed locker.")
	TEST_ASSERT_EQUAL(first.colonist_id, vera.colonist_id, "Claiming a locker did not record who it belonged to.")
	TEST_ASSERT_EQUAL(get_personal_colonist_locker(vera.colonist_id), first, "A claimed locker could not be found again.")

	TEST_ASSERT(!claim_colonist_locker(dan_body, first), "A colonist took a locker that already belonged to somebody else.")
	TEST_ASSERT_EQUAL(first.colonist_id, vera.colonist_id, "A refused claim changed who a locker belonged to.")

	// A second locker moves the claim: one person, one locker.
	TEST_ASSERT(claim_colonist_locker(vera_body, second), "A colonist could not move to another locker.")
	TEST_ASSERT_EQUAL(second.colonist_id, vera.colonist_id, "Claiming a second locker did not record the new owner.")
	TEST_ASSERT_NULL(first.colonist_id, "Claiming a second locker left the first one still claimed.")
	TEST_ASSERT_EQUAL(get_personal_colonist_locker(vera.colonist_id), second, "A colonist who moved lockers was still found at the old one.")

	// The vacated one is free for somebody else.
	TEST_ASSERT(claim_colonist_locker(dan_body, first), "A locker whose owner had moved out could not be claimed.")
	TEST_ASSERT_EQUAL(first.colonist_id, dan.colonist_id, "A vacated locker did not record its new owner.")
