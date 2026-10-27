/// Makes the given human a quarian in a full enviro-suit, and hands back their integrity component.
/proc/rimstation_suit_up_quarian(mob/living/carbon/human/quarian)
	quarian.set_species(/datum/species/quarian)
	quarian.equipOutfit(/datum/outfit/quarian)
	return quarian.GetComponent(/datum/component/quarian_suit_integrity)


/**
 * The suit seals when all four pieces are on and opens the moment one comes off.
 *
 * The exposure clock has to follow the seal in both directions. The source build only ever started it,
 * and relied on a flag to avoid stacking duplicate timers.
 */
/datum/unit_test/rimstation_quarian_suit_seal

/datum/unit_test/rimstation_quarian_suit_seal/Run()
	var/mob/living/carbon/human/quarian = allocate(/mob/living/carbon/human/consistent)
	var/datum/component/quarian_suit_integrity/integrity = rimstation_suit_up_quarian(quarian)

	TEST_ASSERT_NOTNULL(integrity, "A quarian got no suit integrity component.")
	TEST_ASSERT(integrity.sealed, "A quarian in a full enviro-suit is not sealed.")
	TEST_ASSERT(!(integrity in SSprocessing.processing), "A sealed quarian is still running the exposure clock.")

	var/obj/item/helmet = quarian.get_item_by_slot(ITEM_SLOT_HEAD)
	TEST_ASSERT_NOTNULL(helmet, "The quarian has no helmet to remove.")
	quarian.dropItemToGround(helmet, force = TRUE)

	TEST_ASSERT(!integrity.sealed, "Taking the helmet off did not open the suit.")
	TEST_ASSERT(integrity in SSprocessing.processing, "An open suit is not running the exposure clock.")

	quarian.equip_to_slot_or_del(helmet, ITEM_SLOT_HEAD)
	TEST_ASSERT(integrity.sealed, "Putting the helmet back on did not reseal the suit.")
	TEST_ASSERT(!(integrity in SSprocessing.processing), "The exposure clock kept running after the suit resealed.")


/**
 * The exposure clock dies with the quarian, and with the species.
 *
 * This is the defect the port exists to avoid. The original rescheduled a timer from inside its own
 * callback with no stop condition but "suit resealed", so it outlived death and species change alike.
 */
/datum/unit_test/rimstation_quarian_breach_lifecycle

/datum/unit_test/rimstation_quarian_breach_lifecycle/Run()
	var/mob/living/carbon/human/quarian = allocate(/mob/living/carbon/human/consistent)
	var/datum/component/quarian_suit_integrity/integrity = rimstation_suit_up_quarian(quarian)
	quarian.dropItemToGround(quarian.get_item_by_slot(ITEM_SLOT_HEAD), force = TRUE)
	TEST_ASSERT(integrity in SSprocessing.processing, "The suit did not open, so this test cannot check the clock stops.")

	quarian.death()
	TEST_ASSERT(!(integrity in SSprocessing.processing), "A dead quarian is still rolling for infection.")

	quarian.set_species(/datum/species/human)
	TEST_ASSERT_NULL(quarian.GetComponent(/datum/component/quarian_suit_integrity), "The suit integrity component survived the species change.")


/**
 * Preview dummies never get the component.
 *
 * The character menu keeps a dummy alive for the whole round. One running an infection clock would
 * quietly hand diseases to a body that is not a person.
 */
/datum/unit_test/rimstation_quarian_dummy_exempt

/datum/unit_test/rimstation_quarian_dummy_exempt/Run()
	var/mob/living/carbon/human/dummy = allocate(/mob/living/carbon/human/dummy/consistent)
	dummy.set_species(/datum/species/quarian)

	TEST_ASSERT_NULL(dummy.GetComponent(/datum/component/quarian_suit_integrity), "A preview dummy was given a suit integrity component.")


/**
 * A breach illness is the quarian's own problem, and antibodies make it rarer.
 *
 * Non-contagious on purpose: a suit failure should not become a station plague. The chance is asserted
 * rather than rolled, since rolling would make the test a coin flip.
 */
/datum/unit_test/rimstation_quarian_breach_infection

/datum/unit_test/rimstation_quarian_breach_infection/Run()
	var/mob/living/carbon/human/quarian = allocate(/mob/living/carbon/human/consistent)
	var/datum/component/quarian_suit_integrity/integrity = rimstation_suit_up_quarian(quarian)

	var/untreated = integrity.get_infection_chance()
	quarian.reagents.add_reagent(/datum/reagent/medicine/quarian_antibodies, 20)
	var/treated = integrity.get_infection_chance()
	TEST_ASSERT(treated < untreated, "Quarian antibodies did not lower the infection chance ([treated] vs [untreated]).")

	TEST_ASSERT(integrity.infect(), "A forced breach infection did not take hold.")
	TEST_ASSERT_EQUAL(length(quarian.diseases), 1, "The quarian did not end up with exactly one illness.")

	var/datum/disease/caught = quarian.diseases[1]
	TEST_ASSERT(caught.spread_flags & DISEASE_SPREAD_NON_CONTAGIOUS, "A breach illness can spread to the rest of the station.")
