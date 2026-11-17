/// A suited quarian eats, drinks and takes a spoonful through the helmet's feeding port.
/// A muzzle still blocks, and an ordinary helmet still blocks once the quarian one is off.
/datum/unit_test/rimstation_quarian_feeding_port

/datum/unit_test/rimstation_quarian_feeding_port/Run()
	var/mob/living/carbon/human/quarian = allocate(/mob/living/carbon/human/consistent)
	rimstation_suit_up_quarian(quarian)
	TEST_ASSERT(istype(quarian.head, /obj/item/clothing/head/helmet/space/quarian), "The quarian outfit has no quarian helmet, so this test proves nothing.")
	TEST_ASSERT(istype(quarian.wear_mask, /obj/item/clothing/mask/breath), "The quarian outfit has no breath mask, so this test proves nothing.")
	TEST_ASSERT(quarian.is_mouth_covered(), "A suited quarian's mouth reads as uncovered, so disease and pepper spray would reach it.")

	var/obj/item/food/cookie/cookie = allocate(/obj/item/food/cookie)
	var/datum/component/edible/edible = cookie.GetComponent(/datum/component/edible)
	TEST_ASSERT(edible.CanConsume(quarian, quarian), "A suited quarian cannot eat through the feeding port.")

	var/obj/item/reagent_containers/cup/beaker/beaker = allocate(/obj/item/reagent_containers/cup/beaker)
	beaker.reagents.add_reagent(/datum/reagent/water, 10)
	TEST_ASSERT(beaker.canconsume(quarian, quarian), "A suited quarian cannot drink through the feeding port.")

	var/obj/item/kitchen/spoon/spoon = allocate(/obj/item/kitchen/spoon)
	spoon.reagents.add_reagent(/datum/reagent/water, 5)
	spoon.attack(quarian, quarian)
	TEST_ASSERT(spoon.reagents.total_volume < 5, "A suited quarian cannot take a spoonful through the feeding port.")

	qdel(quarian.wear_mask)
	var/obj/item/clothing/mask/muzzle/muzzle = allocate(/obj/item/clothing/mask/muzzle)
	quarian.equip_to_slot(muzzle, ITEM_SLOT_MASK)
	TEST_ASSERT_EQUAL(quarian.wear_mask, muzzle, "The muzzle did not go on, so the next checks prove nothing.")
	TEST_ASSERT(!edible.CanConsume(quarian, quarian), "A muzzled quarian can still eat through the feeding port.")
	TEST_ASSERT(!beaker.canconsume(quarian, quarian), "A muzzled quarian can still drink through the feeding port.")

	qdel(muzzle)
	qdel(quarian.head)
	var/obj/item/clothing/head/helmet/space/plain_helmet = allocate(/obj/item/clothing/head/helmet/space)
	quarian.equip_to_slot(plain_helmet, ITEM_SLOT_HEAD)
	TEST_ASSERT_EQUAL(quarian.head, plain_helmet, "The plain helmet did not go on, so the next checks prove nothing.")
	TEST_ASSERT(!HAS_TRAIT(quarian, TRAIT_FEEDING_PORT), "Taking off the quarian helmet left the feeding port behind.")
	TEST_ASSERT(!edible.CanConsume(quarian, quarian), "An ordinary space helmet lets its wearer eat through it.")
	TEST_ASSERT(!beaker.canconsume(quarian, quarian), "An ordinary space helmet lets its wearer drink through it.")
