/datum/species/asari
	name = "Asari"
	id = SPECIES_ASARI
	inherent_traits = list(
		TRAIT_ADVANCEDTOOLUSER,
		TRAIT_CAN_STRIP,
		TRAIT_LITERATE,
		TRAIT_MUTANT_COLORS,
		TRAIT_SPECIAL_TRAUMA_BOOST,
	)
	inherent_biotypes = MOB_ORGANIC|MOB_HUMANOID
	// Mono-gender race: every asari is feminine, body and pronouns both. sexes stays TRUE so the
	// feminine uniform and chest sprites are used - turning it off renders them with the male silhouette.
	forced_physique = FEMALE
	forced_gender = FEMALE
	// Only the head is ours. Everything below the neck is a human limb, so examine should say so.
	examine_limb_id = SPECIES_HUMAN
	mutant_bodyparts = list()
	skinned_type = /obj/item/stack/sheet/animalhide/carbon/human
	species_language_holder = /datum/language_holder/asari
	changesource_flags = MIRROR_BADMIN | WABBAJACK | MIRROR_MAGIC | MIRROR_PRIDE | ERT_SPAWN | RACE_SWAP | SLIME_EXTRACT
	bodypart_overrides = list(
		BODY_ZONE_HEAD = /obj/item/bodypart/head/asari,
		BODY_ZONE_CHEST = /obj/item/bodypart/chest,
		BODY_ZONE_L_ARM = /obj/item/bodypart/arm/left,
		BODY_ZONE_R_ARM = /obj/item/bodypart/arm/right,
		BODY_ZONE_L_LEG = /obj/item/bodypart/leg/left,
		BODY_ZONE_R_LEG = /obj/item/bodypart/leg/right,
	)

/datum/species/asari/randomize_features()
	var/list/features = ..()
	var/skin_color = pick("#6699CC", "#7FA8D4", "#5C8FB8", "#8E7FC4", "#4F93A6", "#A07FB8")
	features[FEATURE_MUTANT_COLOR] = skin_color
	features[FEATURE_MUTANT_COLOR_TWO] = skin_color
	features[FEATURE_MUTANT_COLOR_THREE] = skin_color
	return features

/// Covers being turned into an asari mid-round, where no preferences are involved at all.
/datum/species/asari/on_species_gain(mob/living/carbon/human/human_who_gained_species, datum/species/old_species, pref_load, regenerate_icons = TRUE, replace_missing = TRUE)
	. = ..()
	apply_forced_body(human_who_gained_species)

/// Runs after every preference, so this is what beats the body type preference at character setup.
/datum/species/asari/apply_supplementary_body_changes(mob/living/carbon/human/target, datum/preferences/preferences, visuals_only = FALSE)
	. = ..()
	apply_forced_body(target)

/datum/species/asari/prepare_human_for_preview(mob/living/carbon/human/asari)
	var/skin_color = "#6699CC"
	asari.dna.features[FEATURE_MUTANT_COLOR] = skin_color
	asari.dna.features[FEATURE_MUTANT_COLOR_TWO] = skin_color
	asari.dna.features[FEATURE_MUTANT_COLOR_THREE] = skin_color
	apply_forced_body(asari)
	asari.update_body(TRUE)

/datum/species/asari/get_scream_sound(mob/living/carbon/human/human)
	return pick(
		'sound/mobs/humanoids/human/scream/femalescream_1.ogg',
		'sound/mobs/humanoids/human/scream/femalescream_2.ogg',
		'sound/mobs/humanoids/human/scream/femalescream_3.ogg',
		'sound/mobs/humanoids/human/scream/femalescream_4.ogg',
		'sound/mobs/humanoids/human/scream/femalescream_5.ogg',
	)

// A list, not a string: this fork's character menu maps over the description. Upstream's doc comment
// still says "Returns a string", and a string here crashes the menu with no runtime to show for it.
/datum/species/asari/get_species_description()
	return list(
		"The asari, native to the planet Thessia, are often considered the most influential and respected \
		sentient species in the galaxy, and are known for their elegance, diplomacy, and biotic aptitude. \
		This is partly due to the fact that the asari were among the earliest races to achieve interstellar \
		flight after the Protheans, and the first to discover and settle the Citadel.",
	)

/datum/species/asari/get_species_lore()
	return list(
		"A mono-gender race, the asari are distinctly feminine in appearance and possess maternal instincts. Their \
		unique physiology, expressed in a millennium-long lifespan and the ability to reproduce with a partner of any \
		gender or species, gives them a conservative yet convivial attitude toward other races. Favoring compromise \
		and cooperation over conflict, the asari were instrumental in proposing and founding the Citadel Council and \
		have been at the heart of galactic society ever since.",

		"In place of hair, an asari grows a semi-rigid crest of cartilage that settles into its adult shape late in \
		maidenhood. No two crests are identical, and reading one is how asari tell each other apart at a distance.",
	)

/datum/species/asari/create_pref_unique_perks()
	var/list/to_add = list()

	to_add += list(
		list(
			SPECIES_PERK_TYPE = SPECIES_NEUTRAL_PERK,
			SPECIES_PERK_ICON = "comment",
			SPECIES_PERK_NAME = "Knows High Thessian",
			SPECIES_PERK_DESC = "You speak and understand High Thessian in addition to Common.",
		),
		list(
			SPECIES_PERK_TYPE = SPECIES_NEUTRAL_PERK,
			SPECIES_PERK_ICON = "venus",
			SPECIES_PERK_NAME = "Mono-Gender",
			SPECIES_PERK_DESC = "There is only one asari sex. Your body is always feminine and you are always \
				she/her. The body type and gender options do not apply to you.",
		),
		list(
			SPECIES_PERK_TYPE = SPECIES_NEUTRAL_PERK,
			SPECIES_PERK_ICON = "palette",
			SPECIES_PERK_NAME = "Crested",
			SPECIES_PERK_DESC = "You grow a cartilage crest instead of hair. Your whole body takes its color from \
				your chosen skin tone.",
		),
		list(
			SPECIES_PERK_TYPE = SPECIES_NEGATIVE_PERK,
			SPECIES_PERK_ICON = "brain",
			SPECIES_PERK_NAME = "Fragile Mind",
			SPECIES_PERK_DESC = "The nervous system that makes an asari biotic does not take a beating well. Severe \
				brain damage is far more likely to leave you with a lasting trauma, and surgery may not clear it.",
		),
	)

	return to_add
