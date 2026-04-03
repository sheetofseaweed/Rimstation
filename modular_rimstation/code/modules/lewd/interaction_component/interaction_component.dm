/datum/component/interactable
	/// Preferences toggled from the interaction menu and saved when the UI closes.
	var/list/modified_preferences = list()
	/// Toggle preferences displayed in the interaction menu.
	var/static/list/preference_paths = list(
		"master_erp_pref" = /datum/preference/toggle/master_erp_preferences,
		"base_erp_pref" = /datum/preference/toggle/erp,
		"erp_sounds_pref" = /datum/preference/toggle/erp/sounds,
		"sextoy_pref" = /datum/preference/toggle/erp/sex_toy,
		"sextoy_sounds_pref" = /datum/preference/toggle/erp/sex_toy_sounds,
		"bimbofication_pref" = /datum/preference/toggle/erp/bimbofication,
		"aphro_pref" = /datum/preference/toggle/erp/aphro,
		"breast_enlargement_pref" = /datum/preference/toggle/erp/breast_enlargement,
		"breast_shrinkage_pref" = /datum/preference/toggle/erp/breast_shrinkage,
		"penis_enlargement_pref" = /datum/preference/toggle/erp/penis_enlargement,
		"penis_shrinkage_pref" = /datum/preference/toggle/erp/penis_shrinkage,
		"gender_change_pref" = /datum/preference/toggle/erp/gender_change,
		"autocum_pref" = /datum/preference/toggle/erp/autocum,
		"autoemote_pref" = /datum/preference/toggle/erp/autoemote,
		"genitalia_removal_pref" = /datum/preference/toggle/erp/genitalia_removal,
		"new_genitalia_growth_pref" = /datum/preference/toggle/erp/new_genitalia_growth,
		"butt_enlargement_pref" = /datum/preference/toggle/erp/butt_enlargement,
		"butt_shrinkage_pref" = /datum/preference/toggle/erp/butt_shrinkage,
		"belly_enlargement_pref" = /datum/preference/toggle/erp/belly_enlargement,
		"belly_shrinkage_pref" = /datum/preference/toggle/erp/belly_shrinkage,
		"forced_neverboner_pref" = /datum/preference/toggle/erp/forced_neverboner,
		"custom_genital_fluids_pref" = /datum/preference/toggle/erp/custom_genital_fluids,
		"cumflation_pref" = /datum/preference/toggle/erp/cumflation,
		"cumflates_partners_pref" = /datum/preference/toggle/erp/cumflates_partners,
		"knotting_pref" = /datum/preference/toggle/erp/knotting,
		"knots_partners_pref" = /datum/preference/toggle/erp/knots_partners,
		"favorite_interactions" = /datum/preference/blob/favorite_interactions,
		"vore_enable_pref" = /datum/preference/toggle/erp/vore_enable,
		"vore_overlays" = /datum/preference/toggle/erp/vore_overlays,
		"vore_overlay_options" = /datum/preference/toggle/erp/vore_overlay_options,
	)
	/// Character-level consent preferences displayed in the interaction menu.
	var/static/list/character_preference_paths = list(
		"erp_pref" = /datum/preference/choiced/erp_status,
		"noncon_pref" = /datum/preference/choiced/erp_status_nc,
		"vore_pref" = /datum/preference/choiced/erp_status_v,
		"extreme_pref" = /datum/preference/choiced/erp_status_extm,
		"extreme_harm" = /datum/preference/choiced/erp_status_extmharm,
		"unholy_pref" = /datum/preference/choiced/erp_status_unholy,
	)
	/// Cached preference values so the menu can redraw without hammering the client preference object.
	var/list/cached_preferences = list()
	/// Auto interaction definitions keyed by interaction name and target ref.
	var/list/auto_interaction_info = list()

	/// A hard reference to the parent.
	var/mob/living/carbon/human/self = null
	/// A list of interactions that the user can engage in.
	var/list/datum/interaction/interactions
	var/interact_last = 0
	var/interact_next = 0
	/// Holds a reference to a relayed body if one exists.
	var/obj/body_relay = null

/datum/component/interactable/Initialize(...)
	if(QDELETED(parent))
		qdel(src)
		return

	if(!ishuman(parent))
		return COMPONENT_INCOMPATIBLE

	self = parent
	add_verb(self, /mob/living/carbon/human/proc/interact_with)
	build_interactions_list()

