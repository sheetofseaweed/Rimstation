#define INFINITE_AUTOSAVES -1
#define SAVE_COMPLETION_MARKER "save_complete.txt"
#define PERSISTENT_SAVE_SCHEMA_VERSION 1

SUBSYSTEM_DEF(world_save)
	name = "World Save"
	dependencies = list(
		/datum/controller/subsystem/persistence,
		/datum/controller/subsystem/mapping,
		/datum/controller/subsystem/atoms,
		/datum/controller/subsystem/machines,
		/datum/controller/subsystem/shuttle,
	)
	flags = SS_BACKGROUND
	wait = INFINITY
	runlevels = RUNLEVEL_GAME

	/// This is used to skip the 1st autosave that is automatically done vis the subsystems fire() at roundstart
	var/was_first_roundstart_autosave_skipped = FALSE
	/// A list of map config jsons used by persistence organized by z-level traits
	var/list/map_configs_cache
	/// Tracking variables for save metrics
	var/list/current_save_metrics = list()
	/// Aggregated serializer diagnostics for the current or most recent save attempt
	var/list/current_save_diagnostics = list()
	/// Current z-level being saved
	var/current_save_z_level = 0
	/// Current x coordinate being processed
	var/current_save_x = 0
	/// Current y coordinate being processed
	var/current_save_y = 0
	/// Current save directory path while a save is active
	var/current_save_directory
	/// Whether a save operation is currently in progress
	var/save_in_progress = FALSE
	/// Whether the current save should stop at the next safe checkpoint
	var/save_cancel_requested = FALSE
	/// Areas that have been counted
	var/list/counted_areas = list()

/datum/controller/subsystem/world_save/Initialize()
	if(CONFIG_GET(number/persistent_autosave_period) > 0 && CONFIG_GET(flag/persistent_save_enabled))
		wait = CONFIG_GET(number/persistent_autosave_period) HOURS

	for(var/obj/child in GLOB.save_containers_children)
		var/parent_id = child.save_container_child_id
		child.forceMove(GLOB.save_containers_parents[parent_id])
		child.save_container_child_id = null

	for(var/parent_id in GLOB.save_containers_parents)
		var/obj/parent = GLOB.save_containers_parents[parent_id]
		parent.update_appearance()
		parent.save_container_parent_id = null

	if(SSatoms.world_save_loaders.len)
		if(CONFIG_GET(flag/persistent_save_enabled))
			for(var/I in 1 to SSatoms.world_save_loaders.len)
				CHECK_TICK
				var/atom/A = SSatoms.world_save_loaders[I]
				//I hate that we need this
				if(QDELETED(A))
					continue
				A.PersistentInitialize()
			testing("Persistent initialized [SSatoms.world_save_loaders.len] atoms")
		SSatoms.world_save_loaders.Cut()

	GLOB.save_containers_parents.Cut()
	GLOB.save_containers_children.Cut()

	return SS_INIT_SUCCESS

/datum/controller/subsystem/world_save/fire(resumed = FALSE)
	if(!was_first_roundstart_autosave_skipped) // prevents pointless autosave at the start of the game
		was_first_roundstart_autosave_skipped = TRUE
		return

	save_world()

/// Saves map z-levels in the world based on PERSISTENT_SAVE_ENABLED config options in config/persistence.txt
/datum/controller/subsystem/world_save/proc/save_world(list/z_levels, silent=FALSE)
	if(save_in_progress)
		log_world("World map save skipped at [time_stamp()] because another save is already in progress")
		return FALSE

	log_world("World map save initiated at [time_stamp()]")
	if(!silent)
		to_chat(world, span_boldannounce("World map save initiated at [time_stamp()]"))

	var/save_succeeded = save_persistent_maps(z_levels, silent)
	if(save_succeeded)
		prune_old_autosaves()
	return save_succeeded

/datum/controller/subsystem/world_save/proc/request_save_cancel(reason = "manual request")
	if(!save_in_progress)
		return FALSE

	save_cancel_requested = TRUE
	log_world("World map save cancellation requested at [time_stamp()] ([reason])")
	return TRUE

/datum/controller/subsystem/world_save/proc/should_cancel_save()
	return save_cancel_requested

