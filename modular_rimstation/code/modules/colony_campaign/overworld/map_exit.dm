/// Where a caravan can leave the colony from, and the map a colonist opens there.

/// A mapped way out that is not the border of the map. Any turf within one tile of it counts.
/obj/effect/landmark/rimstation_caravan_exit
	name = "caravan way out"

GLOBAL_LIST_EMPTY(caravan_exit_markers)

/obj/effect/landmark/rimstation_caravan_exit/Initialize(mapload)
	. = ..()
	GLOB.caravan_exit_markers += src

/obj/effect/landmark/rimstation_caravan_exit/Destroy()
	GLOB.caravan_exit_markers -= src
	return ..()

/// TRUE when a caravan can leave from this turf: the border of the colony surface, or a mapped way out.
/proc/is_caravan_exit_turf(turf/where)
	if(!where)
		return FALSE
	for(var/obj/effect/landmark/rimstation_caravan_exit/marker as anything in GLOB.caravan_exit_markers)
		if(marker.z == where.z && get_dist(marker, where) <= 1)
			return TRUE
	if(!istype(where.loc, /area/rimstation_colony/surface))
		return FALSE

	var/depth = OVERWORLD_EXIT_EDGE_DEPTH
	return where.x <= depth || where.y <= depth || where.x > world.maxx - depth || where.y > world.maxy - depth

/// Opens the map for a colonist at a way out, and signs them on to the expedition that musters there.
/proc/muster_at_exit(mob/living/user)
	var/datum/colonist_record/traveller = SScampaign.get_colonist_record_for_body(user)
	var/datum/overworld_party/party = SScampaign.get_active_party()
	if(traveller && !party)
		party = SScampaign.form_party()
	if(traveller && party?.is_planning() && party.add_member(traveller.colonist_id))
		party.log_membership(traveller, "signed on")
		SScampaign.commit_party_change()
	get_personal_overworld_map().ui_interact(user)

/// Shown while a colonist stands where a caravan can leave from. Clicking it starts the muster.
/atom/movable/screen/alert/caravan_exit
	name = "Way Out"
	desc = "A caravan can leave the colony from here. Click to sign on and open the expedition map."
	clickable_glow = TRUE

/atom/movable/screen/alert/caravan_exit/Initialize(mapload, datum/hud/hud_owner)
	. = ..()
	add_overlay(mutable_appearance('modular_rimstation/icons/obj/structures/caravan.dmi', "hitching_post_ready"))

/atom/movable/screen/alert/caravan_exit/Click(location, control, params)
	. = ..()
	if(!.)
		return
	muster_at_exit(owner)

/// The regional map every colonist carries. It opens anywhere.
/datum/action/colony_expedition_map
	name = "Expedition Map"
	desc = "Look at the country around the colony, and plan or direct an expedition."
	button_icon = 'modular_rimstation/icons/obj/structures/caravan.dmi'
	button_icon_state = "hitching_post"
	check_flags = AB_CHECK_CONSCIOUS

/datum/action/colony_expedition_map/Trigger(mob/clicker, trigger_flags)
	. = ..()
	if(!.)
		return FALSE
	get_personal_overworld_map().ui_interact(owner)
	return TRUE
