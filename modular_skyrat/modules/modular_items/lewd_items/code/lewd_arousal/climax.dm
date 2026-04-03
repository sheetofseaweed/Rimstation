
#define CLIMAX_ON_FLOOR "On the floor"
#define CLIMAX_IN_OR_ON "Climax in or on someone"
#define CLIMAX_OPEN_CONTAINER "Fill reagent container"
#define CLIMAX_PORTAL "Through the portal"

// both of these are pretty much arbitrary
#define MIN_CUM_THRESHOLD 5
#define MIN_VAGINA_WETNESS_THRESHOLD 3.33

/mob/living/carbon/human
	/// Used to prevent nightmare scenarios.
	var/refractory_period

/mob/living/carbon/human/proc/get_interaction_fluid_transfer_object(datum/interaction/climax_interaction, mob/living/carbon/human/partner)
	if(!istype(climax_interaction) || !length(climax_interaction.fluid_transfer_objects))
		return null

	var/list/fluid_transfer_objects = climax_interaction.fluid_transfer_objects
	var/obj/item/reagent_containers/transfer_object = fluid_transfer_objects[REF(partner)]
	if(istype(transfer_object))
		return transfer_object

	transfer_object = fluid_transfer_objects[REF(src)]
	if(istype(transfer_object))
		return transfer_object

	for(var/key in fluid_transfer_objects)
		if(istype(key, /obj/item/reagent_containers))
			return key

		transfer_object = fluid_transfer_objects[key]
		if(istype(transfer_object))
			return transfer_object

	return null

/mob/living/carbon/human/proc/resolve_interaction_climax_target(datum/interaction/climax_interaction, interaction_position, mob/living/carbon/human/partner, list/available_targets)
	var/requested_target = climax_interaction?.cum_target[interaction_position]
	if(!requested_target || !partner)
		return null

	var/obj/item/organ/genital/partner_genital = partner.get_organ_slot(requested_target)
	if(istype(partner_genital))
		return partner_genital.slot

	if(available_targets?.Find(requested_target))
		return requested_target

	return null