/datum/controller/subsystem/world_save/proc/reset_current_save_diagnostics()
	current_save_diagnostics = list(
		"skip_reasons" = list(),
		"skip_types" = list(),
		"failure_reasons" = list(),
		"failure_types" = list(),
		"failure_messages" = list(),
	)

/datum/controller/subsystem/world_save/proc/increment_save_diagnostic(list/target_list, key)
	if(!istext(key) || !length(key))
		key = "unknown"
	target_list[key] = (target_list[key] || 0) + 1

/datum/controller/subsystem/world_save/proc/get_save_subject_key(subject)
	if(isnull(subject))
		return "global"
	if(ispath(subject))
		return "[subject]"
	if(isatom(subject))
		var/atom/subject_atom = subject
		return "[subject_atom.type]"
	return "[subject]"

/datum/controller/subsystem/world_save/proc/clone_current_save_diagnostics()
	if(!islist(current_save_diagnostics))
		return list()

	var/list/cloned_diagnostics = list()
	for(var/key in current_save_diagnostics)
		var/value = current_save_diagnostics[key]
		if(islist(value))
			var/list/value_list = value
			cloned_diagnostics[key] = value_list.Copy()
		else
			cloned_diagnostics[key] = value
	return cloned_diagnostics

/datum/controller/subsystem/world_save/proc/record_serialization_skip(reason, subject)
	if(!islist(current_save_diagnostics))
		reset_current_save_diagnostics()

	increment_save_diagnostic(current_save_diagnostics["skip_reasons"], reason)
	increment_save_diagnostic(current_save_diagnostics["skip_types"], get_save_subject_key(subject))

/datum/controller/subsystem/world_save/proc/record_serialization_failure(reason, subject=null, details=null)
	if(!islist(current_save_diagnostics))
		reset_current_save_diagnostics()

	increment_save_diagnostic(current_save_diagnostics["failure_reasons"], reason)
	increment_save_diagnostic(current_save_diagnostics["failure_types"], get_save_subject_key(subject))

	if(isnull(details))
		return

	var/list/failure_messages = current_save_diagnostics["failure_messages"]
	if(failure_messages.len >= 20)
		return
	failure_messages += "[reason]: [details]"

/datum/controller/subsystem/world_save/proc/reset_active_save_state()
	save_in_progress = FALSE
	save_cancel_requested = FALSE
	current_save_directory = null
	current_save_z_level = 0
	current_save_x = 0
	current_save_y = 0
	counted_areas = list()

/datum/controller/subsystem/world_save/proc/abort_current_save(reason, silent=FALSE)
	var/map_save_directory = current_save_directory
	reset_active_save_state()

	if(map_save_directory && fexists(map_save_directory))
		fdel(map_save_directory)

	log_world("World map save aborted at [time_stamp()]: [reason]")
	if(!silent)
		to_chat(world, span_boldannounce("World map save aborted at [time_stamp()] ([reason])"))
	return FALSE

/datum/controller/subsystem/world_save/proc/finish_current_save(silent=FALSE)
	reset_active_save_state()
	if(!silent)
		to_chat(world, span_boldannounce("World map save finished at [time_stamp()]"))
	log_world("World map save finished at [time_stamp()]")
	return TRUE

/datum/controller/subsystem/world_save/proc/get_save_directory_key(save_directory_name)
	return replacetext("[save_directory_name]", "/", "")

/datum/controller/subsystem/world_save/proc/get_save_directory_path(save_directory_name)
	return "[MAP_PERSISTENT_DIRECTORY][get_save_directory_key(save_directory_name)]"

/datum/controller/subsystem/world_save/proc/read_save_completion_data(save_directory_name)
	var/completion_marker_path = "[get_save_directory_path(save_directory_name)]/[SAVE_COMPLETION_MARKER]"
	if(!fexists(completion_marker_path))
		return null

	var/raw_completion_data = file2text(file(completion_marker_path))
	if(!raw_completion_data)
		return null

	var/list/completion_data = json_decode(raw_completion_data)
	if(!islist(completion_data))
		return null

	return completion_data

