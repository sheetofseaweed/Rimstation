/datum/interaction
	/// The name displayed in the interaction menu.
	var/name = "broken interaction"
	/// The description shown in the interaction menu.
	var/description = "broken"
	/// Whether the interaction can be used at range.
	var/distance_allowed = FALSE
	/// Public emote text shown to nearby players.
	var/list/message = list()
	/// Direct feedback for the acting user.
	var/list/user_messages = list()
	/// Direct feedback for the target.
	var/list/target_messages = list()
	/// The interaction category shown in the UI.
	var/category = INTERACTION_CAT_HIDE
	/// How the interaction can be used: self, other, or both.
	var/usage = INTERACTION_OTHER
	/// Whether the interaction plays a sound.
	var/sound_use = FALSE
	/// How far the interaction sound can be heard.
	var/sound_range = 1
	/// Cached sound picked for this use.
	var/sound_cache = null
	/// Whether the interaction is considered lewd.
	var/lewd = FALSE
	/// Body parts the user must have.
	var/list/user_required_parts = list()
	/// Body parts the target must have.
	var/list/target_required_parts = list()
	/// Pleasure, arousal, and pain values applied to the target.
	var/target_pleasure = 0
	var/target_arousal = 0
	var/target_pain = 0
	/// Pleasure, arousal, and pain values applied to the user.
	var/user_pleasure = 0
	var/user_arousal = 0
	var/user_pain = 0
	/// Candidate sound files for this interaction.
	var/list/sound_possible = list()
	/// Extra requirements checked before the interaction can run.
	var/list/interaction_requires = list()
	/// Button color in the UI.
	var/color = "blue"
	/// Legacy compatibility field for json-defined interactions.
	var/sexuality = ""
	/// Which genital each side climaxes with when this interaction causes a climax.
	var/list/cum_genital = list(CLIMAX_POSITION_USER = null, CLIMAX_POSITION_TARGET = null)
	/// Where on or in the partner climax is directed.
	var/list/cum_target = list(CLIMAX_POSITION_USER = null, CLIMAX_POSITION_TARGET = null)
	/// Optional climax text overrides.
	var/list/cum_message_text_overrides = list(CLIMAX_POSITION_USER = list(), CLIMAX_POSITION_TARGET = list())
	var/list/cum_self_text_overrides = list(CLIMAX_POSITION_USER = list(), CLIMAX_POSITION_TARGET = list())
	var/list/cum_partner_text_overrides = list(CLIMAX_POSITION_USER = list(), CLIMAX_POSITION_TARGET = list())
	/// Whether the interaction requires special consent.
	var/unsafe_types = NONE
	/// Small badges displayed beside interaction buttons.
	var/list/additional_details = list()
	/// Internal modifier flags for interaction-specific logic.
	var/interaction_modifier_flags = NONE
	/// Temporary reagent transfer holders for future interactions.
	var/list/obj/item/reagent_containers/fluid_transfer_objects = list()

/datum/interaction/New()
	cum_message_text_overrides[CLIMAX_POSITION_USER] = sanitize_islist(cum_message_text_overrides[CLIMAX_POSITION_USER], list())
	cum_self_text_overrides[CLIMAX_POSITION_USER] = sanitize_islist(cum_self_text_overrides[CLIMAX_POSITION_USER], list())
	cum_partner_text_overrides[CLIMAX_POSITION_USER] = sanitize_islist(cum_partner_text_overrides[CLIMAX_POSITION_USER], list())
	cum_message_text_overrides[CLIMAX_POSITION_TARGET] = sanitize_islist(cum_message_text_overrides[CLIMAX_POSITION_TARGET], list())
	cum_self_text_overrides[CLIMAX_POSITION_TARGET] = sanitize_islist(cum_self_text_overrides[CLIMAX_POSITION_TARGET], list())
	cum_partner_text_overrides[CLIMAX_POSITION_TARGET] = sanitize_islist(cum_partner_text_overrides[CLIMAX_POSITION_TARGET], list())
	. = ..()

