/**
 * An asari is feminine in body and pronouns, however it got to be an asari.
 *
 * Mid-round changes - a mirror, a wabbajack, an admin - never touch preferences, so on_species_gain()
 * has to do this one itself.
 */
/datum/unit_test/rimstation_asari_forced_body_on_gain

/datum/unit_test/rimstation_asari_forced_body_on_gain/Run()
	var/mob/living/carbon/human/subject = allocate(/mob/living/carbon/human/consistent)
	subject.physique = MALE
	subject.gender = MALE
	subject.set_species(/datum/species/asari)

	TEST_ASSERT_EQUAL(subject.physique, FEMALE, "Becoming an asari did not make the body feminine.")
	TEST_ASSERT_EQUAL(subject.gender, FEMALE, "Becoming an asari did not set the gender to female.")


/**
 * The forced body beats the preferences, which apply after the species one.
 *
 * PREFERENCE_PRIORITY_SPECIES is 3, gender is 5 and body type is 6, so anything set during
 * on_species_gain() is overwritten moments later. apply_supplementary_body_changes() runs after every
 * preference, which is the only reason this holds. Setting both back by hand here stands in for those
 * two preferences having just applied.
 */
/datum/unit_test/rimstation_asari_forced_body_beats_prefs

/datum/unit_test/rimstation_asari_forced_body_beats_prefs/Run()
	var/mob/living/carbon/human/subject = allocate(/mob/living/carbon/human/consistent)
	subject.set_species(/datum/species/asari)

	subject.physique = MALE
	subject.gender = MALE
	subject.dna.species.apply_supplementary_body_changes(subject, null)

	TEST_ASSERT_EQUAL(subject.physique, FEMALE, "The body type preference would leave an asari with a masculine body.")
	TEST_ASSERT_EQUAL(subject.gender, FEMALE, "The gender preference would leave an asari as he/him.")


/**
 * Only species that ask for it are pinned, and an asari who stops being one is released.
 */
/datum/unit_test/rimstation_forced_body_scope

/datum/unit_test/rimstation_forced_body_scope/Run()
	var/datum/species/human_species = GLOB.species_prototypes[/datum/species/human]
	TEST_ASSERT_NULL(human_species.forced_physique, "Humans have a forced physique, so the lock is not species-specific.")
	TEST_ASSERT_NULL(human_species.forced_gender, "Humans have a forced gender, so the lock is not species-specific.")

	var/mob/living/carbon/human/subject = allocate(/mob/living/carbon/human/consistent)
	subject.set_species(/datum/species/asari)
	TEST_ASSERT_EQUAL(subject.physique, FEMALE, "The asari was not pinned in the first place.")

	subject.set_species(/datum/species/human)
	subject.physique = MALE
	subject.gender = MALE
	subject.dna.species.apply_supplementary_body_changes(subject, null)
	TEST_ASSERT_EQUAL(subject.physique, MALE, "A former asari is still being forced feminine as a human.")
	TEST_ASSERT_EQUAL(subject.gender, MALE, "A former asari is still being forced she/her as a human.")


/**
 * The asari keep sexes = TRUE, and that is deliberate.
 *
 * Turning it off looks like the obvious way to express a mono-gender race, and does the opposite here:
 * it drops the female uniform shaping and the dimorphic chest sprite, so an all-feminine species would
 * render with the masculine silhouette. The two locks are what express it instead.
 */
/datum/unit_test/rimstation_asari_keeps_sexes

/datum/unit_test/rimstation_asari_keeps_sexes/Run()
	var/datum/species/asari = GLOB.species_prototypes[/datum/species/asari]

	TEST_ASSERT(asari.sexes, "The asari have sexes = FALSE, which renders them with the masculine body sprite.")
	TEST_ASSERT_EQUAL(asari.forced_physique, FEMALE, "The asari are no longer pinned to a feminine physique.")
	TEST_ASSERT_EQUAL(asari.forced_gender, FEMALE, "The asari are no longer pinned to a feminine gender.")
