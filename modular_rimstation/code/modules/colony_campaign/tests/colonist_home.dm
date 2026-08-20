/**
 * A colonist claims a bed, and comes back to it next chapter.
 *
 * Home is chosen rather than remembered on purpose. Recording where somebody logged off would put them back
 * inside a wall the first time a checkpoint rolled back past the room they were standing in; a claimed bed is
 * something the colony can check still exists before sending anybody to it.
 */
/datum/unit_test/rimstation_colonist_chapter/home_claim

/datum/unit_test/rimstation_colonist_chapter/home_claim/Run()
	begin_test_campaign()

	var/datum/colonist_record/vera = SScampaign.roster.find_or_create("playerone", "Vera Holt", generation_number = 1, chapter = 1)
	var/mob/living/carbon/human/vera_body = allocate(/mob/living/carbon/human/consistent)
	TEST_ASSERT(SScampaign.bind_colonist(vera_body, vera), "A colonist could not be bound to a body.")

	var/turf/first_spot = run_loc_floor_bottom_left
	var/obj/structure/bed/first_bed = allocate(/obj/structure/bed, first_spot)

	TEST_ASSERT(claim_colonist_home(vera_body, first_bed), "A colonist could not claim a bed as their home.")
	TEST_ASSERT_NOTNULL(vera.home_point, "Claiming a bed did not give the colonist a home point.")
	TEST_ASSERT_EQUAL(vera.home_point["x"], first_spot.x, "A claimed home point recorded the wrong x coordinate.")
	TEST_ASSERT_EQUAL(vera.home_point["y"], first_spot.y, "A claimed home point recorded the wrong y coordinate.")
	TEST_ASSERT_EQUAL(vera.home_point["z"], first_spot.z, "A claimed home point recorded the wrong z coordinate.")
	TEST_ASSERT_EQUAL(vera.home_point["bed_type"], "[first_bed.type]", "A claimed home point did not record what was standing there.")

	// The colony can find its way back to it.
	TEST_ASSERT_EQUAL(get_colonist_home_turf(vera), first_spot, "A colonist could not be sent back to the bed they claimed.")

	// A second bed moves the claim rather than adding to it - a colonist sleeps in one place.
	var/turf/second_spot = run_loc_floor_top_right
	var/obj/structure/bed/second_bed = allocate(/obj/structure/bed, second_spot)
	TEST_ASSERT(claim_colonist_home(vera_body, second_bed), "A colonist could not move their home to another bed.")
	TEST_ASSERT_EQUAL(vera.home_point["x"], second_spot.x, "Claiming a second bed did not move the colonist's home to it.")
	TEST_ASSERT_EQUAL(get_colonist_home_turf(vera), second_spot, "A colonist was still sent to the bed they moved out of.")

	// Claiming the bed they already live in gives it up, or there is no way to stop having a home.
	TEST_ASSERT(claim_colonist_home(vera_body, second_bed), "A colonist could not give up the bed they had claimed.")
	TEST_ASSERT_NULL(vera.home_point, "Giving up a claimed bed left the colonist still living in it.")
	TEST_ASSERT_NULL(get_colonist_home_turf(vera), "A colonist with no home was still sent somewhere.")


/// One bed, one colonist. Two people waking up in the same bed every chapter is somebody else's genre.
/datum/unit_test/rimstation_colonist_chapter/home_is_exclusive

/datum/unit_test/rimstation_colonist_chapter/home_is_exclusive/Run()
	begin_test_campaign()

	var/datum/colonist_record/vera = SScampaign.roster.find_or_create("playerone", "Vera Holt", generation_number = 1, chapter = 1)
	var/datum/colonist_record/dan = SScampaign.roster.find_or_create("playertwo", "Dan Reyes", generation_number = 1, chapter = 1)

	var/mob/living/carbon/human/vera_body = allocate(/mob/living/carbon/human/consistent)
	var/mob/living/carbon/human/dan_body = allocate(/mob/living/carbon/human/consistent)
	TEST_ASSERT(SScampaign.bind_colonist(vera_body, vera), "A colonist could not be bound to a body.")
	TEST_ASSERT(SScampaign.bind_colonist(dan_body, dan), "A second colonist could not be bound to a body.")

	var/obj/structure/bed/contested = allocate(/obj/structure/bed, run_loc_floor_bottom_left)
	TEST_ASSERT(claim_colonist_home(vera_body, contested), "A colonist could not claim an unclaimed bed.")
	TEST_ASSERT(!claim_colonist_home(dan_body, contested), "A second colonist took a bed somebody already lived in.")
	TEST_ASSERT_NULL(dan.home_point, "A colonist refused a bed was given a home point anyway.")
	TEST_ASSERT_EQUAL(get_colonist_home_turf(vera), run_loc_floor_bottom_left, "Being refused someone else's bed moved the colonist who actually lived there.")

	// Once the first colonist moves out, the bed is free.
	TEST_ASSERT(claim_colonist_home(vera_body, contested), "A colonist could not give up their bed.")
	TEST_ASSERT(claim_colonist_home(dan_body, contested), "A bed whose owner had moved out could not be claimed.")
	TEST_ASSERT_EQUAL(get_colonist_home_turf(dan), run_loc_floor_bottom_left, "A colonist who claimed a vacated bed was not sent to it.")


/**
 * A home point whose bed is gone sends nobody anywhere.
 *
 * The expected cause is a checkpoint rollback to a world where the bed was never built, which is recovery
 * working rather than anything going wrong. It has to read as "no home" and fall through to the core, not as
 * an arrival at bare coordinates that might now be inside a wall.
 */
/datum/unit_test/rimstation_colonist_chapter/home_survives_a_missing_bed

/datum/unit_test/rimstation_colonist_chapter/home_survives_a_missing_bed/Run()
	begin_test_campaign()

	var/datum/colonist_record/vera = SScampaign.roster.find_or_create("playerone", "Vera Holt", generation_number = 1, chapter = 1)
	var/mob/living/carbon/human/vera_body = allocate(/mob/living/carbon/human/consistent)
	TEST_ASSERT(SScampaign.bind_colonist(vera_body, vera), "A colonist could not be bound to a body.")

	var/turf/spot = run_loc_floor_bottom_left
	var/obj/structure/bed/doomed = allocate(/obj/structure/bed, spot)
	TEST_ASSERT(claim_colonist_home(vera_body, doomed), "A colonist could not claim a bed.")
	TEST_ASSERT_EQUAL(get_colonist_home_turf(vera), spot, "A colonist could not be sent to the bed they claimed.")

	// The bed is destroyed, but the claim on the record is not - the colony simply cannot honour it.
	QDEL_NULL(doomed)
	TEST_ASSERT_NULL(get_colonist_home_turf(vera), "A colonist was sent to a bed that no longer exists.")
	TEST_ASSERT_NOTNULL(vera.home_point, "A destroyed bed erased the colonist's record of where they lived.")

	// Something else standing on the same tile is not their bed either.
	allocate(/obj/structure/table, spot)
	TEST_ASSERT_NULL(get_colonist_home_turf(vera), "A colonist was sent home because something unrelated stood where their bed had been.")

	// Rebuilt in the same place, the claim means something again.
	allocate(/obj/structure/bed, spot)
	TEST_ASSERT_EQUAL(get_colonist_home_turf(vera), spot, "A colonist was not sent back to a bed that had been rebuilt where theirs stood.")