/mob/living/carbon/human/proc/climax(manual = TRUE, mob/living/carbon/human/partner = null, datum/interaction/climax_interaction = null, interaction_position = null)
	if (CONFIG_GET(flag/disable_erp_preferences))
		return

	if(!client?.prefs?.read_preference(/datum/preference/toggle/erp/autocum) && !manual)
		return
	if(refractory_period > REALTIMEOFDAY)
		return
	refractory_period = REALTIMEOFDAY + 30 SECONDS
	if(has_status_effect(/datum/status_effect/climax_cooldown) || !client?.prefs?.read_preference(/datum/preference/toggle/erp))
		return

	if(HAS_TRAIT(src, TRAIT_NEVERBONER) || has_status_effect(/datum/status_effect/climax_cooldown) || (!has_vagina() && !has_penis()))
		visible_message(span_purple("[src] twitches, trying to cum, but with no result."), \
			span_purple("You can't have an orgasm!"))
		return TRUE

	// Reduce pop-ups and make it slightly more frictionless (lewd).
	var/climax_choice = has_penis() ? CLIMAX_PENIS : CLIMAX_VAGINA

	if(manual)
		var/list/genitals = list()
		if(has_vagina())
			genitals.Add(CLIMAX_VAGINA)
			if(has_penis())
				genitals.Add(CLIMAX_PENIS)
				genitals.Add(CLIMAX_BOTH)
		else if(has_penis())
			genitals.Add(CLIMAX_PENIS)
		climax_choice = tgui_alert(src, "You are climaxing, choose which genitalia to climax with.", "Genitalia Preference!", genitals)
	else if(istype(climax_interaction) && climax_interaction.cum_genital[interaction_position])
		climax_choice = climax_interaction.cum_genital[interaction_position]

	switch(gender)
		if(MALE)
			conditional_pref_sound(get_turf(src), pick('modular_skyrat/modules/modular_items/lewd_items/sounds/final_m1.ogg',
										'modular_skyrat/modules/modular_items/lewd_items/sounds/final_m2.ogg',
										'modular_skyrat/modules/modular_items/lewd_items/sounds/final_m3.ogg'), 50, TRUE, pref_to_check = /datum/preference/toggle/erp/sounds)
		if(FEMALE)
			conditional_pref_sound(get_turf(src), pick('modular_skyrat/modules/modular_items/lewd_items/sounds/final_f1.ogg',
										'modular_skyrat/modules/modular_items/lewd_items/sounds/final_f2.ogg',
										'modular_skyrat/modules/modular_items/lewd_items/sounds/final_f3.ogg'), 50, TRUE, pref_to_check = /datum/preference/toggle/erp/sounds)

	var/self_orgasm = FALSE
	var/self_their = p_their()

	var/obj/item/organ/genital/testicles/testicles = get_organ_slot(ORGAN_SLOT_TESTICLES)
	testicles?.calculate_cumshot()

	if(climax_choice == CLIMAX_PENIS || climax_choice == CLIMAX_BOTH)
		var/obj/item/organ/genital/penis/penis = get_organ_slot(ORGAN_SLOT_PENIS)
		if(!testicles || testicles.reagents.total_volume < MIN_CUM_THRESHOLD) //If we have no god damn balls, we can't cum anywhere... GET BALLS! , OR theres so little in your balls that nothing comes out...
			visible_message(span_userlove("[src] orgasms, but nothing comes out of [self_their] penis!"), \
				span_userlove("You orgasm, it feels great, but nothing comes out of your penis!"))

		else if(is_wearing_condom())
			var/obj/item/clothing/sextoy/condom/condom = src.penis // bruh 💀⚰️💀⚰️💀⚰️💀⚰️💀
			condom.condom_use() // condoms probably should become reagent containers at some point
			visible_message(span_userlove("[src] shoots [self_their] load into the [condom], filling it up!"), \
				span_userlove("You shoot your thick load into the [condom] and it catches it all!"))
			testicles.reagents.remove_all(testicles.cumshot_size)

		else if(!is_bottomless() && penis.visibility_preference != GENITAL_ALWAYS_SHOW)
			visible_message(span_userlove("[src] cums inside [self_their] clothes!"), \
				span_userlove("You shoot your load, but you weren't naked, so you mess up your clothes!"))
			self_orgasm = TRUE
			testicles.reagents.remove_all(testicles.cumshot_size)

		else
			var/list/interactable_inrange_humans = list()
			var/list/interactable_inrange_open_containers = list()
			var/obj/item/reagent_containers/interaction_container = get_interaction_fluid_transfer_object(climax_interaction, partner)
			var/mob/living/carbon/human/target_human = null
			var/obj/item/reagent_containers/target_open_container = null
			var/climax_into_choice = null
			var/fluid_consumed = FALSE

			for(var/mob/living/carbon/human/iterating_human in (view(1, src) - src))
				interactable_inrange_humans[iterating_human.name] = iterating_human

			for(var/obj/item/reagent_containers/iterating_open_container in view(1, src))
				if(!(iterating_open_container.is_open_container() || istype(iterating_open_container, /obj/item/reagent_containers/cup)))
					continue
				interactable_inrange_open_containers[iterating_open_container.name] = iterating_open_container

			var/list/buttons = list(CLIMAX_ON_FLOOR)
			if(interactable_inrange_humans.len)
				buttons += CLIMAX_IN_OR_ON

			if(interactable_inrange_open_containers.len)
				buttons += CLIMAX_OPEN_CONTAINER

			// If your using a LustWish portal lets you cum through it
			var/obj/structure/lewd_portal/portal = src.buckled
			if(istype(portal, /obj/structure/lewd_portal))
				buttons += CLIMAX_PORTAL

			var/use_interaction_container = istype(interaction_container) && (!climax_interaction?.cum_target[interaction_position] || !partner)
			var/penis_climax_choice = climax_interaction && !manual ? CLIMAX_IN_OR_ON : tgui_alert(src, "Choose where to shoot your load.", "Load preference!", buttons)

			var/create_cum_decal = FALSE

			if(!penis_climax_choice || penis_climax_choice == CLIMAX_ON_FLOOR)
				create_cum_decal = TRUE
				visible_message(span_userlove("[src] shoots [self_their] sticky load onto the floor!"), \
					span_userlove("You shoot string after string of hot cum, hitting the floor!"))
			else if(penis_climax_choice == CLIMAX_OPEN_CONTAINER || use_interaction_container)
				var/target_choice = use_interaction_container ? interaction_container.name : tgui_input_list(src, "Choose a container to cum into.", "Choose target!", interactable_inrange_open_containers)
				if(!target_choice)
					create_cum_decal = TRUE
					visible_message(span_userlove("[src] shoots [self_their] sticky load onto the floor!"), \
						span_userlove("You shoot string after string of hot cum, hitting the floor!"))
				else
					target_open_container = use_interaction_container ? interaction_container : interactable_inrange_open_containers[target_choice]
					if(target_open_container.is_refillable() && target_open_container.is_drainable())
						// here's where we actually do the cumming(?)
						var/cum_volume = testicles.cumshot_size
						var/total_volume_w_cum = cum_volume + target_open_container.reagents.total_volume
						conditional_pref_sound(get_turf(src), SFX_DESECRATION, 50, TRUE, pref_to_check = /datum/preference/toggle/erp/sounds)
						if(target_open_container.reagents.holder_full())
							// its full already
							add_cum_splatter_floor(get_turf(target_open_container))
							visible_message(span_userlove("[src] tries to cum into the [target_open_container], but it's already full, spilling their hot load onto the floor!"), \
								span_userlove("You try to cum into the [target_open_container], but it's already full, so it all hits the floor instead!"))
						else
							testicles.reagents.trans_to(target_open_container, testicles.cumshot_size, transferred_by = src)
							fluid_consumed = TRUE
							if(total_volume_w_cum > target_open_container.volume)
								// overflow, make the decal
								add_cum_splatter_floor(get_turf(target_open_container))
								visible_message(span_userlove("[src] shoots [self_their] sticky load into the [target_open_container], it's so full that it overflows!"), \
									span_userlove("You shoot string after string of hot cum into the [target_open_container], making it overflow!"))
							else
								visible_message(span_userlove("[src] shoots [self_their] sticky load into the [target_open_container]!"), \
									span_userlove("You shoot string after string of hot cum into the [target_open_container]!"))
					else
						// cum fail
						create_cum_decal = TRUE
						visible_message(span_userlove("[src] shoots [self_their] sticky load onto the floor!"), \
							span_userlove("You shoot string after string of hot cum, hitting the floor!"))

			else if(penis_climax_choice == CLIMAX_PORTAL)
				to_chat(src, "You shoot string after string of hot cum, hitting whatever is on the other side!")
				portal.relayed_body.visible_message("[portal.relayed_body] shoots its sticky load onto the floor!")
				add_cum_splatter_floor(get_turf(portal.relayed_body))
				testicles.reagents.remove_all(testicles.cumshot_size)
				fluid_consumed = TRUE

			else
				var/target_choice = climax_interaction && !manual && partner ? partner.name : tgui_input_list(src, "Choose a person to cum in or on.", "Choose target!", interactable_inrange_humans)
				if(!target_choice)
					create_cum_decal = TRUE
					visible_message(span_userlove("[src] shoots [self_their] sticky load onto the floor!"), \
						span_userlove("You shoot string after string of hot cum, hitting the floor!"))
				else
					target_human = climax_interaction && !manual && partner ? partner : interactable_inrange_humans[target_choice]
					var/target_human_them = target_human.p_them()
					var/list/target_buttons = list()

					if(!target_human.wear_mask)
						target_buttons += CLIMAX_TARGET_MOUTH
					if(target_human.has_vagina(REQUIRE_GENITAL_EXPOSED))
						target_buttons += ORGAN_SLOT_VAGINA
					if(target_human.has_anus(REQUIRE_GENITAL_EXPOSED))
						target_buttons += ORGAN_SLOT_ANUS
					if(target_human.has_penis(REQUIRE_GENITAL_EXPOSED))
						var/obj/item/organ/genital/penis/other_penis = target_human.get_organ_slot(ORGAN_SLOT_PENIS)
						if(other_penis.sheath != "None")
							target_buttons += CLIMAX_TARGET_SHEATH
					target_buttons += "On [target_human_them]"

					var/interaction_target = resolve_interaction_climax_target(climax_interaction, interaction_position, target_human, target_buttons)
					if(climax_interaction && !manual && interaction_target)
						climax_into_choice = interaction_target
					else if(manual)
						climax_into_choice = tgui_input_list(src, "Where on or in [target_human] do you wish to cum?", "Final frontier!", target_buttons)
					else
						climax_into_choice = "On [target_human_them]"

					if(climax_interaction && !manual && climax_interaction.show_climax(src, target_human, interaction_position))
						create_cum_decal = !interaction_target
					else if(!climax_into_choice)
						create_cum_decal = TRUE
						visible_message(span_userlove("[src] shoots their sticky load onto the floor!"), \
							span_userlove("You shoot string after string of hot cum, hitting the floor!"))
					else if(climax_into_choice == "On [target_human_them]")
						create_cum_decal = TRUE
						visible_message(span_userlove("[src] shoots their sticky load onto [target_human]!"), \
							span_userlove("You shoot string after string of hot cum onto [target_human]!"))
					else
						visible_message(
							span_userlove("[src] hilts [self_their] cock into [target_human]'s [climax_into_choice], shooting cum into [target_human_them]!"),
							span_userlove("You hilt your cock into [target_human]'s [climax_into_choice], shooting cum into [target_human_them]!"))
						to_chat(target_human, span_userlove("Your [climax_into_choice] fills with warm cum as [src] shoots [self_their] load into it."))

						if(climax_into_choice == CLIMAX_TARGET_MOUTH)
							testicles.reagents.trans_to(target_human, testicles.cumshot_size, transferred_by = src, methods = INGEST)
							fluid_consumed = TRUE

			if(create_cum_decal)
				if(!fluid_consumed)
					testicles.reagents.remove_all(testicles.cumshot_size)
				add_cum_splatter_floor(get_turf(src))
			else if(target_human && !fluid_consumed)
				testicles.reagents.remove_all(testicles.cumshot_size)

		try_lewd_autoemote("moan")
		if(climax_choice == CLIMAX_PENIS)
			apply_status_effect(/datum/status_effect/climax)
			apply_status_effect(/datum/status_effect/climax_cooldown)
			if(self_orgasm)
				add_mood_event("orgasm", /datum/mood_event/climaxself)
			if(climax_interaction && !manual)
				climax_interaction.post_climax(src, partner, interaction_position)
			return TRUE

	if(climax_choice == CLIMAX_VAGINA || climax_choice == CLIMAX_BOTH)
		var/obj/item/organ/genital/vagina/vagina = get_organ_slot(ORGAN_SLOT_VAGINA)
		if(!is_bottomless() && vagina?.visibility_preference != GENITAL_ALWAYS_SHOW)
			if(vagina.reagents.total_volume >= MIN_VAGINA_WETNESS_THRESHOLD)
				visible_message(
					span_userlove("[src] cums in [self_their] underwear from [self_their] vagina!"),
					span_userlove("You cum in your underwear from your vagina! Eww."))
				self_orgasm = TRUE
			else
				visible_message(
					span_userlove("[src] cums in [self_their] underwear from [self_their] vagina!"),
					span_userlove("You cum in your underwear from your vagina, but you aren't wet enough to mess it up."))
		else
			var/list/interactable_inrange_humans = list()
			var/list/interactable_inrange_open_containers = list()
			var/obj/item/reagent_containers/interaction_container = get_interaction_fluid_transfer_object(climax_interaction, partner)
			var/mob/living/carbon/human/target_human = null
			var/obj/item/reagent_containers/target_open_container = null
			var/climax_into_choice = null
			var/fluid_consumed = FALSE

			for(var/mob/living/carbon/human/iterating_human in (view(1, src) - src))
				interactable_inrange_humans[iterating_human.name] = iterating_human

			for(var/obj/item/reagent_containers/iterating_open_container in view(1, src))
				if(!(iterating_open_container.is_open_container() || istype(iterating_open_container, /obj/item/reagent_containers/cup)))
					continue
				interactable_inrange_open_containers[iterating_open_container.name] = iterating_open_container

			var/list/buttons = list(CLIMAX_ON_FLOOR)
			if(interactable_inrange_humans.len)
				buttons += CLIMAX_IN_OR_ON
			if(interactable_inrange_open_containers.len)
				buttons += CLIMAX_OPEN_CONTAINER

			var/obj/structure/lewd_portal/portal = src.buckled
			if(istype(portal, /obj/structure/lewd_portal))
				buttons += CLIMAX_PORTAL

			var/use_interaction_container = istype(interaction_container) && (!climax_interaction?.cum_target[interaction_position] || !partner)
			var/vagina_climax_choice = climax_interaction && !manual ? CLIMAX_IN_OR_ON : tgui_alert(src, "Choose where to squirt.", "Squirt preference!", buttons)
			var/create_cum_decal = FALSE

			if(!vagina_climax_choice || vagina_climax_choice == CLIMAX_ON_FLOOR)
				create_cum_decal = TRUE
				visible_message(span_userlove("[src] twitches and moans as [p_they()] squirt on the floor!"), \
					span_userlove("You twitch and moan as you squirt on the floor!"))
			else if(vagina_climax_choice == CLIMAX_OPEN_CONTAINER || use_interaction_container)
				var/target_choice = use_interaction_container ? interaction_container.name : tgui_input_list(src, "Choose a container to squirt into.", "Choose target!", interactable_inrange_open_containers)
				if(!target_choice)
					create_cum_decal = TRUE
					visible_message(span_userlove("[src] squirts onto the floor!"), \
						span_userlove("You squirt onto the floor!"))
				else
					target_open_container = use_interaction_container ? interaction_container : interactable_inrange_open_containers[target_choice]
					if(target_open_container.is_refillable() && target_open_container.is_drainable())
						var/squirt_volume = vagina.reagents.total_volume
						var/total_volume_w_squirt = squirt_volume + target_open_container.reagents.total_volume
						conditional_pref_sound(get_turf(src), SFX_DESECRATION, 50, TRUE, pref_to_check = /datum/preference/toggle/erp/sounds)
						if(target_open_container.reagents.holder_full())
							add_cum_splatter_floor(get_turf(target_open_container), female = TRUE)
							visible_message(span_userlove("[src] tries to squirt into the [target_open_container], but it's already full, spilling onto the floor!"), \
								span_userlove("You try to squirt into the [target_open_container], but it's already full, so it all hits the floor instead!"))
						else
							vagina.reagents.trans_to(target_open_container, vagina.reagents.total_volume, transferred_by = src)
							fluid_consumed = TRUE
							if(total_volume_w_squirt > target_open_container.volume)
								add_cum_splatter_floor(get_turf(target_open_container), female = TRUE)
								visible_message(span_userlove("[src] squirts into the [target_open_container], it's so full that it overflows!"), \
									span_userlove("You squirt into the [target_open_container], making it overflow!"))
							else
								visible_message(span_userlove("[src] squirts into the [target_open_container]!"), \
									span_userlove("You squirt into the [target_open_container]!"))
					else
						create_cum_decal = TRUE
						visible_message(span_userlove("[src] squirts onto the floor!"), \
							span_userlove("You squirt onto the floor!"))
			else if(vagina_climax_choice == CLIMAX_PORTAL)
				to_chat(src, "You squirt through the portal, hitting whatever is on the other side!")
				portal.relayed_body.visible_message("[portal.relayed_body] squirts onto the floor!")
				add_cum_splatter_floor(get_turf(portal.relayed_body), female = TRUE)
				vagina.reagents.remove_all(vagina.reagents.total_volume)
				fluid_consumed = TRUE
			else
				var/target_choice = climax_interaction && !manual && partner ? partner.name : tgui_input_list(src, "Choose who to squirt on.", "Choose target!", interactable_inrange_humans)
				if(!target_choice)
					create_cum_decal = TRUE
					visible_message(span_userlove("[src] twitches and moans as [p_they()] squirt on the floor!"), \
						span_userlove("You twitch and moan as you squirt on the floor!"))
				else
					target_human = climax_interaction && !manual && partner ? partner : interactable_inrange_humans[target_choice]
					var/target_human_them = target_human.p_them()
					var/list/target_buttons = list()

					if(!target_human.wear_mask)
						target_buttons += CLIMAX_TARGET_MOUTH
					if(target_human.has_vagina(REQUIRE_GENITAL_EXPOSED))
						target_buttons += ORGAN_SLOT_VAGINA
					if(target_human.has_anus(REQUIRE_GENITAL_EXPOSED))
						target_buttons += ORGAN_SLOT_ANUS
					if(target_human.has_penis(REQUIRE_GENITAL_EXPOSED))
						target_buttons += ORGAN_SLOT_PENIS
						var/obj/item/organ/genital/penis/other_penis = target_human.get_organ_slot(ORGAN_SLOT_PENIS)
						if(other_penis?.sheath != "None")
							target_buttons += CLIMAX_TARGET_SHEATH
					target_buttons += "On [target_human_them]"

					var/interaction_target = resolve_interaction_climax_target(climax_interaction, interaction_position, target_human, target_buttons)
					if(climax_interaction && !manual && interaction_target)
						climax_into_choice = interaction_target
					else if(manual)
						climax_into_choice = tgui_input_list(src, "Where on or in [target_human] do you wish to squirt?", "Final frontier!", target_buttons)
					else
						climax_into_choice = "On [target_human_them]"

					if(climax_interaction && !manual && climax_interaction.show_climax(src, target_human, interaction_position))
						create_cum_decal = !interaction_target
					else if(!climax_into_choice)
						create_cum_decal = TRUE
						visible_message(span_userlove("[src] squirts on the floor!"), \
							span_userlove("You squirt on the floor!"))
					else if(climax_into_choice == "On [target_human_them]")
						create_cum_decal = TRUE
						visible_message(span_userlove("[src] squirts all over [target_human]!"), \
							span_userlove("You squirt all over [target_human]!"))
					else
						visible_message(span_userlove("[src] squirts into [target_human]'s [climax_into_choice]!"), \
							span_userlove("You squirt into [target_human]'s [climax_into_choice]!"))
						to_chat(target_human, span_userlove("Your [climax_into_choice] fills with [src]'s fluids."))

						if(climax_into_choice == CLIMAX_TARGET_MOUTH)
							vagina.reagents.trans_to(target_human, vagina.reagents.total_volume, transferred_by = src, methods = INGEST)
							fluid_consumed = TRUE

			if(create_cum_decal)
				if(!fluid_consumed)
					vagina.reagents.remove_all(vagina.reagents.total_volume)
				add_cum_splatter_floor(get_turf(src), female = TRUE)
			else if(target_human && !fluid_consumed)
				vagina.reagents.remove_all(vagina.reagents.total_volume)

	apply_status_effect(/datum/status_effect/climax)
	apply_status_effect(/datum/status_effect/climax_cooldown)
	if(self_orgasm)
		add_mood_event("orgasm", /datum/mood_event/climaxself)
	if(climax_interaction && !manual)
		climax_interaction.post_climax(src, partner, interaction_position)
	return TRUE

#undef CLIMAX_VAGINA
#undef CLIMAX_PENIS
#undef CLIMAX_BOTH
#undef CLIMAX_ON_FLOOR
#undef CLIMAX_IN_OR_ON
#undef CLIMAX_OPEN_CONTAINER

#undef MIN_CUM_THRESHOLD
#undef MIN_VAGINA_WETNESS_THRESHOLD
#undef CLIMAX_PORTAL
