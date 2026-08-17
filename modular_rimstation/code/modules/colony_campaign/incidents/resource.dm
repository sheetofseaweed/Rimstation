/**
 * A blight in the crop the colony is living on.
 *
 * Hydroponics already models this: `pestlevel` climbs, the plant suffers, and someone with the right tool can
 * bring it back down. The incident sets the infestation going and then asks whether the colony wants to spend
 * on treating it, which is a real choice - the cheap answer is to let the crop die and eat the stores instead.
 *
 * The decision is answerable at the core as well as a console, because it is the settlement's own business
 * rather than a call from outside.
 */
/datum/colony_incident/blight
	name = "crop blight"
	category = COLONY_INCIDENT_CATEGORY_RESOURCE
	tags = list(INCIDENT_TAG_HARVEST)
	warning_duration = 45 SECONDS
	answer_sources = INCIDENT_ANSWER_CONSOLE | INCIDENT_ANSWER_COLONY_CORE
	/// What treating it costs the settlement.
	var/treatment_cost = 200
	/// The trays that took the blight.
	var/list/blighted_trays
	/// Set once the colony pays to deal with it.
	var/treated = FALSE

/datum/colony_incident/blight/can_begin()
	if(!..())
		return FALSE
	return length(find_growing_trays()) > 0

/// Hydroponics trays with something actually growing in them.
/datum/colony_incident/blight/proc/find_growing_trays()
	RETURN_TYPE(/list)
	var/list/growing = list()
	for(var/obj/machinery/hydroponics/tray as anything in SSmachines.get_machines_by_type_and_subtypes(/obj/machinery/hydroponics))
		if(tray.myseed && !QDELETED(tray))
			growing += tray
	return growing

/datum/colony_incident/blight/select_target()
	blighted_trays = find_growing_trays()
	return length(blighted_trays) > 0

/datum/colony_incident/blight/announce_warning()
	priority_announce("Something is spreading through the settlement's crop. It will take hold shortly.", "Colony Agricultural Advisory")
	return TRUE

/datum/colony_incident/blight/execute()
	if(!length(blighted_trays))
		select_target()
	if(!length(blighted_trays))
		resolve(COLONY_INCIDENT_OUTCOME_IGNORED)
		return FALSE

	// The infestation is real whether or not anyone pays: this is what the colony is deciding about.
	for(var/obj/machinery/hydroponics/tray as anything in blighted_trays)
		if(QDELETED(tray))
			continue
		tray.adjust_pestlevel(5)

	var/content = "A blight has taken hold in [length(blighted_trays)] of the settlement's growing trays.<br><br>\
		Treating it means buying in what is needed: [treatment_cost] credits.<br><br>\
		Left alone it will run its course, and the crop with it."

	if(!ask_colony("Crop Blight", content, list("Pay for treatment.", "Let it run its course."), PROC_REF(on_answered)))
		resolve(COLONY_INCIDENT_OUTCOME_IGNORED, 1)
		return FALSE
	return TRUE

/// Index 1 treats the blight, index 2 lets it run.
/datum/colony_incident/blight/proc/on_answered(index)
	if(index != 1)
		priority_announce("The blight has been left to run its course.", "Colony Agricultural Advisory")
		resolve(COLONY_INCIDENT_OUTCOME_FAILED, 2)
		return

	if(!SScampaign.try_debit(treatment_cost, LEDGER_CATEGORY_UPKEEP, "crop blight treatment", null, id))
		priority_announce("There is nothing in the account to treat it with.", "Colony Agricultural Advisory")
		resolve(COLONY_INCIDENT_OUTCOME_FAILED, 2)
		return

	treated = TRUE
	for(var/obj/machinery/hydroponics/tray as anything in blighted_trays)
		if(QDELETED(tray))
			continue
		tray.adjust_pestlevel(-10)

	priority_announce("The blight has been treated. The crop should recover.", "Colony Agricultural Advisory")
	resolve(COLONY_INCIDENT_OUTCOME_SUCCEEDED, -1)

/datum/colony_incident/blight/build_result(datum/colony_incident_result/building)
	building.record_telemetry("blighted_trays", length(blighted_trays))
	building.record_telemetry("treated", treated)

	if(treated)
		building.add_consequence("the settlement paid to save its crop")
		building.add_reward("the harvest survived")
	else
		building.add_consequence("a blight was left to run through the crop")
	return TRUE

/datum/colony_incident/blight/Destroy(force)
	blighted_trays = null
	return ..()
