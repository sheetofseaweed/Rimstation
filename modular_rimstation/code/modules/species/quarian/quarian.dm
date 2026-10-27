/datum/species/quarian
	name = "Quarian"
	id = SPECIES_QUARIAN
	inherent_traits = list(
		TRAIT_ADVANCEDTOOLUSER,
		TRAIT_CAN_STRIP,
		TRAIT_LITERATE,
		TRAIT_MADNESS_IMMUNE,
		TRAIT_MUTANT_COLORS,
		TRAIT_FIXED_MUTANT_COLORS,
		TRAIT_QUICK_BUILD,
		TRAIT_SPECIAL_TRAUMA_BOOST,
		TRAIT_SUPERMATTER_SOOTHER,
	)
	inherent_biotypes = MOB_ORGANIC|MOB_HUMANOID
	// Every quarian is the same grey-purple under the suit, so the colour picker is pointless for them.
	fixed_mut_color = "#9692BE"
	// Forced digitigrade swaps the default legs for their digi type on species gain, so we keep the
	// inherited bodypart_overrides and let try_make_digitigrade() do the work.
	digitigrade_customization = DIGITIGRADE_FORCED
	examine_limb_id = SPECIES_HUMAN
	mutant_bodyparts = list()
	skinned_type = /obj/item/stack/sheet/animalhide/carbon/human
	species_language_holder = /datum/language_holder/quarian
	// No ERT_SPAWN. A quarian dropped into a response team has none of their own gear.
	changesource_flags = MIRROR_BADMIN | WABBAJACK | MIRROR_MAGIC | MIRROR_PRIDE | RACE_SWAP | SLIME_EXTRACT

/datum/species/quarian/prepare_human_for_preview(mob/living/carbon/human/quarian)
	quarian.hairstyle = "Business Hair"
	quarian.hair_color = "#bb9966"
	quarian.update_body(TRUE)

/datum/species/quarian/get_scream_sound(mob/living/carbon/human/human)
	if(human.physique == MALE)
		return pick(
			'sound/mobs/humanoids/human/scream/malescream_1.ogg',
			'sound/mobs/humanoids/human/scream/malescream_2.ogg',
			'sound/mobs/humanoids/human/scream/malescream_3.ogg',
			'sound/mobs/humanoids/human/scream/malescream_4.ogg',
			'sound/mobs/humanoids/human/scream/malescream_5.ogg',
			'sound/mobs/humanoids/human/scream/malescream_6.ogg',
		)

	return pick(
		'sound/mobs/humanoids/human/scream/femalescream_1.ogg',
		'sound/mobs/humanoids/human/scream/femalescream_2.ogg',
		'sound/mobs/humanoids/human/scream/femalescream_3.ogg',
		'sound/mobs/humanoids/human/scream/femalescream_4.ogg',
		'sound/mobs/humanoids/human/scream/femalescream_5.ogg',
	)

// A list, not a string: this fork's character menu maps over the description. Upstream's doc comment
// still says "Returns a string", and a string here crashes the menu with no runtime to show for it.
/datum/species/quarian/get_species_description()
	return list(
		"The quarians are a nomadic species of humanoid aliens known for their skill with technology and \
		synthetic intelligence. Since their homeworld Rannoch was conquered, the quarians have lived aboard \
		the Migrant Fleet, a huge collection of starships that travels as a single body. They created the \
		geth as a source of cheap labour, tried to destroy them when they became sentient, lost the war, and \
		have wandered the galaxy in salvaged and secondhand ships ever since.",
	)

/datum/species/quarian/get_species_lore()
	return list(
		"Quarians are generally shorter and of slighter build than humans. They have an endoskeleton, lips, teeth, \
		and two eyes with eyelids and tear ducts, and their eyes see into the ultraviolet. Their facial structure \
		and hair make them the most human-looking of the Citadel races from the neck up.",

		"From the waist down they are not human at all. Their lower legs bow backwards sharply, and they have three \
		thick fingers on each hand and three toes on each foot. Like humans, quarian blood is red.",

		"The most distinguishing feature of quarian biology is a weak immune system, compounded by centuries of \
		living in sterile environments. A quarian outside the Fleet normally wears a sealed enviro-suit, and a \
		breach in one is a serious medical event rather than an inconvenience.",
	)

/datum/species/quarian/create_pref_unique_perks()
	var/list/to_add = list()

	to_add += list(
		list(
			SPECIES_PERK_TYPE = SPECIES_NEUTRAL_PERK,
			SPECIES_PERK_ICON = "comment",
			SPECIES_PERK_NAME = "Knows Khelish",
			SPECIES_PERK_DESC = "You speak and understand Khelish in addition to Common.",
		),
		list(
			SPECIES_PERK_TYPE = SPECIES_NEUTRAL_PERK,
			SPECIES_PERK_ICON = "shoe-prints",
			SPECIES_PERK_NAME = "Digitigrade",
			SPECIES_PERK_DESC = "Your legs bend backwards. Footwear and jumpsuits that have no digitigrade cut \
				will not fit you.",
		),
		list(
			SPECIES_PERK_TYPE = SPECIES_POSITIVE_PERK,
			SPECIES_PERK_ICON = "hard-hat",
			SPECIES_PERK_NAME = "Born on a Hull",
			SPECIES_PERK_DESC = "A lifetime of patching a ship that was always falling apart. You put up \
				structural parts a quarter faster than anyone else.",
		),
		list(
			SPECIES_PERK_TYPE = SPECIES_POSITIVE_PERK,
			SPECIES_PERK_ICON = "sun",
			SPECIES_PERK_NAME = "Unimpressed by Rocks",
			SPECIES_PERK_DESC = "The supermatter cannot drive you mad, and it settles down while you are watching \
				it. Engineering will want you in the chamber.",
		),
		list(
			SPECIES_PERK_TYPE = SPECIES_NEGATIVE_PERK,
			SPECIES_PERK_ICON = "brain",
			SPECIES_PERK_NAME = "Thin Margins",
			SPECIES_PERK_DESC = "Generations of cheap cybernetics and recycled air leave little room for error. \
				Severe brain damage is far more likely to leave you with a lasting trauma, and surgery may not \
				clear it.",
		),
	)

	return to_add
