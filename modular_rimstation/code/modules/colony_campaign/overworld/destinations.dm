/**
 * The places an expedition physically stands in, and the one path that brings them into being.
 *
 * Every scene out here is a lazy template: it does not exist until somebody walks to it, and once loaded it is
 * kept until the server reboots. Releasing a scene mid-round is deliberately not attempted - players will have
 * built, dropped and broken things in it, and tearing down a reservation somebody is standing in is a far worse
 * failure than holding a few hundred turfs longer than strictly necessary. The region caps how many sites can
 * exist, so the memory is bounded by design rather than by cleanup.
 *
 * The loader validates before it calls the inherited one, because the inherited one does not fail politely: a
 * missing file, an unparseable map or an exhausted reservation pool all CRASH. Nothing here can prevent the
 * last of those, so the rule is that the party stays where it was until a load has actually returned.
 */

/// Where a party member appears in the travelling camp.
/obj/effect/landmark/rimstation_caravan_spawn
	name = "caravan camp spawn"

/// Where a party arrives at a site, and where it stands to leave again.
/obj/effect/landmark/rimstation_expedition_arrival
	name = "expedition arrival point"

/// Where a returning party is put down in the colony, if the map offers somewhere.
/obj/effect/landmark/rimstation_caravan_return
	name = "caravan return point"

/datum/lazy_template/rimstation_caravan_transit
	key = LAZY_TEMPLATE_KEY_RIMSTATION_TRANSIT
	map_name = "rimstation_caravan_transit"

/datum/lazy_template/rimstation_resource_site
	key = LAZY_TEMPLATE_KEY_RIMSTATION_RESOURCE_SITE
	map_name = "rimstation_resource_site"


/**
 * One loaded scene, and what was found in it.
 *
 * Runtime only. None of this is persisted: a reservation is a fact about this boot, and writing one into the
 * campaign record would have the next boot believing in turfs nobody reserved.
 */
/datum/overworld_destination
	/// The site this scene is for, or null for the shared travelling camp.
	var/site_id
	/// The template key it was built from.
	var/template_key
	/// The reservation holding it. Kept so the turfs are not handed back out from under people.
	var/datum/turf_reservation/reservation
	/// Turfs somebody arriving should be put on, in map order.
	var/list/arrival_turfs
	/// The deposit or objective in this scene, if it has one.
	var/datum/weakref/objective_ref

/datum/overworld_destination/New(site_id, template_key)
	. = ..()
	src.site_id = site_id
	src.template_key = template_key
	arrival_turfs = list()

/datum/overworld_destination/Destroy(force)
	// The reservation is deliberately not released; see the file comment. Dropping the reference is enough.
	reservation = null
	arrival_turfs = null
	objective_ref = null
	return ..()

/// Somewhere in this scene to put a body, or null if the map offered nowhere.
/datum/overworld_destination/proc/pick_arrival_turf()
	RETURN_TYPE(/turf)
	for(var/turf/candidate as anything in arrival_turfs)
		if(candidate && !isclosedturf(candidate))
			return candidate
	return null


/// Every scene loaded this boot, by site id. The travelling camp is held under its own key.
GLOBAL_LIST_EMPTY(rimstation_overworld_destinations)

/// The key the shared travelling camp is filed under. Not a site, so it cannot collide with one.
#define OVERWORLD_TRANSIT_DESTINATION_KEY "transit"

/// The camp the party travels in, if it has been loaded this boot.
/proc/get_caravan_transit()
	RETURN_TYPE(/datum/overworld_destination)
	return GLOB.rimstation_overworld_destinations[OVERWORLD_TRANSIT_DESTINATION_KEY]

/// The loaded scene for one site, if it has been loaded this boot.
/proc/get_loaded_destination(site_id)
	RETURN_TYPE(/datum/overworld_destination)
	return GLOB.rimstation_overworld_destinations[site_id]

/**
 * Why this template cannot be loaded, or null if it can.
 *
 * Checked before the inherited loader is called, because that one crashes rather than returning. An unknown
 * key or a missing file is a content mistake somebody can fix, and it should read as one rather than as a
 * runtime in the middle of somebody's expedition.
 */
/proc/overworld_template_problem(template_key)
	if(!istext(template_key) || !template_key)
		return "no template was named"

	var/datum/lazy_template/template = GLOB.lazy_templates[template_key]
	if(!template)
		return "there is no template registered under '[template_key]'"

	var/load_path = "[template.map_dir]/[template.map_name].dmm"
	if(!fexists(load_path))
		return "the template file '[load_path]' is missing"

	return null

/**
 * Brings a scene into being and binds what was found in it. Returns the destination, or null.
 *
 * Sleeps - the inherited loader parses a map and reserves turfs - so this must be reached from somewhere that
 * is allowed to. Everything that calls it does so through INVOKE_ASYNC and revalidates afterwards, because a
 * great deal can change in the seconds a load takes.
 */