/datum/interaction/proc/allow_act(mob/living/carbon/human/user, mob/living/carbon/human/target)
	if(target == user && usage == INTERACTION_OTHER)
		return FALSE

	if(unsafe_types & INTERACTION_EXTREME)
		if(user.client?.prefs?.read_preference(/datum/preference/choiced/erp_status_extm) == "No" || target.client?.prefs?.read_preference(/datum/preference/choiced/erp_status_extm) == "No")
			return FALSE
	if(unsafe_types & INTERACTION_HARMFUL)
		if(user.client?.prefs?.read_preference(/datum/preference/choiced/erp_status_extmharm) == "No" || target.client?.prefs?.read_preference(/datum/preference/choiced/erp_status_extmharm) == "No")
			return FALSE
	if(unsafe_types & INTERACTION_UNHOLY)
		if(user.client?.prefs?.read_preference(/datum/preference/choiced/erp_status_unholy) == "No" || target.client?.prefs?.read_preference(/datum/preference/choiced/erp_status_unholy) == "No")
			return FALSE

	for(var/slot in user_required_parts)
		if(!user.has_genital(LAZYACCESS(user_required_parts, slot) || REQUIRE_GENITAL_EXPOSED, slot))
			return FALSE

	for(var/slot in target_required_parts)
		if(!target.has_genital(LAZYACCESS(target_required_parts, slot) || REQUIRE_GENITAL_EXPOSED, slot))
			return FALSE

	for(var/requirement in interaction_requires)
		switch(requirement)
			if(INTERACTION_REQUIRE_SELF_HUMAN)
				if(!ishuman(user))
					return FALSE
			if(INTERACTION_REQUIRE_TARGET_HUMAN)
				if(!ishuman(target))
					return FALSE
			if(INTERACTION_REQUIRE_SELF_HAND)
				if(!user.get_active_hand())
					return FALSE
			if(INTERACTION_REQUIRE_TARGET_HAND)
				if(!target.get_active_hand())
					return FALSE
			if(INTERACTION_REQUIRE_SELF_MOUTH)
				if(!user.get_bodypart(BODY_ZONE_HEAD) || user.is_mouth_covered())
					return FALSE
			if(INTERACTION_REQUIRE_TARGET_MOUTH)
				if(!target.get_bodypart(BODY_ZONE_HEAD) || target.is_mouth_covered())
					return FALSE
			if(INTERACTION_REQUIRE_SELF_TOPLESS)
				if(!user.is_topless())
					return FALSE
			if(INTERACTION_REQUIRE_TARGET_TOPLESS)
				if(!target.is_topless())
					return FALSE
			if(INTERACTION_REQUIRE_SELF_BOTTOMLESS)
				if(!user.is_bottomless())
					return FALSE
			if(INTERACTION_REQUIRE_TARGET_BOTTOMLESS)
				if(!target.is_bottomless())
					return FALSE
			if(INTERACTION_REQUIRE_SELF_FEET)
				if(user.has_feet() < (LAZYACCESS(user_required_parts, INTERACTION_REQUIRE_SELF_FEET) || 2))
					return FALSE
			if(INTERACTION_REQUIRE_TARGET_FEET)
				if(target.has_feet() < (LAZYACCESS(target_required_parts, INTERACTION_REQUIRE_TARGET_FEET) || 2))
					return FALSE
			else
				CRASH("Unimplemented interaction requirement '[requirement]'")

	return TRUE