/datum/component/interactable/RegisterWithParent()
	RegisterSignal(parent, COMSIG_CLICK_CTRL_SHIFT, PROC_REF(open_interaction_menu))

/datum/component/interactable/UnregisterFromParent()
	UnregisterSignal(parent, COMSIG_CLICK_CTRL_SHIFT)

/datum/component/interactable/Destroy(force, silent)
	STOP_PROCESSING(SSinteractions, src)
	self = null
	interactions = null
	cached_preferences = null
	auto_interaction_info = null
	return ..()

/datum/component/interactable/process(seconds_per_tick)
	if(!LAZYLEN(auto_interaction_info))
		return PROCESS_KILL

	for(var/interaction_text in auto_interaction_info)
		var/list/interaction_data = auto_interaction_info[interaction_text]
		var/datum/interaction/interaction = SSinteractions.interactions[splittext(interaction_text, "_target_")[1]]
		var/mob/living/carbon/human/target = locate(interaction_data["target"])
		var/datum/component/interactable/target_component = target?.GetComponent(/datum/component/interactable)
		if(!interaction || !target || QDELETED(target))
			auto_interaction_info -= interaction_text
			continue
		if(!interaction.allow_act(self, target))
			auto_interaction_info -= interaction_text
			continue
		if(interaction.lewd && !target.client?.prefs?.read_preference(/datum/preference/toggle/erp))
			auto_interaction_info -= interaction_text
			continue
		if(!interaction.distance_allowed && !self.Adjacent(target))
			if(self.loc != target.loc || isturf(self.loc))
				if(!target_component?.body_relay || !self.Adjacent(target_component.body_relay))
					auto_interaction_info -= interaction_text
					continue
		if(interaction.category == INTERACTION_CAT_HIDE)
			auto_interaction_info -= interaction_text
			continue

		if(world.time < interaction_data["next_interaction"])
			continue

		interaction.act(self, target)
		interaction_data["next_interaction"] = world.time + (interaction_data["speed"] SECONDS)

/datum/component/interactable/proc/build_interactions_list()
	interactions = list()
	if(!SSinteractions)
		return

	for(var/interaction_id in SSinteractions.interactions)
		var/datum/interaction/interaction = SSinteractions.interactions[interaction_id]
		if(interaction.lewd && !self.client?.prefs?.read_preference(/datum/preference/toggle/erp))
			continue
		interactions += interaction

/datum/component/interactable/proc/open_interaction_menu(datum/source, mob/user)
	if(!ishuman(user))
		return

	build_interactions_list()
	ui_interact(user)

/datum/component/interactable/proc/can_interact(datum/interaction/interaction, mob/living/carbon/human/target)
	if(!interaction.allow_act(target, self))
		return FALSE
	if(interaction.lewd && !target.client?.prefs?.read_preference(/datum/preference/toggle/erp))
		return FALSE
	if(!interaction.distance_allowed && !target.Adjacent(self))
		if(target.loc != self.loc || isturf(target.loc))
			if(!body_relay || !target.Adjacent(body_relay))
				return FALSE
	if(interaction.category == INTERACTION_CAT_HIDE)
		return FALSE
	if(self == target && interaction.usage == INTERACTION_OTHER)
		return FALSE
	return TRUE

/datum/component/interactable/ui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "InteractionPanel")
		ui.open()

/datum/component/interactable/ui_status(mob/user, datum/ui_state/state)
	if(!ishuman(user))
		return UI_CLOSE

	return UI_INTERACTIVE