/proc/load_overworld_destination(site_id, template_key)
	RETURN_TYPE(/datum/overworld_destination)
	var/registry_key = site_id || OVERWORLD_TRANSIT_DESTINATION_KEY

	// Already standing; loading it twice would strand whoever is in the first copy.
	var/datum/overworld_destination/existing = GLOB.rimstation_overworld_destinations[registry_key]
	if(existing)
		return existing

	var/problem = overworld_template_problem(template_key)
	if(problem)
		log_game("Overworld destination '[registry_key]' could not be loaded: [problem].")
		message_admins(span_boldwarning("An expedition destination could not be loaded: [problem]. This is a content problem, not a player one."))
		return null

	var/datum/overworld_destination/destination = new(site_id, template_key)
	if(!destination.load_scene())
		qdel(destination)
		return null

	GLOB.rimstation_overworld_destinations[registry_key] = destination
	log_game("Overworld destination '[registry_key]' loaded from '[template_key]' with [length(destination.arrival_turfs)] arrival points.")
	return destination

/**
 * Reserves the turfs and fills this destination in. Returns TRUE if it now describes a real place.
 *
 * The destination does its own loading so that it can be the thing listening for the load: the signal has to
 * be caught by a datum, and this is the datum that wants what the signal carries.
 *
 * `lazy_load()` is called directly rather than through SSmapping.lazy_load_template(), which caches one
 * reservation per key and would hand the second deposit the first one's turfs. Each site needs its own copy of
 * the same scene, so each gets its own load.
 */
/datum/overworld_destination/proc/load_scene()
	var/datum/lazy_template/template = GLOB.lazy_templates[template_key]
	if(!template)
		return FALSE

	// Registered before the load, because the signal fires from inside it.
	RegisterSignal(template, COMSIG_LAZY_TEMPLATE_LOADED, PROC_REF(on_scene_loaded))
	reservation = template.lazy_load()
	UnregisterSignal(template, COMSIG_LAZY_TEMPLATE_LOADED)

	if(!reservation)
		log_game("Overworld destination '[site_id || OVERWORLD_TRANSIT_DESTINATION_KEY]' reserved no turfs.")
		return FALSE
	return TRUE

/**
 * Picks the landmarks out of a freshly loaded scene.
 *
 * Runs inside the load, which is the only moment the full list of what was placed is available - walking the
 * turfs afterwards would also find anything players later dragged in.
 */
/datum/overworld_destination/proc/on_scene_loaded(datum/source, list/atoms, list/turfs, list/areas)
	SIGNAL_HANDLER
	for(var/atom/movable/thing as anything in atoms)
		if(istype(thing, /obj/effect/landmark/rimstation_caravan_spawn) || istype(thing, /obj/effect/landmark/rimstation_expedition_arrival))
			var/turf/spot = get_turf(thing)
			if(spot)
				arrival_turfs += spot
			continue

		if(istype(thing, /obj/structure/rimstation_resource_deposit))
			var/obj/structure/rimstation_resource_deposit/deposit = thing
			// One deposit per scene. A second would be a second payout for one journey, so the first wins and
			// the rest are left inert rather than quietly doubling what the site is worth.
			if(objective_ref)
				deposit.set_inert("this site already has a deposit bound to it")
				continue
			objective_ref = WEAKREF(deposit)
			deposit.bind_to_site(site_id)

/**
 * A worked deposit at a resource site.
 *
 * Pays once, and the campaign record is what says so - not this object. The two are not interchangeable: the
 * structure lives in a reservation that survives until reboot, so a second chapter walking back into the same
 * loaded scene would find it standing there ready to be worked again. The site state in the overworld record
 * is the thing that outlives the scene, so that is the guard, and the local flag only stops the button
 * flickering between somebody clicking and the campaign answering.
 */
/obj/structure/rimstation_resource_deposit
	name = "mineral deposit"
	desc = "A seam of ore breaking the surface. Workable with what a caravan carries."
	icon = 'icons/obj/mining_zones/terrain.dmi'
	icon_state = "ore_vent"
	anchored = TRUE
	density = TRUE
	max_integrity = 300
	resistance_flags = FIRE_PROOF | LAVA_PROOF | UNACIDABLE | ACID_PROOF
	/// The generated site this stands for. Null until the loader binds it.
	var/site_id
	/// What working it pays, taken from the generated site rather than invented here.
	var/deposit_yield = 0
	/// Set once this has paid out or been ruled out, so it stops offering.
	var/worked = FALSE
	/// Why it is inert, shown on examine so a confused player gets an answer rather than a dead object.
	var/inert_reason

/obj/structure/rimstation_resource_deposit/examine(mob/user)
	. = ..()
	if(inert_reason)
		. += span_warning("It has nothing more to give: [inert_reason]")
		return
	if(!site_id)
		. += span_warning("This seam is not part of any surveyed deposit. It cannot be worked.")
		return
	. += span_notice("Roughly [deposit_yield] units of ore. Work it to carry the lot back to the colony.")

