/**
 * The asari exist, are pickable, and render.
 *
 * Every assertion here covers something that fails silently rather than loudly. A missing config line or
 * define leaves the species compiled but absent from character setup; a wrong limb_id or a bad .dmi leaves
 * the head invisible instead of erroring; and the species was ported from a build whose language module
 * stripped Common off every mob in the game, which is the one thing that must not have come across.
 */
/datum/unit_test/rimstation_asari_playable

/datum/unit_test/rimstation_asari_playable/Run()
	// Compiling the species is not the same as being able to pick it. This needs the config entry too.
	TEST_ASSERT(SPECIES_ASARI in get_selectable_species(), "The asari are not selectable, so ROUNDSTART_RACES is missing the entry.")

	// A limb whose state is absent draws nothing at all rather than erroring.
	TEST_ASSERT(icon_exists(BODYPART_ICON_ASARI, "asari_head"), "The asari head icon has no 'asari_head' state, so the head would render blank.")

	var/mob/living/carbon/human/asari = allocate(/mob/living/carbon/human/dummy/consistent)
	asari.set_species(/datum/species/asari)

	var/obj/item/bodypart/head/head = asari.get_bodypart(BODY_ZONE_HEAD)
	TEST_ASSERT_NOTNULL(head, "The asari has no head bodypart at all.")
	TEST_ASSERT(istype(head, /obj/item/bodypart/head/asari), "The asari head is [head.type], so bodypart_overrides did not take.")

	// The crest is drawn into the head sprite, so hair would clip through it. This also hides the hair prefs.
	TEST_ASSERT(!(head.head_flags & HEAD_HAIR), "The asari head allows hair, which would draw on top of the crest.")

	// draw_color is what carries the mutant colour onto a greyscale limb. Null here means the body renders grey.
	TEST_ASSERT_NOTNULL(head.draw_color, "The asari head has no draw_color, so TRAIT_MUTANT_COLORS never applied.")


/**
 * An asari speaks High Thessian without losing Common.
 *
 * Speaking a language needs the tongue to allow it on top of the language holder granting it. The fork-wide
 * override that drops the tongue's whitelist is what lets this work with a plain human tongue, so if an
 * upstream merge ever restores that whitelist, this is the test that catches it.
 */
/datum/unit_test/rimstation_asari_languages

/datum/unit_test/rimstation_asari_languages/Run()
	var/mob/living/carbon/human/asari = allocate(/mob/living/carbon/human/dummy/consistent)
	asari.set_species(/datum/species/asari)

	TEST_ASSERT(asari.has_language(/datum/language/thessian, UNDERSTOOD_LANGUAGE), "An asari cannot understand High Thessian.")
	TEST_ASSERT(asari.has_language(/datum/language/thessian, SPOKEN_LANGUAGE), "An asari cannot speak High Thessian.")
	TEST_ASSERT(asari.could_speak_language(/datum/language/thessian), "An asari's tongue refuses High Thessian, so the tongue whitelist is back.")

	TEST_ASSERT(asari.has_language(/datum/language/common, UNDERSTOOD_LANGUAGE), "An asari cannot understand Common.")
	TEST_ASSERT(asari.has_language(/datum/language/common, SPOKEN_LANGUAGE), "An asari cannot speak Common.")
