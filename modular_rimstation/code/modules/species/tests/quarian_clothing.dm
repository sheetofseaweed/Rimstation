/**
 * Every quarian garment resolves the icon state it asks for, in both sheets.
 *
 * The sheets came from a build whose metadata had drifted from its pixels, so this walks every type and
 * every state the helmet can compute, in the world sheet and the worn sheet. A missing state draws
 * nothing at all rather than erroring, which is exactly the kind of fault that reaches a live round.
 */
/datum/unit_test/rimstation_quarian_clothing_icons

/datum/unit_test/rimstation_quarian_clothing_icons/Run()
	var/list/simple = list(/obj/item/clothing/under/quarian) + subtypesof(/obj/item/clothing/under/quarian)
	simple += /obj/item/clothing/gloves/quarian
	simple += /obj/item/clothing/shoes/quarian

	for(var/obj/item/clothing/garment as anything in simple)
		check_state(garment, garment::icon_state)

	// The helmet builds its state as "<base>-<visor down>-<light on>", so all four exist for every colour.
	var/list/helmets = list(/obj/item/clothing/head/helmet/space/quarian) + subtypesof(/obj/item/clothing/head/helmet/space/quarian)
	for(var/obj/item/clothing/head/helmet/space/quarian/helmet as anything in helmets)
		for(var/visor in list(0, 1))
			for(var/light in list(0, 1))
				check_state(helmet, "[helmet::base_icon_state]-[visor]-[light]")

/datum/unit_test/rimstation_quarian_clothing_icons/proc/check_state(obj/item/clothing/garment, state)
	if(!icon_exists(garment::icon, state))
		TEST_FAIL("[garment] has no '[state]' state in its world icon, so it would show as blank.")
	if(!icon_exists(garment::worn_icon, state))
		TEST_FAIL("[garment] has no '[state]' state in its worn icon, so it would show as blank.")


/**
 * A quarian arrives in their own enviro-suit, not the job's jumpsuit.
 *
 * pre_equip_species_outfit() fills the slots first and the job outfit is then dropped on the floor of
 * can_equip(), which is load-bearing but invisible. If the ordering ever flips, a quarian spawns in a
 * grey jumpsuit and nothing anywhere says why.
 */
/datum/unit_test/rimstation_quarian_spawns_suited

/datum/unit_test/rimstation_quarian_spawns_suited/Run()
	var/datum/job/assistant = SSjob.get_job(JOB_ASSISTANT)
	TEST_ASSERT_NOTNULL(assistant, "The assistant job is not registered, so this test cannot dress anyone.")

	var/mob/living/carbon/human/quarian = allocate(/mob/living/carbon/human/dummy/consistent)
	quarian.set_species(/datum/species/quarian)
	quarian.job = assistant
	quarian.dress_up_as_job(assistant)

	var/obj/item/uniform = quarian.get_item_by_slot(ITEM_SLOT_ICLOTHING)
	TEST_ASSERT(istype(uniform, /obj/item/clothing/under/quarian), "A quarian assistant is wearing [uniform || "nothing"] instead of a quarian suit.")

	var/obj/item/head = quarian.get_item_by_slot(ITEM_SLOT_HEAD)
	TEST_ASSERT(istype(head, /obj/item/clothing/head/helmet/space/quarian), "A quarian assistant is wearing [head || "nothing"] instead of a quarian helmet.")

	var/obj/item/feet = quarian.get_item_by_slot(ITEM_SLOT_FEET)
	TEST_ASSERT(istype(feet, /obj/item/clothing/shoes/quarian), "A quarian assistant is wearing [feet || "nothing"] instead of quarian boots.")

	var/obj/item/hands = quarian.get_item_by_slot(ITEM_SLOT_GLOVES)
	TEST_ASSERT(istype(hands, /obj/item/clothing/gloves/quarian), "A quarian assistant is wearing [hands || "nothing"] instead of quarian gloves.")


/**
 * Suit colour follows the job's department, with a named handful of exceptions.
 *
 * Command is deliberately checked last so a head wears their own department's colour. These four cases
 * are the ones that go wrong if that order is ever shuffled.
 */
/datum/unit_test/rimstation_quarian_outfit_colours

