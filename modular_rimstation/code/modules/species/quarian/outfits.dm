/**
 * A quarian spawns in their own enviro-suit instead of the job's uniform.
 *
 * pre_equip_species_outfit() runs before the job outfit, and the job's own uniform, gloves, shoes and
 * head are then deleted on arrival because those slots are already full. That is the same mechanism
 * plasmamen use for their envirosuit.
 *
 * The source build carried one outfit datum per job and a quarian_outfit var on every /datum/job. This
 * reads the department off the job instead, so only the handful of jobs whose colour does not follow
 * their department need naming.
 */
/datum/outfit/quarian
	name = "Quarian Enviro-suit"
	uniform = /obj/item/clothing/under/quarian/white
	gloves = /obj/item/clothing/gloves/quarian
	shoes = /obj/item/clothing/shoes/quarian
	head = /obj/item/clothing/head/helmet/space/quarian/white
	mask = /obj/item/clothing/mask/breath

/datum/outfit/quarian/black
	name = "Quarian Enviro-suit (Black)"
	uniform = /obj/item/clothing/under/quarian/black
	head = /obj/item/clothing/head/helmet/space/quarian/black

/datum/outfit/quarian/red
	name = "Quarian Enviro-suit (Red)"
	uniform = /obj/item/clothing/under/quarian/red
	head = /obj/item/clothing/head/helmet/space/quarian/red

/datum/outfit/quarian/orange
	name = "Quarian Enviro-suit (Orange)"
	uniform = /obj/item/clothing/under/quarian/orange
	head = /obj/item/clothing/head/helmet/space/quarian/orange

/datum/outfit/quarian/yellow
	name = "Quarian Enviro-suit (Yellow)"
	uniform = /obj/item/clothing/under/quarian/yellow
	head = /obj/item/clothing/head/helmet/space/quarian/yellow

/datum/outfit/quarian/green
	name = "Quarian Enviro-suit (Green)"
	uniform = /obj/item/clothing/under/quarian/green
	head = /obj/item/clothing/head/helmet/space/quarian/green

/datum/outfit/quarian/blue
	name = "Quarian Enviro-suit (Blue)"
	uniform = /obj/item/clothing/under/quarian/blue
	head = /obj/item/clothing/head/helmet/space/quarian/blue

/datum/outfit/quarian/violet
	name = "Quarian Enviro-suit (Violet)"
	uniform = /obj/item/clothing/under/quarian/violet
	head = /obj/item/clothing/head/helmet/space/quarian/violet


/// Jobs whose suit colour does not follow their department.
GLOBAL_LIST_INIT(quarian_outfits_by_job, list(
	/datum/job/bartender = /datum/outfit/quarian/black,
	/datum/job/chaplain = /datum/outfit/quarian/black,
	/datum/job/chemist = /datum/outfit/quarian/orange,
	/datum/job/clown = /datum/outfit/quarian/orange,
	/datum/job/cook = /datum/outfit/quarian,
	/datum/job/janitor = /datum/outfit/quarian/violet,
	/datum/job/mime = /datum/outfit/quarian/black,
	/datum/job/prisoner = /datum/outfit/quarian/orange,
	/datum/job/psychologist = /datum/outfit/quarian/green,
	/datum/job/shaft_miner = /datum/outfit/quarian/violet,
))

/datum/species/quarian/pre_equip_species_outfit(datum/job/job, mob/living/carbon/human/equipping, visuals_only = FALSE)
	equipping.equipOutfit(get_quarian_outfit(job), visuals_only)

/// Picks a suit colour: the job's own entry first, then its department, then plain white.
/datum/species/quarian/proc/get_quarian_outfit(datum/job/job)
	if(isnull(job))
		return /datum/outfit/quarian

	var/by_job = GLOB.quarian_outfits_by_job[job.type]
	if(by_job)
		return by_job

	// departments_list, not departments_bitflags: the bitflags are stripped back off a job when a map
	// disables it, so on a colony map every station job would fall through to the default.
	// Command is checked last so a head wears their own department's colour, not a command one.
	var/list/departments = job.departments_list
	if(!length(departments))
		return /datum/outfit/quarian

	if(/datum/job_department/security in departments)
		return /datum/outfit/quarian/blue
	if(/datum/job_department/engineering in departments)
		return /datum/outfit/quarian/yellow
	if(/datum/job_department/medical in departments)
		return /datum/outfit/quarian/red
	if(/datum/job_department/science in departments)
		return /datum/outfit/quarian/violet
	if(/datum/job_department/cargo in departments)
		return /datum/outfit/quarian/yellow
	if(/datum/job_department/service in departments)
		return /datum/outfit/quarian/green
	if(/datum/job_department/command in departments)
		return /datum/outfit/quarian/blue

	return /datum/outfit/quarian
