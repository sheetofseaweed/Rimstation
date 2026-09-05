/datum/job
	/// TRUE for a job on a colony's roster rather than a station's. Decides which half map_check() hides.
	var/colony_role = FALSE

/**
 * The role nearly everyone in a colony holds.
 *
 * A settlement is not a station: there is no department to belong to, nobody to report to, and no rank to hold.
 * Everything that separates one colonist from another - what they can do, where they sleep, what the colony
 * remembers of them - lives in their record rather than in a job title. See /datum/job/colony_leader for the
 * single exception, which exists because a communications console asks for a card and not for a person.
 *
 * Unavailable by default. The map that wants colonists says so in its own config, which is also what tells
 * every other job to stand down; see is_colonist_only_map().
 */
/datum/job/colonist
	title = JOB_COLONIST
	description = "Survive on the frontier. Build the colony, feed it, and be standing when something comes for it."
	faction = FACTION_STATION
	total_positions = 0
	spawn_positions = 0
	supervisors = "nobody. A colony decides together."
	exp_granted_type = EXP_TYPE_CREW
	outfit = /datum/outfit/job/colonist
	plasmaman_outfit = /datum/outfit/plasmaman
	paycheck = PAYCHECK_LOWER
	paycheck_department = ACCOUNT_CIV
	display_order = JOB_DISPLAY_ORDER_ASSISTANT
	department_for_prefs = /datum/job_department/assistant
	job_flags = STATION_JOB_FLAGS
	config_tag = "COLONIST"
	colony_role = TRUE

/**
 * Puts the arriving player into the colony's roster and onto the right piece of ground.
 *
 * Done here rather than at spawn-point selection because get_roundstart_spawn_point() is asked of the job with
 * no idea who is spawning, and which colonist this is decides where they belong.
 */
/datum/job/colonist/after_spawn(mob/living/spawned, client/player_client)
	. = ..()
	if(!ishuman(spawned) || !player_client)
		return
	settle_colonist(spawned, player_client.ckey)

/// Built on the planet rather than on the hub the rest of the fork latejoins to. Falls back if unplaced.
/datum/job/colonist/get_latejoin_spawn_point()
	var/atom/colony_arrival = get_colony_latejoin_spawn_point()
	return colony_arrival || ..()


/datum/outfit/job/colonist
	name = JOB_COLONIST
	jobtype = /datum/job/colonist
	// The assistant trim, because a colonist needs an account to trade with and nothing more; a settlement has
	// no access levels of its own to hand out.
	id_trim = /datum/id_trim/job/assistant
	uniform = /obj/item/clothing/under/color/grey
	shoes = /obj/item/clothing/shoes/workboots
	back = /obj/item/storage/backpack

/**
 * TRUE when the loaded map hands out the colonist job.
 *
 * A map declares itself a colony by granting Colonist positions in its own `job_changes`, which is the same
 * supported config channel every other map uses to change its roster. Read as a signal rather than matching on
 * a map name, so a second colony map inherits the behaviour by declaring the same thing.
 */
/proc/is_colonist_only_map()
	var/granted = CHECK_MAP_JOB_CHANGE(JOB_COLONIST, "total_positions")
	return isnum(granted) && granted != 0

/**
 * Says out loud when a campaign is running on a map that is not offering the colonist job.
 *
 * The failure this exists for is silent and confusing: the roster is decided from `SSmapping.current_map`,
 * which on an ordinary boot is read from `data/next_map.json` - a *copy* of a map config taken when the map
 * was last selected, not the file in `_maps/`. Edit the map's config and the running server keeps using the
 * older copy until something rewrites it, so the colony quietly comes up with the full station roster and
 * nothing anywhere says why.
 */
/datum/controller/subsystem/campaign/proc/warn_if_map_is_not_a_colony()
	if(is_colonist_only_map())
		return FALSE

	var/complaint = "Campaign [manifest?.campaign_id] is running on map config '[SSmapping.current_map?.map_name]', which does not grant the [JOB_COLONIST] job. \
		Players will see the station roster instead of the colony. If this map is meant to be a colony, copy its config from _maps/ over data/next_map.json and restart."
	log_game(complaint)
	message_admins(span_boldwarning(complaint))
	return TRUE