/datum/controller/subsystem/world_save/proc/get_saved_z_level_entries(save_directory_name, list/completion_data = null)
	var/list/saved_z_levels = completion_data?["saved_z_levels"]
	if(islist(saved_z_levels) && saved_z_levels.len)
		return saved_z_levels

	var/save_directory_path = get_save_directory_path(save_directory_name)
	var/list/save_files = flist(save_directory_path)
	if(!save_files.len)
		return null

	var/list/legacy_entries = list()
	sortTim(save_files, GLOBAL_PROC_REF(cmp_persistent_saves_asc))

	for(var/save_file in save_files)
		if(copytext("[save_file]", -5) != ".json")
			continue

		var/save_file_basename = copytext("[save_file]", 1, -5)
		legacy_entries += list(list(
			"json_file" = save_file,
			"map_file" = "[save_file_basename].dmm",
		))

	return legacy_entries

/datum/controller/subsystem/world_save/proc/is_save_valid(save_directory_name)
	var/full_path = get_save_directory_path(save_directory_name)
	var/list/completion_data = read_save_completion_data(save_directory_name)
	if(!islist(completion_data))
		log_mapping("Save [save_directory_name] is incomplete - missing or invalid completion marker")
		return FALSE

	if(completion_data["save_completed"] != TRUE)
		log_mapping("Save [save_directory_name] is incomplete - completion marker does not indicate success")
		return FALSE

	var/list/saved_z_levels = get_saved_z_level_entries(save_directory_name, completion_data)
	if(!saved_z_levels.len)
		log_mapping("Save [save_directory_name] appears empty - no saved z-levels were recorded")
		return FALSE

	for(var/list/save_entry as anything in saved_z_levels)
		var/json_file = save_entry["json_file"]
		var/map_file = save_entry["map_file"]
		if(!istext(json_file) || !istext(map_file))
			log_mapping("Save [save_directory_name] has an invalid z-level manifest entry")
			return FALSE

		if(!fexists("[full_path]/[json_file]"))
			log_mapping("Save [save_directory_name] is incomplete - missing [json_file]")
			return FALSE

		if(!fexists("[full_path]/[map_file]"))
			log_mapping("Save [save_directory_name] is incomplete - missing [map_file]")
			return FALSE

	return TRUE

/datum/controller/subsystem/world_save/proc/is_save_compatible(save_directory_name, list/completion_data)
	if("schema_version" in completion_data)
		var/schema_version = completion_data["schema_version"]
		if(schema_version != PERSISTENT_SAVE_SCHEMA_VERSION)
			log_mapping("Save [save_directory_name] uses unsupported persistence schema version [schema_version]")
			return FALSE

	if("map_current_version" in completion_data)
		var/map_current_version = completion_data["map_current_version"]
		if(map_current_version != MAP_CURRENT_VERSION)
			log_mapping("Save [save_directory_name] targets map version [map_current_version] instead of [MAP_CURRENT_VERSION]")
			return FALSE

	return TRUE

/datum/controller/subsystem/world_save/proc/is_save_loadable(save_directory_name)
	if(!is_save_valid(save_directory_name))
		return FALSE

	var/save_directory_path = get_save_directory_path(save_directory_name)
	var/list/completion_data = read_save_completion_data(save_directory_name)
	if(!is_save_compatible(save_directory_name, completion_data))
		return FALSE

	var/list/saved_z_levels = get_saved_z_level_entries(save_directory_name, completion_data)

	for(var/list/save_entry as anything in saved_z_levels)
		var/json_file = save_entry["json_file"]
		if(!istext(json_file))
			return FALSE

		var/datum/map_config/persistent_map = load_map_config(copytext(json_file, 1, -5), save_directory_path, persistence_save = TRUE)
		var/is_valid_config = !persistent_map.defaulted
		qdel(persistent_map)

		if(!is_valid_config)
			log_mapping("Save [save_directory_name] failed to load persistent map config [json_file]")
			return FALSE

	return TRUE

/datum/controller/subsystem/world_save/proc/get_save_flag_names(save_flags)
	var/list/save_flag_names = list()

	if(save_flags & SAVE_OBJECTS)
		save_flag_names += "objects"
	if(save_flags & SAVE_OBJECTS_VARIABLES)
		save_flag_names += "objects_variables"
	if(save_flags & SAVE_OBJECTS_PROPERTIES)
		save_flag_names += "objects_properties"
	if(save_flags & SAVE_MOBS)
		save_flag_names += "mobs"
	if(save_flags & SAVE_TURFS)
		save_flag_names += "turfs"
	if(save_flags & SAVE_TURFS_ATMOS)
		save_flag_names += "turfs_atmos"
	if(save_flags & SAVE_TURFS_SPACE)
		save_flag_names += "turfs_space"
	if(save_flags & SAVE_AREAS)
		save_flag_names += "areas"
	if(save_flags & SAVE_AREAS_DEFAULT_SHUTTLES)
		save_flag_names += "areas_default_shuttles"
	if(save_flags & SAVE_AREAS_CUSTOM_SHUTTLES)
		save_flag_names += "areas_custom_shuttles"

	return save_flag_names