/datum/component/interactable/ui_data(mob/living/carbon/human/user)
	var/list/data = list()
	var/list/descriptions = list()
	var/list/categories = list()
	var/list/display_categories = list()
	var/list/colors = list()
	var/list/additional_details = list()
	var/datum/component/interactable/user_interaction_component = user.GetComponent(/datum/component/interactable)

	if(!LAZYLEN(cached_preferences))
		update_cached_preferences(user)

	for(var/datum/interaction/interaction in interactions)
		if(!can_interact(interaction, user))
			continue
		if(!categories[interaction.category])
			categories[interaction.category] = list(interaction.name)
		else
			categories[interaction.category] += interaction.name
			categories[interaction.category] = sort_list(categories[interaction.category])
		descriptions[interaction.name] = interaction.description
		colors[interaction.name] = interaction.color
		if(length(interaction.additional_details))
			additional_details[interaction.name] = interaction.additional_details

	for(var/category in categories)
		display_categories += category

	data["categories"] = sort_list(display_categories)
	data["interactions"] = categories
	data["descriptions"] = descriptions
	data["colors"] = colors
	data["additional_details"] = additional_details
	data["ref_user"] = REF(user)
	data["ref_self"] = REF(self)
	data["self"] = self.name
	data["block_interact"] = user_interaction_component?.interact_next >= world.time
	data["isTargetSelf"] = (user == self)
	data["interactingWith"] = user == self ? "Interacting with yourself..." : "Interacting with [self]..."
	data["favorite_interactions"] = cached_preferences["favorite_interactions"] || list()

	if(body_relay && !can_see(user, self))
		data["self"] = body_relay.name

	data["pleasure"] = user.pleasure || 0
	data["maxPleasure"] = AROUSAL_LIMIT * (user.dna?.features["lust_tolerance"] || 1)
	data["arousal"] = user.arousal || 0
	data["maxArousal"] = AROUSAL_LIMIT
	data["pain"] = user.pain || 0
	data["maxPain"] = AROUSAL_LIMIT
	data["selfAttributes"] = get_interaction_attributes(user)

	if(user != self)
		data["theirPleasure"] = self.pleasure || 0
		data["theirMaxPleasure"] = AROUSAL_LIMIT * (self.dna?.features["lust_tolerance"] || 1)
		data["theirArousal"] = self.arousal || 0
		data["theirMaxArousal"] = AROUSAL_LIMIT
		data["theirPain"] = self.pain || 0
		data["theirMaxPain"] = AROUSAL_LIMIT
		data["theirAttributes"] = get_interaction_attributes(self)
	else
		data["theirPleasure"] = null
		data["theirMaxPleasure"] = null
		data["theirArousal"] = null
		data["theirMaxArousal"] = null
		data["theirPain"] = null
		data["theirMaxPain"] = null
		data["theirAttributes"] = list()

	for(var/entry in character_preference_paths)
		var/datum/preference/choiced/preference_entry = GLOB.preference_entries[character_preference_paths[entry]]
		data[entry] = cached_preferences[entry]
		data["[entry]_values"] = preference_entry.get_choices()

	for(var/entry in preference_paths)
		data[entry] = cached_preferences[entry]

	var/list/genital_list = list()
	for(var/obj/item/organ/genital/genital in user.organs)
		if(genital.visibility_preference == GENITAL_SKIP_VISIBILITY)
			continue
		genital_list += list(list(
			"name" = genital.name,
			"slot" = genital.slot,
			"visibility" = genital.visibility_preference,
			"aroused" = genital.aroused,
			"can_arouse" = genital.aroused != AROUSAL_CANT,
		))
	data["genitals"] = genital_list

	var/list/parts = list()
	if(can_lewd_strip(user, self) && self.client?.prefs?.read_preference(/datum/preference/toggle/erp/sex_toy))
		if(self.has_vagina())
			parts += list(generate_strip_entry(ORGAN_SLOT_VAGINA, self, user, self.vagina))
		if(self.has_penis())
			parts += list(generate_strip_entry(ORGAN_SLOT_PENIS, self, user, self.penis))
		if(self.has_anus())
			parts += list(generate_strip_entry(ORGAN_SLOT_ANUS, self, user, self.anus))
		parts += list(generate_strip_entry(ORGAN_SLOT_NIPPLES, self, user, self.nipples))
	data["lewd_slots"] = parts

	data["auto_interaction_speed_values"] = list(
		INTERACTION_SPEED_MIN * (1 / (1 SECONDS)),
		INTERACTION_SPEED_MAX * (1 / (1 SECONDS)),
	)
	data["auto_interaction_info"] = user_interaction_component?.auto_interaction_info || list()

	return data

/datum/component/interactable/proc/generate_strip_entry(name, mob/living/carbon/human/target, mob/living/carbon/human/source, obj/item/clothing/sextoy/item)
	return list(
		"name" = name,
		"img" = (item && can_lewd_strip(source, target, name)) ? icon2base64(icon(item.icon, item.icon_state, SOUTH, 1)) : null,
		"item_name" = item ? item.name : null,
	)

/datum/component/interactable/ui_close(mob/user)
	cached_preferences = list()
	if(length(modified_preferences) && user.client?.prefs)
		user.client.prefs.save_character()
		user.client.prefs.save_preferences()
	modified_preferences.Cut()

