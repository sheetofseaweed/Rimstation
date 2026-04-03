/mob/living/carbon/human/proc/has_genital(required_state = REQUIRE_GENITAL_ANY, genital_slot)
	switch(genital_slot)
		if(ORGAN_SLOT_PENIS)
			return has_penis(required_state)
		if(ORGAN_SLOT_TESTICLES)
			return has_balls(required_state)
		if(ORGAN_SLOT_VAGINA)
			return has_vagina(required_state)
		if(ORGAN_SLOT_BREASTS)
			return has_breasts(required_state)
		if(ORGAN_SLOT_ANUS)
			return has_anus(required_state)
		if(ORGAN_SLOT_BUTT)
			return FALSE
		if(ORGAN_SLOT_BELLY)
			return FALSE
		else
			return FALSE

/mob/living/carbon/human/proc/has_butt(required_state = REQUIRE_GENITAL_ANY)
	return FALSE

/mob/living/carbon/human/proc/has_belly(required_state = REQUIRE_GENITAL_ANY)
	return FALSE

/// Rimstation does not currently expose the older four-way action intent state.
/// Interaction ports use this helper for flavor text, so we collapse it to help/harm.
/proc/resolve_intent_name(mob/living/user)
	if(!istype(user))
		return "help"

	if(user.combat_mode)
		return "harm"

	return "help"