///Returns the path to persistence maps directory based on current timestamp format via YYYY-MM-DD_UTC_hh.mm.ss
/datum/controller/subsystem/world_save/proc/get_current_persistence_map_directory()
	var/realtime = world.realtime
	var/timestamp_utc  = time2text(realtime, "YYYY-MM-DD_UTC_hh.mm.ss", TIMEZONE_UTC)
	var/map_directory = MAP_PERSISTENT_DIRECTORY + timestamp_utc
	return map_directory

///Deletes empty save directories and removes the oldest saves if the total count exceeds the max autosaves allowed in config
/datum/controller/subsystem/world_save/proc/prune_old_autosaves()
	if(!CONFIG_GET(flag/persistent_save_enabled))
		return

	// First, remove any corrupted/incomplete saves
	var/list/all_saves_raw = flist(MAP_PERSISTENT_DIRECTORY)
	for(var/save_directory in all_saves_raw)
		var/full_path = get_save_directory_path(save_directory)

		if(!flist(full_path).len)
			log_mapping("Deleted empty autosave: [full_path]")
			log_admin("Deleted empty autosave: [full_path]")
			fdel(full_path)
			continue

		if(!is_save_valid(save_directory))
			log_mapping("Deleted corrupted autosave: [full_path]")
			log_admin("Deleted corrupted autosave: [full_path]")
			fdel(full_path)

	if(CONFIG_GET(number/persistent_max_autosaves) == INFINITE_AUTOSAVES)
		return

	// organize by oldest saves first
	var/list/all_saves = get_all_saves(GLOBAL_PROC_REF(cmp_text_asc))
	if(!all_saves.len)
		return // no saves exist yet

	var/total_saves = all_saves.len
	var/saves_to_delete = total_saves - CONFIG_GET(number/persistent_max_autosaves)
	if(saves_to_delete <= 0)
		return

	for(var/i in 1 to saves_to_delete)
		var/oldest_autosave_full_path = get_save_directory_path(all_saves[i])
		log_mapping("Deleted oldest autosave: [oldest_autosave_full_path]")
		log_admin("Deleted oldest autosave: [oldest_autosave_full_path]")
		fdel(oldest_autosave_full_path)

/datum/controller/subsystem/world_save/proc/get_last_save()
	// organize by newest saves first
	var/list/all_saves = get_all_saves(GLOBAL_PROC_REF(cmp_text_dsc))
	if(!all_saves.len)
		return null // no saves exist yet

	for(var/save_directory in all_saves)
		if(is_save_loadable(save_directory))
			log_mapping("Using loadable save: [save_directory]")
			return save_directory

		log_mapping("Skipping save that failed load validation: [save_directory]")

	log_mapping("ERROR: No valid saves found!")
	return null