/datum/component/interactable/proc/update_cached_preferences(mob/living/carbon/human/user, list/preferences)
	if(LAZYLEN(preferences))
		for(var/entry in preferences)
			cached_preferences[entry] = user.client?.prefs?.read_preference(character_preference_paths[entry] || preference_paths[entry])
		return

	cached_preferences = list()
	for(var/entry in character_preference_paths)
		cached_preferences[entry] = user.client?.prefs?.read_preference(character_preference_paths[entry])
	for(var/entry in preference_paths)
		cached_preferences[entry] = user.client?.prefs?.read_preference(preference_paths[entry])

/datum/component/interactable/proc/get_interaction_attributes(mob/living/carbon/human/target)
	var/list/attributes = list()

	if(target.has_arms())
		attributes += "have hands"

	if(target.get_bodypart(BODY_ZONE_HEAD))
		attributes += "have a mouth, which is [target.is_mouth_covered() ? "covered" : "uncovered"]"

	if(target.refractory_period > REALTIMEOFDAY)
		attributes += "are sexually exhausted for the time being"

	if(target.combat_mode)
		attributes += "are fighting anyone who comes near"
	else
		attributes += "are acting gentle"

	var/is_topless = target.is_topless()
	var/is_bottomless = target.is_bottomless()
	if(is_topless && is_bottomless)
		attributes += "are naked"
	else if(is_topless || is_bottomless)
		attributes += "are partially clothed"
	else
		attributes += "are clothed"

	if(target.has_penis(REQUIRE_GENITAL_EXPOSED))
		attributes += "have a penis"
	if(target.has_balls(REQUIRE_GENITAL_EXPOSED))
		attributes += "have a ballsack"
	if(target.has_vagina(REQUIRE_GENITAL_EXPOSED))
		attributes += "have a vagina"
	if(target.has_breasts(REQUIRE_GENITAL_EXPOSED))
		attributes += "have breasts"
	if(target.has_anus(REQUIRE_GENITAL_EXPOSED))
		attributes += "have an anus"
	if(target.has_belly(REQUIRE_GENITAL_EXPOSED))
		attributes += "have a belly"

	var/num_feet = target.has_feet(REQUIRE_GENITAL_EXPOSED)
	if(num_feet >= 2)
		attributes += "have a pair of feet"
	else if(num_feet == 1)
		attributes += "have a single foot"

	if(target.has_tail(REQUIRE_GENITAL_ANY))
		attributes += "have a tail"

	return attributes