/datum/interaction/proc/act(mob/living/carbon/human/user, mob/living/carbon/human/target, obj/body_relay = null)
	if(!allow_act(user, target))
		return FALSE
	if(!message)
		message_admins("Interaction had a null message list. '[name]'")
		return FALSE
	if(!islist(message) && istext(message))
		message_admins("Deprecated message handling for '[name]'. Correct format is a list with one entry. This message will only show once.")
		message = list(message)

	if(user == target && usage == INTERACTION_BOTH)
		user_pleasure += target_pleasure
		user_arousal += target_arousal
		user_pain += target_pain

	var/msg = pick(message)
	if(body_relay)
		msg = replacetext(msg, "%TARGET%", "\the [body_relay.name]")
	msg = trim(replacetext(replacetext(replacetext(msg, "%TARGET%", "[target]"), "%USER%", ""), "%KNOT%", "knot"), INTERACTION_MAX_CHAR)

	if(lewd)
		user.emote("subtle", null, span_purple(msg), TRUE)
	else
		user.manual_emote(msg)

	if(user_messages.len)
		var/user_msg = pick(user_messages)
		if(body_relay)
			user_msg = replacetext(user_msg, "%TARGET%", "\the [body_relay.name]")
		user_msg = replacetext(replacetext(replacetext(user_msg, "%TARGET%", "[target]"), "%USER%", "[user]"), "%KNOT%", "knot")
		to_chat(user, user_msg)

	if(target_messages.len)
		var/target_msg = pick(target_messages)
		if(body_relay)
			target_msg = replacetext(target_msg, "%USER%", "Unknown")
		target_msg = replacetext(replacetext(replacetext(target_msg, "%TARGET%", "[target]"), "%USER%", "[user]"), "%KNOT%", "knot")
		to_chat(target, target_msg)

	if(sound_use)
		if(!sound_possible)
			message_admins("Interaction has sound_use set to TRUE but no sound list. '[name]'")
			return FALSE
		if(!islist(sound_possible) && istext(sound_possible))
			message_admins("Deprecated sound handling for '[name]'. Correct format is a list with one entry. This message will only show once.")
			sound_possible = list(sound_possible)
		sound_cache = pick(sound_possible)
		conditional_pref_sound(user, sound_cache, 80, TRUE, falloff_distance = sound_range, pref_to_check = /datum/preference/toggle/erp/sounds)

	if(lewd)
		var/user_potency = user.dna?.features["sexual_potency"] || 1
		user.adjust_pleasure(user_pleasure * user_potency, target, src, CLIMAX_POSITION_USER)
		user.adjust_arousal(user_arousal)
		user.adjust_pain(user_pain)
		if(user != target)
			var/target_potency = target.dna?.features["sexual_potency"] || 1
			target.adjust_pleasure(target_pleasure * target_potency, user, src, CLIMAX_POSITION_TARGET)
			target.adjust_arousal(target_arousal)
			target.adjust_pain(target_pain)
		if(body_relay)
			var/obj/lewd_portal_relay/body_portal_relay = body_relay
			body_portal_relay.update_visuals()

	if(user == target && usage == INTERACTION_BOTH)
		user_pleasure -= target_pleasure
		user_arousal -= target_arousal
		user_pain -= target_pain

	post_interaction(user, target)
	return TRUE

/datum/interaction/proc/post_interaction(mob/living/carbon/human/user, mob/living/carbon/human/target)
	return

