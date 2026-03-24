// Configs for persistent map saving and loading
/// This will load the most recent saved maps, z-levels, and jsons in the _maps/persistence folder organized by year/month/day/hour-minute-second
/datum/config_entry/flag/persistent_save_enabled
/// Include specific z-levels when saving and loading determined by trait
/datum/config_entry/keyed_list/persistent_save_z_levels
	key_mode = KEY_MODE_TEXT
	value_mode = VALUE_MODE_FLAG
	lowercase_key = FALSE //The macros are written the exact same way as their values
/// Include specific save flags that determines types and data to save and load
/datum/config_entry/keyed_list/persistent_save_flags
	key_mode = KEY_MODE_TEXT
	value_mode = VALUE_MODE_FLAG
	lowercase_key = FALSE
/// If enabled, disables procedural grid generation and loads the pre-configured layout from z-level JSONs.
/datum/config_entry/flag/persistent_use_static_map_grid
/// Period of time in hours between map autosaves (set to -1 to only allow saving when server reboots)
/datum/config_entry/number/persistent_autosave_period
	integer = FALSE
	default = 4 // every 4 hours
	min_val = -1
/// The max amount of objects that can be saved on a single turf (rest get skipped)
/datum/config_entry/number/persistent_max_object_limit_per_turf
	default = 100
	min_val = 1
/// The max amount of mobs that can be saved on a single turf (rest get skipped)
/datum/config_entry/number/persistent_max_mob_limit_per_turf
	default = 5
	min_val = 1
/// The maximum amount of autosaves to store (set to -1 to never delete any autosaves)
/datum/config_entry/number/persistent_max_autosaves
	default = -1
	min_val = -1
