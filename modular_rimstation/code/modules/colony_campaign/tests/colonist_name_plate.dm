/**
 * A plate turns a container the colony built into somebody's own locker.
 *
 * The claim system in stash.dm had nothing that could reach it: no recipe made a personal locker and no map
 * placed one, so every colonist shared the one stash. This is the path that opens it.
 */
/datum/unit_test/rimstation_colonist_chapter/name_plate_claims_a_container

/datum/unit_test/rimstation_colonist_chapter/name_plate_claims_a_container/Run()
	begin_test_campaign()

	var/datum/colonist_record/vera = SScampaign.roster.find_or_create("playerone", "Vera Holt", generation_number = 1, chapter = 1)
	var/mob/living/carbon/human/vera_body = allocate(/mob/living/carbon/human/consistent, run_loc_floor_bottom_left)
	TEST_ASSERT(SScampaign.bind_colonist(vera_body, vera), "A colonist could not be bound to a body.")

	// A wooden cabinet, which the colony can already build, with something already in it.
	var/obj/structure/closet/cabinet/cabinet = allocate(/obj/structure/closet/cabinet, run_loc_floor_top_right)
	var/turf/stood_on = get_turf(cabinet)
	var/obj/item/stored = new /obj/item/clothing/under/color/grey(cabinet)

	TEST_ASSERT_NULL(why_container_cannot_be_claimed(cabinet, vera_body), "A colonist was refused a container they should have been able to claim.")

	var/obj/structure/closet/colonist_storage/locker/claimed = convert_closet_to_colonist_locker(cabinet, vera_body)
	TEST_ASSERT_NOTNULL(claimed, "Nailing a plate to a cabinet produced no locker.")
	allocated += claimed
	TEST_ASSERT(QDELETED(cabinet), "The container that was claimed is still standing beside the locker it became.")
	TEST_ASSERT_EQUAL(get_turf(claimed), stood_on, "A claimed locker did not end up where the container it replaced stood.")
	TEST_ASSERT_EQUAL(stored.loc, claimed, "Claiming a container tipped what was inside it onto the floor.")

	TEST_ASSERT(claim_colonist_locker(vera_body, claimed), "A colonist could not claim the locker their own plate made.")
	TEST_ASSERT_EQUAL(get_personal_colonist_locker(vera.colonist_id), claimed, "A claimed locker is not the one the colony looks up for its owner.")


/// The plate refuses anything that is not somebody's to claim, and says why.
/datum/unit_test/rimstation_colonist_chapter/name_plate_refuses_what_is_not_yours

/datum/unit_test/rimstation_colonist_chapter/name_plate_refuses_what_is_not_yours/Run()
	begin_test_campaign()

	var/datum/colonist_record/vera = SScampaign.roster.find_or_create("playerone", "Vera Holt", generation_number = 1, chapter = 1)
	var/mob/living/carbon/human/vera_body = allocate(/mob/living/carbon/human/consistent, run_loc_floor_bottom_left)
	TEST_ASSERT(SScampaign.bind_colonist(vera_body, vera), "A colonist could not be bound to a body.")

	// The colony's shared stash. Claiming it would make the settlement's storage one person's property.
	var/obj/structure/closet/colonist_storage/stash/shared = allocate(/obj/structure/closet/colonist_storage/stash, run_loc_floor_top_right)
	TEST_ASSERT_NOTNULL(why_container_cannot_be_claimed(shared, vera_body), "The colony's shared stash could be claimed as one colonist's locker.")

	var/obj/structure/closet/cabinet/sealed = allocate(/obj/structure/closet/cabinet, run_loc_floor_top_right)
	sealed.welded = TRUE
	TEST_ASSERT_NOTNULL(why_container_cannot_be_claimed(sealed, vera_body), "A welded container could be claimed.")
	sealed.welded = FALSE

	// Replacing a container with somebody inside it would move a person, so it is refused instead.
	var/mob/living/carbon/human/hiding = allocate(/mob/living/carbon/human/consistent, run_loc_floor_bottom_left)
	hiding.forceMove(sealed)
	TEST_ASSERT_NOTNULL(why_container_cannot_be_claimed(sealed, vera_body), "A container with somebody inside it could be claimed.")
	hiding.forceMove(run_loc_floor_bottom_left)

	// Somebody who is not one of this colony's people has nobody to claim it for.
	var/mob/living/carbon/human/stranger = allocate(/mob/living/carbon/human/consistent, run_loc_floor_bottom_left)
	TEST_ASSERT_NOTNULL(why_container_cannot_be_claimed(sealed, stranger), "A stranger to the colony could claim one of its containers.")

	// And the item's own entry point refuses the same cases rather than starting the work.
	var/obj/item/colonist_name_plate/plate = allocate(/obj/item/colonist_name_plate, run_loc_floor_bottom_left)
	TEST_ASSERT_EQUAL(plate.interact_with_atom(shared, vera_body), ITEM_INTERACT_BLOCKING, "Using a plate on the shared stash was not refused.")
	TEST_ASSERT_EQUAL(plate.interact_with_atom(sealed, stranger), ITEM_INTERACT_BLOCKING, "Using a plate as a stranger to the colony was not refused.")
	TEST_ASSERT_EQUAL(plate.interact_with_atom(vera_body, vera_body), NONE, "A plate tried to claim something that is not a container at all.")


/// Outside a campaign nothing can be claimed, because there is no colony to keep anything for.
/datum/unit_test/rimstation_name_plate_needs_a_colony
	var/saved_state
	var/datum/campaign_manifest/saved_manifest

/datum/unit_test/rimstation_name_plate_needs_a_colony/Run()
	saved_state = SScampaign.campaign_state
	saved_manifest = SScampaign.manifest
	SScampaign.manifest = null
	SScampaign.campaign_state = CAMPAIGN_STATE_NONE

	var/mob/living/carbon/human/body = allocate(/mob/living/carbon/human/consistent, run_loc_floor_bottom_left)
	var/obj/structure/closet/cabinet/cabinet = allocate(/obj/structure/closet/cabinet, run_loc_floor_top_right)
	TEST_ASSERT_NOTNULL(why_container_cannot_be_claimed(cabinet, body), "A container was claimable in a round with no campaign running.")

/datum/unit_test/rimstation_name_plate_needs_a_colony/Destroy()
	SScampaign.campaign_state = saved_state
	SScampaign.manifest = saved_manifest
	saved_manifest = null
	return ..()


/// The plate is craftable, and from wood, which is what a new colony has.
/datum/unit_test/rimstation_name_plate_is_craftable

/datum/unit_test/rimstation_name_plate_is_craftable/Run()
	var/datum/crafting_recipe/found
	for(var/datum/crafting_recipe/recipe as anything in GLOB.crafting_recipes)
		if(recipe.result == /obj/item/colonist_name_plate)
			found = recipe
			break

	TEST_ASSERT_NOTNULL(found, "No crafting recipe makes a name plate, so a colonist can never claim a locker.")
	TEST_ASSERT(found.reqs[/obj/item/stack/sheet/mineral/wood], "The name plate is not made out of wood.")