/// Builds custom climax messaging for interactions that define override text.
/datum/interaction/proc/show_climax(mob/living/cumming, mob/living/came_in, position)
	var/override_check = length(cum_message_text_overrides[position]) && length(cum_self_text_overrides[position]) && (length(cum_partner_text_overrides[position]) || cumming == came_in)
	if(!override_check)
		return FALSE

	var/cumming_their = cumming.p_their()
	var/cumming_them = cumming.p_them()
	var/came_in_them = came_in.p_them()
	var/came_in_their = came_in.p_their()
	var/genital_used = cum_genital[position]
	var/hole_used = cum_target[position]

	var/message = pick(cum_message_text_overrides[position])
	message = replacetext(message, "%CUMMING%", "[cumming]")
	message = replacetext(message, "%CUMMING_THEIR%", "[cumming_their]")
	message = replacetext(message, "%CUMMING_THEM%", "[cumming_them]")
	message = replacetext(message, "%CAME_IN%", "[came_in]")
	message = replacetext(message, "%CAME_IN_THEIR%", "[came_in_their]")
	message = replacetext(message, "%CAME_IN_THEM%", "[came_in_them]")
	message = replacetext(message, "%CUM_GENITAL%", "[genital_used]")
	message = replacetext(message, "%CUM_TARGET%", "[hole_used]")

	var/self_message = pick(cum_self_text_overrides[position])
	self_message = replacetext(self_message, "%CUMMING%", "[cumming]")
	self_message = replacetext(self_message, "%CUMMING_THEIR%", "[cumming_their]")
	self_message = replacetext(self_message, "%CUMMING_THEM%", "[cumming_them]")
	self_message = replacetext(self_message, "%CAME_IN%", "[came_in]")
	self_message = replacetext(self_message, "%CAME_IN_THEIR%", "[came_in_their]")
	self_message = replacetext(self_message, "%CAME_IN_THEM%", "[came_in_them]")
	self_message = replacetext(self_message, "%CUM_GENITAL%", "[genital_used]")
	self_message = replacetext(self_message, "%CUM_TARGET%", "[hole_used]")

	cumming.visible_message(span_userlove(message), span_userlove(self_message))

	if(cumming != came_in)
		var/partner_message = pick(cum_partner_text_overrides[position])
		partner_message = replacetext(partner_message, "%CUMMING%", "[cumming]")
		partner_message = replacetext(partner_message, "%CUMMING_THEIR%", "[cumming_their]")
		partner_message = replacetext(partner_message, "%CUMMING_THEM%", "[cumming_them]")
		partner_message = replacetext(partner_message, "%CAME_IN%", "[came_in]")
		partner_message = replacetext(partner_message, "%CAME_IN_THEIR%", "[came_in_their]")
		partner_message = replacetext(partner_message, "%CAME_IN_THEM%", "[came_in_them]")
		partner_message = replacetext(partner_message, "%CUM_GENITAL%", "[genital_used]")
		partner_message = replacetext(partner_message, "%CUM_TARGET%", "[hole_used]")
		to_chat(came_in, span_userlove(partner_message))

	return TRUE

/// Hook for interaction-specific climax side effects.
/datum/interaction/proc/post_climax(mob/living/carbon/human/cumming, mob/living/carbon/human/came_in, position)
	return

/datum/interaction/proc/load_from_json(path)
	if(!fexists(path))
		message_admins("Attempted to load an interaction from json and the file does not exist")
		qdel(src)
		return FALSE

	var/list/json = json_decode(file2text(path))
	name = sanitize_text(json["name"])
	description = sanitize_text(json["description"])
	distance_allowed = sanitize_integer(json["distance_allowed"], 0, 1, 0)
	message = sanitize_islist(json["message"], list("json error"))
	category = sanitize_text(json["category"])
	usage = sanitize_text(json["usage"])
	sound_use = sanitize_integer(json["sound_use"], 0, 1, 0)
	sound_range = sanitize_integer(json["sound_range"], 1, 7, 1)
	sound_possible = sanitize_islist(json["sound_possible"], list("json error"))
	interaction_requires = sanitize_islist(json["interaction_requires"], list())
	color = sanitize_text(json["color"])
	user_messages = sanitize_islist(json["user_messages"], list())
	user_required_parts = sanitize_islist(json["user_required_parts"], list())
	user_arousal = sanitize_integer(json["user_arousal"], 0, 100, 0)
	user_pleasure = sanitize_integer(json["user_pleasure"], 0, 100, 0)
	user_pain = sanitize_integer(json["user_pain"], 0, 100, 0)
	target_messages = sanitize_islist(json["target_messages"], list())
	target_required_parts = sanitize_islist(json["target_required_parts"], list())
	target_arousal = sanitize_integer(json["target_arousal"], 0, 100, 0)
	target_pleasure = sanitize_integer(json["target_pleasure"], 0, 100, 0)
	target_pain = sanitize_integer(json["target_pain"], 0, 100, 0)
	lewd = sanitize_integer(json["lewd"], 0, 1, 0)
	sexuality = sanitize_text(json["sexuality"])
	cum_genital[CLIMAX_POSITION_USER] = sanitize_text(json["cum_genital_user"])
	cum_genital[CLIMAX_POSITION_TARGET] = sanitize_text(json["cum_genital_target"])
	cum_target[CLIMAX_POSITION_USER] = sanitize_text(json["cum_target_user"])
	cum_target[CLIMAX_POSITION_TARGET] = sanitize_text(json["cum_target_target"])
	cum_message_text_overrides[CLIMAX_POSITION_USER] = sanitize_islist(json["cum_message_text_overrides_user"], list())
	cum_message_text_overrides[CLIMAX_POSITION_TARGET] = sanitize_islist(json["cum_message_text_overrides_target"], list())
	cum_self_text_overrides[CLIMAX_POSITION_USER] = sanitize_islist(json["cum_self_text_overrides_user"], list())
	cum_self_text_overrides[CLIMAX_POSITION_TARGET] = sanitize_islist(json["cum_self_text_overrides_target"], list())
	cum_partner_text_overrides[CLIMAX_POSITION_USER] = sanitize_islist(json["cum_partner_text_overrides_user"], list())
	cum_partner_text_overrides[CLIMAX_POSITION_TARGET] = sanitize_islist(json["cum_partner_text_overrides_target"], list())

	var/list/unsafe_flags = list(
		"extreme" = INTERACTION_EXTREME,
		"extremeharm" = INTERACTION_EXTREME | INTERACTION_HARMFUL,
		"unholy" = INTERACTION_UNHOLY,
	)
	for(var/unsafe_type in sanitize_islist(json["unsafe_types"], list()))
		unsafe_types |= unsafe_flags[unsafe_type]

	return TRUE