/// Ties this seam to a generated site, taking its worth from the region rather than making one up.
/obj/structure/rimstation_resource_deposit/proc/bind_to_site(bound_site_id)
	if(!bound_site_id)
		set_inert("it belongs to no surveyed site")
		return FALSE

	var/datum/overworld_region/region = get_active_overworld_region()
	var/datum/overworld_site/site = region?.sites[bound_site_id]
	if(!site)
		set_inert("the survey that found it no longer describes this region")
		return FALSE

	site_id = bound_site_id
	deposit_yield = site.yield

	// A site the colony already emptied stays empty, even if the scene is being walked into again.
	var/datum/overworld_state/region_state = SScampaign.get_overworld_state()
	if(region_state && region_state.get_site_state(site_id) != OVERWORLD_SITE_STATE_AVAILABLE)
		set_inert("the colony has already stripped this seam")
		return FALSE

	return TRUE

/// Stops this deposit offering anything, for a reason a player can read.
/obj/structure/rimstation_resource_deposit/proc/set_inert(reason)
	worked = TRUE
	inert_reason = reason
	update_appearance()

/obj/structure/rimstation_resource_deposit/attack_hand(mob/living/user, list/modifiers)
	. = ..()
	if(.)
		return
	return work_deposit(user)

/**
 * Works the seam, once.
 *
 * The campaign is asked to change the site's state first, and only a state change that this call caused pays
 * out. Two colonists clicking together, or one clicking twice through the do_after, both arrive here - and the
 * record answering "already depleted" is what makes the second one cost nothing.
 */
/obj/structure/rimstation_resource_deposit/proc/work_deposit(mob/living/user)
	if(worked)
		to_chat(user, span_warning("[src] has nothing more to give."))
		return TRUE
	if(!site_id)
		to_chat(user, span_warning("[src] is not part of any surveyed deposit."))
		return TRUE

	to_chat(user, span_notice("You start working [src] loose..."))
	if(!do_after(user, OVERWORLD_SITE_WORK_SECONDS SECONDS, src))
		return TRUE
	// Rechecked after the wait: somebody else may have finished it while this one was digging.
	if(worked)
		return TRUE

	var/datum/overworld_region/region = get_active_overworld_region()
	var/datum/overworld_state/region_state = SScampaign.get_overworld_state()
	if(!region || !region_state)
		to_chat(user, span_warning("There is no campaign here to carry this back to."))
		return TRUE

	if(region_state.get_site_state(site_id) != OVERWORLD_SITE_STATE_AVAILABLE)
		set_inert("the colony has already stripped this seam")
		to_chat(user, span_warning("[src] has already been stripped."))
		return TRUE

	if(!region_state.set_site_state(region, site_id, OVERWORLD_SITE_STATE_DEPLETED, "worked by an expedition"))
		to_chat(user, span_warning("[src] could not be recorded as worked. Nothing was taken."))
		return TRUE

	// Marked inert before the payout, so nothing can re-enter between the record changing and the ore landing.
	set_inert("an expedition stripped it")

	// Real ore on the ground rather than a number in a ledger.
	//
	// The same rule the larder taught and that raid theft already runs on: what the colony has is what it can
	// carry home. A party killed on the road loses the ore with them, which is what makes the journey back
	// worth anything. The ledger entry beside it is the account of the work, not a second pile of iron.
	drop_deposit_ore(get_turf(src), deposit_yield)
	SScampaign.record_nonfinancial(
		LEDGER_CATEGORY_EXPEDITION,
		"site_worked",
		actor_id = SScampaign.get_colonist_record_for_body(user)?.colonist_id,
		related_id = site_id,
	)
	SScampaign.sync_overworld()
	SScampaign.refresh_overworld_consoles()

	visible_message(span_notice("[user] works [deposit_yield] units of ore out of [src]."))
	log_game("Colony expedition: [key_name(user)] worked site [site_id] for [deposit_yield] [OVERWORLD_SITE_RESOURCE_ID].")
	return TRUE


/**
 * Puts a deposit's worth of ore on the ground, in stacks a person can actually pick up.
 *
 * Split across stacks rather than dumped as one, because a stack is capped and a yield can exceed that cap.
 * Spread over neighbouring tiles for the same reason a raid does not stack its loot on one square: a pile
 * nobody can walk onto is a pile nobody can carry home.
 */
/proc/drop_deposit_ore(turf/where, units)
	if(!where || !isnum(units) || units <= 0)
		return 0

	var/obj/item/stack/ore/iron/reference = /obj/item/stack/ore/iron
	var/per_stack = initial(reference.max_amount) || 50
	var/list/spots = list(where)
	for(var/direction in GLOB.cardinals)
		var/turf/neighbour = get_step(where, direction)
		if(neighbour && !isclosedturf(neighbour))
			spots += neighbour

	var/dropped = 0
	var/index = 1
	while(dropped < units)
		var/this_stack = min(per_stack, units - dropped)
		new /obj/item/stack/ore/iron(spots[index], this_stack)
		dropped += this_stack
		// Wraps rather than running out of tiles: a very rich seam piles up rather than vanishing.
		index = (index % length(spots)) + 1

	return dropped