/// Based on the last recent save, get a list of all z levels as numbers which have the specific trait
/// Will return null if no traits match or a save file doesn't exist yet
/datum/controller/subsystem/world_save/proc/cache_z_levels_map_configs()
	var/last_save_name = get_last_save()
	if(!last_save_name)
		log_world("WARNING: No valid persistence saves found")
		return null // no valid saves exist

	var/last_save = get_save_directory_path(last_save_name)
	var/list/completion_data = read_save_completion_data(last_save_name)
	var/list/saved_z_levels = get_saved_z_level_entries(last_save_name, completion_data)
	if(!saved_z_levels.len)
		log_mapping("Save [last_save_name] did not contain any persistent z-level entries")
		return null

	var/list/matching_z_levels = list()
	var/list/persistent_save_z_levels = CONFIG_GET(keyed_list/persistent_save_z_levels)

	for(var/list/save_entry as anything in saved_z_levels)
		var/json_file = save_entry["json_file"]
		var/datum/map_config/map_config = load_map_config(copytext(json_file, 1, -5), last_save, persistence_save = TRUE)
		if(map_config.defaulted)
			log_mapping("Save [last_save_name] contained invalid map config [json_file]")
			return null

		// for persistent autosaves, the name is always a number which indicates the z-level
		var/current_z = map_config.map_name
		if(!islist(map_config.traits))
			CRASH("Missing list of traits in autosave json for [last_save]/[current_z].json")

		// for multi-z maps if a trait is found on ANY z-levels, the entire map is considered to have that trait
		for(var/level in map_config.traits)
			if(persistent_save_z_levels[ZTRAIT_CENTCOM] && (ZTRAIT_CENTCOM in level))
				LAZYINITLIST(matching_z_levels[ZTRAIT_CENTCOM])
				matching_z_levels[ZTRAIT_CENTCOM] |= map_config
			else if(persistent_save_z_levels[ZTRAIT_STATION] && (ZTRAIT_STATION in level))
				LAZYINITLIST(matching_z_levels[ZTRAIT_STATION])
				matching_z_levels[ZTRAIT_STATION] |= map_config
			else if(persistent_save_z_levels[ZTRAIT_MINING] && (ZTRAIT_MINING in level))
				LAZYINITLIST(matching_z_levels[ZTRAIT_MINING])
				matching_z_levels[ZTRAIT_MINING] |= map_config
			else if(persistent_save_z_levels[ZTRAIT_SPACE_RUINS] && (ZTRAIT_SPACE_RUINS in level))
				LAZYINITLIST(matching_z_levels[ZTRAIT_SPACE_RUINS])
				matching_z_levels[ZTRAIT_SPACE_RUINS] |= map_config
			else if(persistent_save_z_levels[ZTRAIT_SPACE_EMPTY] && (ZTRAIT_SPACE_EMPTY in level))
				LAZYINITLIST(matching_z_levels[ZTRAIT_SPACE_EMPTY])
				matching_z_levels[ZTRAIT_SPACE_EMPTY] |= map_config
			else if(persistent_save_z_levels[ZTRAIT_ICE_RUINS] && (ZTRAIT_ICE_RUINS in level))
				LAZYINITLIST(matching_z_levels[ZTRAIT_ICE_RUINS])
				matching_z_levels[ZTRAIT_ICE_RUINS] |= map_config
			else if(persistent_save_z_levels[ZTRAIT_RESERVED] && (ZTRAIT_RESERVED in level)) // for shuttles in transit (hyperspace)
				LAZYINITLIST(matching_z_levels[ZTRAIT_RESERVED])
				matching_z_levels[ZTRAIT_RESERVED] |= map_config
			else if(persistent_save_z_levels[ZTRAIT_AWAY] && (ZTRAIT_AWAY in level)) // gateway away missions
				LAZYINITLIST(matching_z_levels[ZTRAIT_AWAY])
				matching_z_levels[ZTRAIT_AWAY] |= map_config

	if(!matching_z_levels.len)
		return null

	matching_z_levels[PERSISTENT_LOADED_Z_LEVELS] = list()
	map_configs_cache = matching_z_levels
	return map_configs_cache

/*
 * Helper proc to get all saves that returns a list of paths relative to MAP_PERSISTENT_DIRECTORY
 * This will also prune any empty save directories by deleting them automatically
 * Args:
 * * sorting_method: This determines the sorting method and must be either OLDEST or NEWEST
 */
/datum/controller/subsystem/world_save/proc/get_all_saves(sorting_method)
	var/list/all_saves = flist(MAP_PERSISTENT_DIRECTORY)
	var/list/valid_saves = list()

	// Prune any empty save directories
	for(var/path in all_saves)
		if(is_save_valid(path))
			valid_saves += path

	sortTim(valid_saves, sorting_method)
	return valid_saves

