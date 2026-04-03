/mob/living/carbon/human/proc/adjust_pleasure(pleas = 0, mob/living/carbon/human/partner = null, datum/interaction/interaction = null, position = null)
	if(stat >= DEAD || !client?.prefs?.read_preference(/datum/preference/toggle/erp))
		return

	var/lust_tolerance = dna?.features["lust_tolerance"] || 1
	pleasure = clamp(pleasure + pleas, AROUSAL_MINIMUM, AROUSAL_LIMIT * lust_tolerance)

	if(pleasure >= (AROUSAL_AUTO_CLIMAX_THRESHOLD * lust_tolerance) && pleas > 0)
		climax(manual = FALSE, partner = partner, climax_interaction = interaction, interaction_position = position)