/datum/interaction/proc/json_save(path)
	if(fexists(path))
		fdel(path)

	var/list/json = list(
		"name" = name,
		"description" = description,
		"distance_allowed" = distance_allowed,
		"message" = message,
		"category" = category,
		"usage" = usage,
		"sound_use" = sound_use,
		"sound_range" = sound_range,
		"sound_possible" = sound_possible,
		"interaction_requires" = interaction_requires,
		"color" = color,
		"user_messages" = user_messages,
		"user_required_parts" = user_required_parts,
		"user_arousal" = user_arousal,
		"user_pleasure" = user_pleasure,
		"user_pain" = user_pain,
		"target_messages" = target_messages,
		"target_required_parts" = target_required_parts,
		"target_arousal" = target_arousal,
		"target_pleasure" = target_pleasure,
		"target_pain" = target_pain,
		"lewd" = lewd,
		"sexuality" = sexuality,
		"cum_genital_user" = cum_genital[CLIMAX_POSITION_USER],
		"cum_genital_target" = cum_genital[CLIMAX_POSITION_TARGET],
		"cum_target_user" = cum_target[CLIMAX_POSITION_USER],
		"cum_target_target" = cum_target[CLIMAX_POSITION_TARGET],
		"cum_message_text_overrides_user" = cum_message_text_overrides[CLIMAX_POSITION_USER],
		"cum_message_text_overrides_target" = cum_message_text_overrides[CLIMAX_POSITION_TARGET],
		"cum_self_text_overrides_user" = cum_self_text_overrides[CLIMAX_POSITION_USER],
		"cum_self_text_overrides_target" = cum_self_text_overrides[CLIMAX_POSITION_TARGET],
		"cum_partner_text_overrides_user" = cum_partner_text_overrides[CLIMAX_POSITION_USER],
		"cum_partner_text_overrides_target" = cum_partner_text_overrides[CLIMAX_POSITION_TARGET],
	)

	var/list/unsafe_flags = list()
	if(unsafe_types & INTERACTION_EXTREME)
		unsafe_flags += "extreme"
	if(unsafe_types & INTERACTION_HARMFUL)
		unsafe_flags += "extremeharm"
	if(unsafe_types & INTERACTION_UNHOLY)
		unsafe_flags += "unholy"
	json["unsafe_types"] = unsafe_flags

	var/file = file(path)
	WRITE_FILE(file, json_encode(json))
	return TRUE

/mob/living/carbon/human/Initialize(mapload)
	. = ..()
	AddComponent(/datum/component/interactable)

/proc/get_interaction_registry()
	if(!islist(SSinteractions?.interactions))
		SSinteractions.interactions = list()
	return SSinteractions.interactions