/datum/controller/subsystem/world_save/proc/get_save_flags()
	var/flags = NONE

	var/list/persistent_save_flags = CONFIG_GET(keyed_list/persistent_save_flags)

	if(persistent_save_flags["objects"])
		flags |= SAVE_OBJECTS
	if(persistent_save_flags["objects_variables"])
		flags |= SAVE_OBJECTS_VARIABLES
	if(persistent_save_flags["objects_properties"])
		flags |= SAVE_OBJECTS_PROPERTIES

	if(persistent_save_flags["mobs"])
		flags |= SAVE_MOBS

	if(persistent_save_flags["turfs"])
		flags |= SAVE_TURFS
	if(persistent_save_flags["turfs_atmos"])
		flags |= SAVE_TURFS_ATMOS
	if(persistent_save_flags["turfs_space"])
		flags |= SAVE_TURFS_SPACE

	if(persistent_save_flags["areas"])
		flags |= SAVE_AREAS
	if(persistent_save_flags["areas_default_shuttles"])
		flags |= SAVE_AREAS_DEFAULT_SHUTTLES
	if(persistent_save_flags["areas_custom_shuttles"])
		flags |= SAVE_AREAS_CUSTOM_SHUTTLES

	return flags

/datum/controller/subsystem/world_save/proc/save_persistent_maps(list/z_levels, silent=FALSE)
	save_in_progress = TRUE
	save_cancel_requested = FALSE
	current_save_metrics = list()
	reset_current_save_diagnostics()
	counted_areas = list()

	GLOB.TGM_objs = 0
	GLOB.TGM_mobs = 0
	GLOB.TGM_total_objs = 0
	GLOB.TGM_total_mobs = 0
	GLOB.TGM_total_turfs = 0
	GLOB.TGM_total_areas = 0

	var/map_save_directory = get_current_persistence_map_directory()
	current_save_directory = map_save_directory
	var/save_flags = get_save_flags()
	var/overall_save_start = REALTIMEOFDAY
	var/list/persistent_save_z_levels = CONFIG_GET(keyed_list/persistent_save_z_levels)
	var/list/saved_z_level_entries = list()

	for(var/z in 1 to world.maxz)
		if(should_cancel_save())
			return abort_current_save("cancel requested", silent)

		var/list/level_traits = list()
		var/datum/space_level/level_to_check = SSmapping.z_list[z]
		var/list/z_traits = level_to_check.traits.Copy()
		if(level_to_check.xi || level_to_check.yi)
			z_traits["xi"] = level_to_check.xi
			z_traits["yi"] = level_to_check.yi
		level_traits += list(z_traits)

		if(z_levels) // Skip saving z-levels based on num
			if(!z_levels[num2text(z)])
				continue
		else // Skip saving certain z-levels based on config settings
			if(!persistent_save_z_levels[ZTRAIT_CENTCOM] && is_centcom_level(z))
				continue
			else if(!persistent_save_z_levels[ZTRAIT_STATION] && is_station_level(z))
				continue
			else if(!persistent_save_z_levels[ZTRAIT_SPACE_EMPTY] && is_space_empty_level(z))
				continue
			else if(!persistent_save_z_levels[ZTRAIT_SPACE_RUINS] && is_space_ruins_level(z))
				continue
			else if(!persistent_save_z_levels[ZTRAIT_ICE_RUINS] && is_ice_ruins_level(z))
				continue
			else if(!persistent_save_z_levels[ZTRAIT_MINING] && is_mining_level(z))
				continue
			else if(!persistent_save_z_levels[ZTRAIT_RESERVED] && is_reserved_level(z)) // for shuttles in transit (hyperspace)
				continue
			else if(!persistent_save_z_levels[ZTRAIT_AWAY] && is_away_level(z)) // gateway away missions
				continue

		var/bottom_z = z
		var/top_z = z
		if(is_multi_z_level(z))
			if(!SSmapping.level_trait(z, ZTRAIT_UP) || SSmapping.level_trait(z, ZTRAIT_DOWN))
				continue // skip all the other z levels if they aren't a bottom

			for(var/above_z in (bottom_z + 1) to world.maxz)
				var/datum/space_level/above_level_to_check = SSmapping.z_list[above_z]
				var/list/above_z_traits = above_level_to_check.traits.Copy()
				if(above_level_to_check.xi || above_level_to_check.yi)
					above_z_traits["xi"] = above_level_to_check.xi
					above_z_traits["yi"] = above_level_to_check.yi
				level_traits += list(above_z_traits)

				if(!SSmapping.level_trait(above_z, ZTRAIT_UP) && SSmapping.level_trait(above_z, ZTRAIT_DOWN))
					top_z = above_z
					break

		// Update progress tracking for this z-level
		current_save_z_level = z
		current_save_x = 0
		current_save_y = 0
		var/z_objs_start = GLOB.TGM_total_objs
		var/z_mobs_start = GLOB.TGM_total_mobs
		var/z_turfs_start = GLOB.TGM_total_turfs
		var/z_areas_start = GLOB.TGM_total_areas

		var/z_save_time_start = REALTIMEOFDAY
		var/map = write_map(1, 1, bottom_z, world.maxx, world.maxy, top_z, save_flags)
		if(should_cancel_save() || !istext(map))
			return abort_current_save("cancel requested", silent)

		var/file_path = "[map_save_directory]/[z].dmm"
		rustg_file_write(map, file_path)
		var/map_path = copytext(map_save_directory, 7) // drop the "_maps/" from directory
		var/json_data = list(
			"version" = MAP_CURRENT_VERSION,
			"map_name" = level_to_check.name || CUSTOM_MAP_PATH,
			"map_path" = map_path,
			"map_file" = "[z].dmm",
			"traits" = level_traits,
			"minetype" = MINETYPE_NONE,
		)

		// saving station z-levels but not mining, we need to make sure minetype is included
		if(is_station_level(z) && !persistent_save_z_levels[ZTRAIT_MINING])
			json_data["minetype"] = SSmapping.current_map.minetype

		// consult is_on_a_planet() proc to see how planetary is determined
		// on mining levels, planetary is always TRUE and doesnt need to be set
		// on station levels, planetary is set via map_config (ie. Ice)
		if(is_station_level(z) && SSmapping.is_planetary())
			json_data["planetary"] = TRUE

		rustg_file_write(json_encode(json_data, JSON_PRETTY_PRINT), "[map_save_directory]/[z].json")
		saved_z_level_entries += list(list(
			"bottom_z" = bottom_z,
			"top_z" = top_z,
			"level_name" = level_to_check.name || "Z-Level [bottom_z]",
			"json_file" = "[z].json",
			"map_file" = "[z].dmm",
		))

		var/z_save_time_end = (REALTIMEOFDAY - z_save_time_start) / 10
		current_save_metrics += list(list(
			"z-level" = bottom_z,
			"multi z-levels" = top_z - bottom_z,
			"save_time_seconds" = z_save_time_end,
			"mobs_saved" = GLOB.TGM_total_mobs - z_mobs_start,
			"objs_saved" = GLOB.TGM_total_objs - z_objs_start,
			"turfs_saved" = GLOB.TGM_total_turfs - z_turfs_start,
			"areas_saved" = GLOB.TGM_total_areas - z_areas_start,
		))

	var/overall_save_time_end = (REALTIMEOFDAY - overall_save_start) / 10
	var/completion_data = list(
		"schema_version" = PERSISTENT_SAVE_SCHEMA_VERSION,
		"map_current_version" = MAP_CURRENT_VERSION,
		"save_completed" = TRUE,
		"timestamp" = time2text(world.realtime, "YYYY-MM-DD hh:mm:ss"),
		"source_map_name" = SSmapping.current_map.map_name,
		"source_map_file" = SSmapping.current_map.map_file,
		"save_flags" = save_flags,
		"save_flag_names" = get_save_flag_names(save_flags),
		"configured_z_level_traits" = persistent_save_z_levels.Copy(),
		"saved_z_levels" = saved_z_level_entries,
		"world_size" = list("x" = world.maxx, "y" = world.maxy, "z" = world.maxz),
		"serialization_diagnostics" = clone_current_save_diagnostics(),
		"total_save_time_seconds" = overall_save_time_end,
		"z_level_metrics" = current_save_metrics,
	)
	if(islist(z_levels) && z_levels.len)
		completion_data["requested_z_levels"] = z_levels.Copy()

	var/completion_marker_path = "[map_save_directory]/[SAVE_COMPLETION_MARKER]"
	rustg_file_write(json_encode(completion_data, JSON_PRETTY_PRINT), completion_marker_path)

	return finish_current_save(silent)

/// Gets the current progress percentage for the active z-level
/datum/controller/subsystem/world_save/proc/get_current_progress_percent()
	if(!save_in_progress)
		return 0

	var/total_tiles = world.maxx * world.maxy
	var/completed_tiles = (current_save_x * world.maxy) + current_save_y

	return (completed_tiles / total_tiles) * 100

#undef INFINITE_AUTOSAVES
#undef SAVE_COMPLETION_MARKER
#undef PERSISTENT_SAVE_SCHEMA_VERSION