/datum/component/interactable/ui_act(action, list/params)
	. = ..()
	if(.)
		return
	if(!ishuman(usr))
		return

	var/mob/living/carbon/human/user = usr
	var/datum/preferences/prefs = user.client?.prefs

	switch(action)
		if("interact")
			var/interaction_id = params["interaction"]
			var/mob/living/carbon/human/source = locate(params["userref"])
			var/mob/living/carbon/human/target = locate(params["selfref"])
			var/datum/component/interactable/source_component = source?.GetComponent(/datum/component/interactable)
			if(!interaction_id || !source || !target || !source_component)
				return FALSE

			var/datum/interaction/selected_interaction
			for(var/datum/interaction/interaction in interactions)
				if(interaction.name == interaction_id)
					selected_interaction = interaction
					break

			if(!selected_interaction || !can_interact(selected_interaction, source))
				return FALSE
			if(source_component.interact_next >= world.time)
				return FALSE

			if(body_relay && !can_see(user, self))
				selected_interaction.act(source, target, body_relay)
			else
				selected_interaction.act(source, target)

			source_component.interact_last = world.time
			source_component.interact_next = source_component.interact_last + INTERACTION_COOLDOWN
			return TRUE

		if("favorite")
			if(!prefs)
				return FALSE

			var/interaction_id = params["interaction"]
			if(!interaction_id)
				return FALSE

			var/list/favorite_interactions = prefs.read_preference(/datum/preference/blob/favorite_interactions) || list()
			if(interaction_id in favorite_interactions)
				favorite_interactions -= interaction_id
			else
				favorite_interactions += interaction_id

			prefs.update_preference(GLOB.preference_entries[/datum/preference/blob/favorite_interactions], favorite_interactions)
			modified_preferences |= "favorite_interactions"
			update_cached_preferences(user, list("favorite_interactions"))
			return TRUE

		if("pref")
			if(!prefs)
				return FALSE

			var/pref_path = LAZYACCESS(preference_paths, params["pref"])
			if(!pref_path)
				return FALSE

			if(!isnull(params["amount"]))
				prefs.update_preference(GLOB.preference_entries[pref_path], params["amount"])
			else
				prefs.update_preference(GLOB.preference_entries[pref_path], !prefs.read_preference(pref_path))

			modified_preferences |= params["pref"]
			update_cached_preferences(user, list(params["pref"]))
			return TRUE

		if("char_pref")
			if(!prefs)
				return FALSE

			var/pref_path = LAZYACCESS(character_preference_paths, params["char_pref"])
			if(!pref_path)
				return FALSE

			var/value = params["value"]
			var/datum/preference/choiced/pref_type = GLOB.preference_entries[pref_path]
			var/list/valid_values = pref_type.get_choices()
			if(!(value in valid_values))
				return FALSE

			prefs.update_preference(pref_type, value)
			modified_preferences |= params["char_pref"]
			update_cached_preferences(user, list(params["char_pref"]))
			return TRUE

		if("item_slot")
			var/item_index = params["item_slot"]
			var/mob/living/carbon/human/source = locate(params["userref"])
			var/mob/living/carbon/human/target = locate(params["selfref"])
			if(!source || !target)
				return FALSE

			var/obj/item/clothing/sextoy/new_item = source.get_active_held_item()
			var/obj/item/clothing/sextoy/existing_item = target.vars[item_index]
			if(!existing_item && !new_item)
				source.show_message(span_warning("No item to insert or remove!"))
				return FALSE
			if(!existing_item && !istype(new_item))
				source.show_message(span_warning("The item you're holding is not a toy!"))
				return FALSE
			if(!can_lewd_strip(source, target, item_index) || !is_toy_compatible(new_item, item_index))
				source.show_message(span_warning("Failed to adjust [target.name]'s toys!"))
				return FALSE

			var/internal = item_index in list(ORGAN_SLOT_VAGINA, ORGAN_SLOT_ANUS)
			var/insert_or_attach = internal ? "insert" : "attach"
			var/into_or_onto = internal ? "into" : "onto"

			if(existing_item)
				source.visible_message(span_purple("[source.name] starts trying to remove something from [target.name]'s [item_index]."), span_purple("You start to remove [existing_item.name] from [target.name]'s [item_index]."), span_purple("You hear someone trying to remove something from someone nearby."), vision_distance = 1, ignored_mobs = list(target))
			else
				source.visible_message(span_purple("[source.name] starts trying to [insert_or_attach] the [new_item.name] [into_or_onto] [target.name]'s [item_index]."), span_purple("You start to [insert_or_attach] the [new_item.name] [into_or_onto] [target.name]'s [item_index]."), span_purple("You hear someone trying to [insert_or_attach] something [into_or_onto] someone nearby."), vision_distance = 1, ignored_mobs = list(target))

			if(source != target)
				target.show_message(span_warning("[source.name] is trying to [existing_item ? "remove the [existing_item.name] [internal ? "in" : "on"]" : "[insert_or_attach] the [new_item.name] [into_or_onto]"] your [item_index]!"))

			if(!do_after(source, 5 SECONDS, target, interaction_key = "interaction_[item_index]") || !can_lewd_strip(source, target, item_index))
				return FALSE

			if(existing_item)
				source.visible_message(span_purple("[source.name] removes [existing_item.name] from [target.name]'s [item_index]."), span_purple("You remove [existing_item.name] from [target.name]'s [item_index]."), span_purple("You hear someone remove something from someone nearby."), vision_distance = 1)
				target.dropItemToGround(existing_item, force = TRUE)
				source.put_in_hands(existing_item, forced = TRUE)
				target.vars[item_index] = null
			else
				source.visible_message(span_purple("[source.name] [internal ? "inserts" : "attaches"] the [new_item.name] [into_or_onto] [target.name]'s [item_index]."), span_purple("You [insert_or_attach] the [new_item.name] [into_or_onto] [target.name]'s [item_index]."), span_purple("You hear someone [insert_or_attach] something [into_or_onto] someone nearby."), vision_distance = 1)
				target.vars[item_index] = new_item
				new_item.forceMove(target)
				new_item.lewd_equipped(target, item_index)

			target.update_inv_lewd()
			return TRUE

		if("toggle_genital_visibility")
			var/obj/item/organ/genital/genital = user.get_organ_slot(params["genital"])
			if(!genital)
				return FALSE

			var/visibility = text2num("[params["visibility"]]")
			if(!(visibility in list(GENITAL_NEVER_SHOW, GENITAL_HIDDEN_BY_CLOTHES, GENITAL_ALWAYS_SHOW)))
				return FALSE

			genital.visibility_preference = visibility
			user.update_body()
			return TRUE

		if("toggle_genital_arousal")
			var/obj/item/organ/genital/genital = user.get_organ_slot(params["genital"])
			if(!genital || genital.aroused == AROUSAL_CANT)
				return FALSE

			var/arousal = text2num("[params["arousal"]]")
			if(!(arousal in list(AROUSAL_NONE, AROUSAL_PARTIAL, AROUSAL_FULL)))
				return FALSE

			genital.aroused = arousal
			genital.update_sprite_suffix()
			user.update_body()
			return TRUE

		if("auto_interaction")
			var/interaction_text = params["interaction_text"]
			var/datum/component/interactable/user_component = user.GetComponent(/datum/component/interactable)
			var/datum/interaction/interaction = SSinteractions.interactions[splittext(interaction_text, "_target_")[1]]
			if(!interaction || !user_component)
				return FALSE

			if(params["action"] == "stop")
				user_component.auto_interaction_info -= interaction_text
				return TRUE

			var/already_processing = LAZYLEN(user_component.auto_interaction_info)
			user_component.auto_interaction_info[interaction_text] = list(
				"speed" = clamp(round(text2num("[params["speed"]]"), 0.5), INTERACTION_SPEED_MIN * (1 / (1 SECONDS)), INTERACTION_SPEED_MAX * (1 / (1 SECONDS))),
				"target" = params["selfref"],
				"target_name" = self.name,
				"next_interaction" = world.time,
			)
			if(!already_processing)
				START_PROCESSING(SSinteractions, user_component)
			return TRUE

	message_admins("Unhandled interaction action '[action]'. Inform coders.")
	return FALSE

