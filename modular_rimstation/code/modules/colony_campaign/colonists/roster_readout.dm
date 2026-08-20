/**
 * Where the colony reads its own roster.
 *
 * The whole phase is invisible without this. A colonist's history, their skills and their attendance are all
 * stored where nothing in the world shows them - which is the same hole that made storyteller recovery
 * unfalsifiable until it was given a readout. If nobody can see that Vera has been here six chapters and is
 * the best builder in the settlement, then none of it happened as far as the people playing are concerned.
 *
 * Skill is shown as a level to everybody and as a number only to its owner. A small settlement knows who its
 * best builder is, which is the practical reason to read this at all; the exact experience behind it is
 * nobody else's business.
 */
/obj/machinery/computer/colony_register
	name = "colony register"
	desc = "A record of everyone who has lived here, what they learned, and who did not come back."
	icon_screen = "medcomp"
	icon_keyboard = "med_key"
	circuit = /obj/item/circuitboard/computer/colony_register
	light_color = LIGHT_COLOR_ORANGE

/obj/item/circuitboard/computer/colony_register
	name = "Colony Register (Computer Board)"
	greyscale_colors = CIRCUIT_COLOR_GENERIC
	build_path = /obj/machinery/computer/colony_register

/obj/machinery/computer/colony_register/ui_interact(mob/user, datum/tgui/ui)
	. = ..()
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "ColonyRegister", name)
		ui.open()

/**
 * The roster as the person standing at the console sees it.
 *
 * Left on autoupdate rather than pushed from the several places a roster changes - joining, dying, claiming a
 * bed. A roster is a handful of records of plain values with no icon work or text building behind it, so the
 * per-tick cost is negligible, and a readout that silently goes stale because one change site forgot to push
 * would be a worse failure than the one this console exists to fix.
 */
/obj/machinery/computer/colony_register/ui_data(mob/user)
	var/list/data = list()

	var/datum/campaign_manifest/manifest = SScampaign.manifest
	data["campaign"] = manifest?.campaign_id
	data["generation"] = manifest?.generation_number
	data["chapter"] = manifest?.chapter

	var/datum/colonist_record/viewer = SScampaign.get_colonist_record_for_body(user)
	data["viewer_id"] = viewer?.colonist_id

	var/list/colonists = list()
	var/datum/colonist_roster/colony = SScampaign.get_roster()
	for(var/colonist_id in colony?.records)
		var/datum/colonist_record/record = colony.records[colonist_id]
		var/is_you = (record == viewer)

		var/list/skills = list()
		for(var/stored_path in record.skills)
			var/skill_type = text2path(stored_path)
			if(!skill_type || !(skill_type in GLOB.skill_types))
				continue
			var/datum/skill/known = skill_type
			var/experience = record.skills[stored_path]
			skills += list(list(
				"name" = initial(known.name),
				"level" = colonist_skill_level_name(experience),
				// Only its owner sees the number behind the level.
				"experience" = is_you ? experience : null,
			))

		colonists += list(list(
			"id" = record.colonist_id,
			"name" = record.display_name,
			"status" = record.status,
			"chapters_attended" = record.chapters_attended,
			"chapter_joined" = record.chapter_joined,
			"generation_joined" = record.generation_joined,
			"has_home" = !isnull(record.home_point),
			"is_you" = is_you,
			"skills" = skills,
		))

	data["colonists"] = colonists
	return data

/**
 * What a stored experience figure is called.
 *
 * Worked out from the number rather than read off a mind, because the roster holds people who are not in the
 * round - the away and the dead have no mind to ask. Mirrors update_skill_level(): the level is the highest
 * threshold the experience has reached.
 */
/proc/colonist_skill_level_name(experience)
	if(!isnum(experience) || experience <= 0)
		return SSskills.level_names[SKILL_LEVEL_NONE]

	var/list/thresholds = SKILL_EXP_LIST
	var/level = SKILL_LEVEL_NONE
	for(var/index in 1 to length(thresholds))
		if(experience >= thresholds[index])
			level = index
	return SSskills.level_names[level]
