/**
 * The quarians exist, are pickable, and stand on digitigrade legs.
 *
 * The legs are the whole point of this species, and they are not declared on it - forced digitigrade swaps
 * the inherited leg overrides at species gain. So the assertion is on the bodyshape flag that clothing
 * actually reads, not on a typepath, and the icon state is checked the way the limb pipeline builds it.
 */
/datum/unit_test/rimstation_quarian_playable

/datum/unit_test/rimstation_quarian_playable/Run()
	TEST_ASSERT(SPECIES_QUARIAN in get_selectable_species(), "The quarians are not selectable, so ROUNDSTART_RACES is missing the entry.")

	var/mob/living/carbon/human/quarian = allocate(/mob/living/carbon/human/dummy/consistent)
	quarian.set_species(/datum/species/quarian)

	for(var/zone in list(BODY_ZONE_L_LEG, BODY_ZONE_R_LEG))
		var/obj/item/bodypart/leg = quarian.get_bodypart(zone)
		TEST_ASSERT_NOTNULL(leg, "The quarian has no [zone].")
		TEST_ASSERT(leg.bodyshape & BODYSHAPE_DIGITIGRADE, "The quarian's [zone] is not digitigrade, so DIGITIGRADE_FORCED did not take.")
		// A limb whose state is absent draws nothing rather than erroring.
		TEST_ASSERT(icon_exists(UNLINT(leg.icon_greyscale), "[leg.limb_id]_[leg.body_zone]"), "The quarian's [zone] has no '[leg.limb_id]_[leg.body_zone]' state, so it would render blank.")

	// Quarians keep their hair, unlike the asari. This catches the head override being copied across.
	var/obj/item/bodypart/head/head = quarian.get_bodypart(BODY_ZONE_HEAD)
	TEST_ASSERT(head.head_flags & HEAD_HAIR, "The quarian head cannot grow hair.")

	// fixed_mut_color is what makes every quarian the same colour. Null draw_color means it never applied.
	var/datum/species/quarian/species = quarian.dna.species
	TEST_ASSERT_EQUAL(head.draw_color, species.fixed_mut_color, "The quarian head is not drawn in the species' fixed colour.")


/**
 * Forcing one quarian digitigrade must not drag every other species along.
 *
 * try_make_digitigrade() rewrites bodypart_overrides in place. That is fine on the per-mob species instance
 * and a disaster on the shared prototype, so this checks the prototype still has plain legs afterwards.
 */
/datum/unit_test/rimstation_quarian_digi_is_per_mob

/datum/unit_test/rimstation_quarian_digi_is_per_mob/Run()
	var/mob/living/carbon/human/quarian = allocate(/mob/living/carbon/human/dummy/consistent)
	quarian.set_species(/datum/species/quarian)

	var/datum/species/prototype = GLOB.species_prototypes[/datum/species/quarian]
	TEST_ASSERT_EQUAL(prototype.bodypart_overrides[BODY_ZONE_L_LEG], /obj/item/bodypart/leg/left, "Spawning a quarian rewrote the shared species prototype's left leg.")
	TEST_ASSERT_EQUAL(prototype.bodypart_overrides[BODY_ZONE_R_LEG], /obj/item/bodypart/leg/right, "Spawning a quarian rewrote the shared species prototype's right leg.")

	var/datum/species/human_prototype = GLOB.species_prototypes[/datum/species/human]
	TEST_ASSERT_EQUAL(human_prototype.bodypart_overrides[BODY_ZONE_L_LEG], /obj/item/bodypart/leg/left, "Spawning a quarian gave humans digitigrade legs.")


/**
 * A quarian speaks Khelish without losing Common.
 *
 * Same shape as the asari check: the tongue has to allow the language on top of the holder granting it.
 */
/datum/unit_test/rimstation_quarian_languages

/datum/unit_test/rimstation_quarian_languages/Run()
	var/mob/living/carbon/human/quarian = allocate(/mob/living/carbon/human/dummy/consistent)
	quarian.set_species(/datum/species/quarian)

	TEST_ASSERT(quarian.has_language(/datum/language/khelish, UNDERSTOOD_LANGUAGE), "A quarian cannot understand Khelish.")
	TEST_ASSERT(quarian.has_language(/datum/language/khelish, SPOKEN_LANGUAGE), "A quarian cannot speak Khelish.")
	TEST_ASSERT(quarian.could_speak_language(/datum/language/khelish), "A quarian's tongue refuses Khelish, so the tongue whitelist is back.")

	TEST_ASSERT(quarian.has_language(/datum/language/common, UNDERSTOOD_LANGUAGE), "A quarian cannot understand Common.")
	TEST_ASSERT(quarian.has_language(/datum/language/common, SPOKEN_LANGUAGE), "A quarian cannot speak Common.")