/datum/component/interactable/proc/can_lewd_strip(mob/living/carbon/human/source, mob/living/carbon/human/target, slot_index)
	if(!target.client?.prefs?.read_preference(/datum/preference/toggle/erp/sex_toy))
		return FALSE
	if(!(source.loc == target.loc || source.Adjacent(target)))
		return FALSE
	if(!source.has_arms())
		return FALSE
	if(!slot_index)
		return TRUE

	switch(slot_index)
		if(ORGAN_SLOT_NIPPLES)
			var/chest_exposed = target.has_breasts(required_state = REQUIRE_GENITAL_EXPOSED)
			if(!chest_exposed)
				chest_exposed = target.is_topless()
			return chest_exposed
		if(ORGAN_SLOT_PENIS)
			return target.has_penis(required_state = REQUIRE_GENITAL_EXPOSED)
		if(ORGAN_SLOT_VAGINA)
			return target.has_vagina(required_state = REQUIRE_GENITAL_EXPOSED)
		if(ORGAN_SLOT_ANUS)
			return target.has_anus(required_state = REQUIRE_GENITAL_EXPOSED)
		else
			return FALSE

/datum/component/interactable/proc/is_toy_compatible(obj/item/clothing/sextoy/item, slot_index)
	if(!item)
		return TRUE

	switch(slot_index)
		if(ORGAN_SLOT_VAGINA)
			return item.lewd_slot_flags & LEWD_SLOT_VAGINA
		if(ORGAN_SLOT_PENIS)
			return item.lewd_slot_flags & LEWD_SLOT_PENIS
		if(ORGAN_SLOT_ANUS)
			return item.lewd_slot_flags & LEWD_SLOT_ANUS
		if(ORGAN_SLOT_NIPPLES)
			return item.lewd_slot_flags & LEWD_SLOT_NIPPLES
		else
			return FALSE

/mob/living/carbon/human/proc/interact_with()
	set name = "Interact With"
	set desc = "Perform an interaction with someone."
	set category = "IC"
	set src in view(usr.client)

	var/datum/component/interactable/menu = GetComponent(/datum/component/interactable)
	if(!menu)
		to_chat(src, span_warning("You do not have an interaction component."))
		return

	menu.open_interaction_menu(src, usr)