/proc/populate_interaction_instances()
	var/list/datum/interaction/registry = get_interaction_registry()
	for(var/spath in subtypesof(/datum/interaction))
		var/datum/interaction/interaction = new spath()
		if(interaction.name == /datum/interaction::name || interaction.description == /datum/interaction::description)
			continue
		registry[interaction.name] = interaction
	populate_interaction_jsons(INTERACTION_JSON_FOLDER)

/proc/populate_interaction_jsons(directory)
	var/list/datum/interaction/registry = get_interaction_registry()
	for(var/file_name in flist(directory))
		var/file_path = directory + file_name
		if(flist(file_path) && !findlasttext(file_path, ".json"))
			populate_interaction_jsons(file_path)
			continue
		if(findlasttext(file_path, ".master.json"))
			populate_interaction_jsons_master(file_path)
			continue
		var/datum/interaction/interaction = new()
		if(interaction.load_from_json(file_path))
			registry[interaction.name] = interaction
		else
			message_admins("Error loading interaction from file: '[file_path]'. Inform coders.")

/proc/populate_interaction_jsons_master(path)
	var/list/datum/interaction/registry = get_interaction_registry()
	if(!fexists(path))
		message_admins("We are attempting to load an interaction master without the file existing! '[path]'")
		return

	var/list/json = json_decode(file2text(path))
	for(var/iname in json)
		if(registry[iname])
			message_admins("Interaction Master '[path]' contained a duplicate interaction! '[iname]'")
			continue

		var/list/ijson = json[iname]
		var/datum/interaction/interaction = new()
		interaction.name = sanitize_text(ijson["name"])
		if(interaction.name != iname)
			message_admins("Interaction Master '[path]' contained an invalid interaction! '[iname]'")
			continue

		interaction.description = sanitize_text(ijson["description"])
		interaction.distance_allowed = sanitize_integer(ijson["distance_allowed"], 0, 1, 0)
		interaction.message = sanitize_islist(ijson["message"], list("json error"))
		interaction.category = sanitize_text(ijson["category"])
		interaction.usage = sanitize_text(ijson["usage"])
		interaction.sound_use = sanitize_integer(ijson["sound_use"], 0, 1, 0)
		interaction.sound_range = sanitize_integer(ijson["sound_range"], 1, 7, 1)
		interaction.sound_possible = sanitize_islist(ijson["sound_possible"], list("json error"))
		interaction.interaction_requires = sanitize_islist(ijson["interaction_requires"], list())
		interaction.color = sanitize_text(ijson["color"])
		interaction.user_messages = sanitize_islist(ijson["user_messages"], list())
		interaction.user_required_parts = sanitize_islist(ijson["user_required_parts"], list())
		interaction.user_arousal = sanitize_integer(ijson["user_arousal"], 0, 100, 0)
		interaction.user_pleasure = sanitize_integer(ijson["user_pleasure"], 0, 100, 0)
		interaction.user_pain = sanitize_integer(ijson["user_pain"], 0, 100, 0)
		interaction.target_messages = sanitize_islist(ijson["target_messages"], list())
		interaction.target_required_parts = sanitize_islist(ijson["target_required_parts"], list())
		interaction.target_arousal = sanitize_integer(ijson["target_arousal"], 0, 100, 0)
		interaction.target_pleasure = sanitize_integer(ijson["target_pleasure"], 0, 100, 0)
		interaction.target_pain = sanitize_integer(ijson["target_pain"], 0, 100, 0)
		interaction.lewd = sanitize_integer(ijson["lewd"], 0, 1, 0)
		interaction.sexuality = sanitize_text(ijson["sexuality"])

		var/list/unsafe_flags = list(
			"extreme" = INTERACTION_EXTREME,
			"extremeharm" = INTERACTION_EXTREME | INTERACTION_HARMFUL,
			"unholy" = INTERACTION_UNHOLY,
		)
		for(var/unsafe_type in sanitize_islist(ijson["unsafe_types"], list()))
			interaction.unsafe_types |= unsafe_flags[unsafe_type]

		registry[iname] = interaction

ADMIN_VERB(reload_interactions, R_DEBUG, "Reload Interactions", "Force reload interactions.", ADMIN_CATEGORY_DEBUG)
	SSinteractions.prepare_interactions()