/datum/unit_test/rimstation_quarian_outfit_colours/Run()
	var/datum/species/quarian/species = GLOB.species_prototypes[/datum/species/quarian]

	var/list/expected = list(
		/datum/job/chief_engineer = /datum/outfit/quarian/yellow,
		/datum/job/head_of_personnel = /datum/outfit/quarian/green,
		/datum/job/captain = /datum/outfit/quarian/blue,
		/datum/job/chemist = /datum/outfit/quarian/orange,
	)

	for(var/job_type in expected)
		var/datum/job/job = SSjob.get_job_type(job_type)
		TEST_ASSERT_NOTNULL(job, "The job [job_type] is not registered with SSjob.")
		TEST_ASSERT_EQUAL(species.get_quarian_outfit(job), expected[job_type], "[job.title] got the wrong quarian suit colour.")

	TEST_ASSERT_EQUAL(species.get_quarian_outfit(null), /datum/outfit/quarian, "A quarian with no job did not fall back to the plain suit.")


/**
 * Quarian gloves take on a fitted pair's traits and insulation, and give them back.
 *
 * The traits have to go on through attach_clothing_traits() rather than a plain assignment, because a
 * plain one never reaches someone who is already wearing the gloves.
 */
/datum/unit_test/rimstation_quarian_glove_module

/datum/unit_test/rimstation_quarian_glove_module/Run()
	var/mob/living/carbon/human/wearer = allocate(/mob/living/carbon/human/dummy/consistent)
	var/obj/item/clothing/gloves/quarian/gloves = allocate(/obj/item/clothing/gloves/quarian)
	wearer.equip_to_slot_or_del(gloves, ITEM_SLOT_GLOVES)
	TEST_ASSERT_EQUAL(wearer.get_item_by_slot(ITEM_SLOT_GLOVES), gloves, "The quarian gloves would not go on.")

	var/obj/item/clothing/gloves/latex/nitrile/module = allocate(/obj/item/clothing/gloves/latex/nitrile)
	wearer.put_in_hands(module)
	gloves.item_interaction(wearer, module)

	TEST_ASSERT_EQUAL(gloves.module, module, "The nitrile gloves did not fit as a module.")
	TEST_ASSERT(TRAIT_QUICKER_CARRY in gloves.clothing_traits, "The fitted module's traits did not transfer to the gloves.")
	TEST_ASSERT(HAS_TRAIT(wearer, TRAIT_QUICKER_CARRY), "The wearer did not gain the module's trait, so a plain assignment was used instead of attach_clothing_traits().")
	TEST_ASSERT_EQUAL(gloves.icon_state, "nitrile", "The gloves did not take the module's colour.")

	var/obj/item/screwdriver = allocate(/obj/item/screwdriver)
	gloves.screwdriver_act(wearer, screwdriver)

	TEST_ASSERT_NULL(gloves.module, "The module did not come out.")
	TEST_ASSERT(!HAS_TRAIT(wearer, TRAIT_QUICKER_CARRY), "The wearer kept the module's trait after it was removed.")
	TEST_ASSERT_EQUAL(gloves.icon_state, gloves.base_icon_state, "The gloves did not go back to their bare sprite.")


/**
 * A bare quarian helmet cannot lower a welding visor it does not have.
 *
 * Fitting the mask is what enables it, and the icon state has to follow, because the visor-down sprite
 * is the only thing telling the wearer their flash protection is on.
 */
/datum/unit_test/rimstation_quarian_helmet_visor

/datum/unit_test/rimstation_quarian_helmet_visor/Run()
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human/dummy/consistent)
	var/obj/item/clothing/head/helmet/space/quarian/helmet = allocate(/obj/item/clothing/head/helmet/space/quarian)

	TEST_ASSERT(helmet.up, "A fresh quarian helmet starts with its visor down.")
	TEST_ASSERT_EQUAL(helmet.flash_protect, FLASH_PROTECTION_NONE, "A fresh quarian helmet protects from flashes with no welding mask in it.")
	TEST_ASSERT(!helmet.adjust_visor(user), "A quarian helmet lowered a welding visor it has not been given.")

	var/obj/item/clothing/mask/gas/welding/mask = allocate(/obj/item/clothing/mask/gas/welding)
	user.put_in_hands(mask)
	helmet.item_interaction(user, mask)
	TEST_ASSERT_EQUAL(helmet.welding_mask, mask, "The welding mask did not fit into the helmet.")

	TEST_ASSERT(helmet.adjust_visor(user), "The helmet would not lower its visor with a mask fitted.")
	TEST_ASSERT(!helmet.up, "The visor did not come down.")
	TEST_ASSERT_EQUAL(helmet.flash_protect, FLASH_PROTECTION_WELDER, "The lowered visor does not protect from flashes.")
	TEST_ASSERT_EQUAL(helmet.icon_state, "[helmet.base_icon_state]-1-0", "The helmet sprite does not show the visor down.")
