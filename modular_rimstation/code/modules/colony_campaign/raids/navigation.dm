/**
 * Route maps for one raid: an upstream path map per destination, built with the same passability rules as JPS.
 * A build costs ~0.6 s CPU on the colony map, so it runs in capped slices; SSpathfinder would stall other mobs.
 */
/datum/colony_raid_navigator
	/// Passability for every map. Taken from the raider type, because the first map is needed before any raider exists.
	var/datum/can_pass_info/pass_info
	/// Finished maps keyed by destination turf.
	var/list/maps
	/// When each finished map was requested, keyed by destination turf. A map shows the world as it was then.
	var/list/requested_at
	/// Builds in progress keyed by destination turf, oldest first.
	var/list/builds
	/// Maps finished over the raid's life, for the admin readout.
	var/maps_built = 0

/datum/colony_raid_navigator/New()
	. = ..()
	var/mob/living/basic/trooper/pirate/melee/rimstation_raider/raider_type = /mob/living/basic/trooper/pirate/melee/rimstation_raider
	pass_info = new(null, list())
	pass_info.is_living = TRUE
	pass_info.mob_size = initial(raider_type.mob_size)
	pass_info.pass_flags = initial(raider_type.pass_flags)
	pass_info.movement_type = initial(raider_type.movement_type)

/datum/colony_raid_navigator/Destroy(force)
	STOP_PROCESSING(SSfastprocess, src)
	var/list/unfinished = builds
	builds = null
	for(var/turf/goal as anything in unfinished)
		qdel(unfinished[goal])
	maps = null
	requested_at = null
	pass_info = null
	return ..()

/// TRUE once a finished map toward `goal` exists, however old.
/datum/colony_raid_navigator/proc/has_map(turf/goal)
	return !isnull(maps?[goal])

/// TRUE when a map toward `goal` exists and is recent enough to trust a missing route on it.
/datum/colony_raid_navigator/proc/is_fresh(turf/goal)
	return has_map(goal) && world.time - requested_at[goal] < COLONY_RAID_NAVIGATION_REFRESH_DELAY

/// TRUE when the current map toward `goal` has a route from `from`.
/datum/colony_raid_navigator/proc/is_reachable(turf/from, turf/goal)
	var/datum/path_map/flow = maps?[goal]
	return !!flow?.next_closest[from]

/// Queues a fresh map toward `goal`. The old map stays in use until the new one is finished.
/datum/colony_raid_navigator/proc/request(turf/goal)
	if(!goal || builds?[goal])
		return FALSE
	var/datum/pathfind/sssp/build = new()
	var/list/on_finish = list(CALLBACK(src, PROC_REF(on_map_built), goal, world.time))
	build.setup_from_canpass(pass_info, goal, COLONY_RAID_NAVIGATION_RANGE, TRUE, null, on_finish)
	if(!build.start())
		qdel(build)
		return FALSE
	LAZYSET(builds, goal, build)
	START_PROCESSING(SSfastprocess, src)
	return TRUE

/// Queues a fresh map toward `goal` if the current one is old enough to doubt. Called when a raider gets stuck.
/datum/colony_raid_navigator/proc/refresh(turf/goal)
	if(world.time - requested_at?[goal] < COLONY_RAID_NAVIGATION_REFRESH_DELAY)
		return FALSE
	return request(goal)

/// The map toward `goal`, finishing its build first if there is one. Sleeps between slices.
/datum/colony_raid_navigator/proc/get_map_now(turf/goal)
	RETURN_TYPE(/datum/path_map)
	if(!builds?[goal] && (has_map(goal) || !request(goal)))
		return maps?[goal]
	var/datum/pathfind/sssp/build = builds[goal]
	while(!QDELETED(build) && !advance(build, 100))
		stoplag()
	return maps?[goal]

/datum/colony_raid_navigator/process(seconds_per_tick)
	if(!length(builds))
		return PROCESS_KILL
	advance(builds[builds[1]], COLONY_RAID_NAVIGATION_TICK_SHARE)

/// Runs one slice of `build` within `share` percent of this tick, like MC_SPLIT_TICK. TRUE once the build has ended.
/datum/colony_raid_navigator/proc/advance(datum/pathfind/sssp/build, share)
	var/tick_limit = Master.current_ticklimit
	Master.current_ticklimit = min(tick_limit, TICK_USAGE + share)
	var/stable = build.search_step()
	Master.current_ticklimit = tick_limit
	if(!stable)
		build.early_exit()
		return TRUE
	if(build.working_index < length(build.working_queue))
		return FALSE
	build.finished()
	return TRUE

/// Stores a finished map. Also called with null when a build is abandoned.
/datum/colony_raid_navigator/proc/on_map_built(turf/goal, request_time, datum/path_map/built)
	LAZYREMOVE(builds, goal)
	if(!istype(built))
		return
	LAZYSET(maps, goal, built)
	LAZYSET(requested_at, goal, request_time)
	maps_built++

/**
 * Where an attacker at `from` should walk next toward `goal`: one waypoint spacing ahead, or the goal once it is that close.
 * Null when there is no map toward the goal yet, or the map has no route from `from`.
 */
/datum/colony_raid_navigator/proc/next_leg(turf/from, turf/goal)
	if(from == goal)
		return goal
	if(!is_reachable(from, goal))
		return null
	var/datum/path_map/flow = maps[goal]
	// Drops the raider's own tile and the goal tile, which is usually dense.
	var/list/turf/steps = flow.get_path_from(from, TRUE, 1)
	if(length(steps) <= COLONY_RAID_WAYPOINT_SPACING)
		return goal
	return steps[COLONY_RAID_WAYPOINT_SPACING]
