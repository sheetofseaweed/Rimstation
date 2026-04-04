/// Save object types.
#define SAVE_OBJECTS (1 << 1)
/// Save object variables from obj.get_save_vars() and obj.get_custom_save_vars().
#define SAVE_OBJECTS_VARIABLES (1 << 2)
/// Save object custom properties from obj.on_object_saved().
#define SAVE_OBJECTS_PROPERTIES (1 << 3)
/// Save mob types (excludes mob/living/carbon).
#define SAVE_MOBS (1 << 4)
/// Save turf types, if disabled saves turfs as /turf/template_noop.
#define SAVE_TURFS (1 << 5)
/// Save turf atmospheric properties.
#define SAVE_TURFS_ATMOS (1 << 6)
/// Save space turfs, otherwise replace them with /template_noop.
#define SAVE_TURFS_SPACE (1 << 7)
/// Save area types, if disabled saves areas as /area/template_noop.
#define SAVE_AREAS (1 << 8)
/// Save area types for default shuttles.
#define SAVE_AREAS_DEFAULT_SHUTTLES (1 << 9)
/// Save area types for custom player-built shuttles.
#define SAVE_AREAS_CUSTOM_SHUTTLES (1 << 10)

// Ignore turf if it contains
#define SAVE_SHUTTLEAREA_DONTCARE 0
#define SAVE_SHUTTLES_ONLY 1

#define DMM2TGM_MESSAGE "MAP CONVERTED BY dmm2tgm.py THIS HEADER COMMENT PREVENTS RECONVERSION, DO NOT REMOVE"

/// Sanitizes text so it remains safe inside serialized TGM output.
#define HASHTAG_NEWLINES_AND_TABS(text, replacements)\
	if(isnull(replacements)) {\
		replacements = list("\n"="#", "\t"="#");\
	};\
	for(var/char in replacements){\
		text = replacetext(text, char, replacements[char]);\
	};

/**
 * Encodes a value into a TGM-valid string.
 * Not handled:
 * - pops: /obj{name="foo"}
 * - new(), newlist(), icon(), matrix(), sound()
 */
#define TGM_ENCODE(value)\
	if(istext(value)) {\
		value = tgm_encode_text(value);\
	} else if(isnum(value) || ispath(value)) {\
		value = "[value]";\
	} else if(islist(value)) {\
		value = to_list_string(value);\
	} else if(isnull(value)) {\
		value = "null";\
	} else if(isicon(value) || isfile(value)) {\
		value = "'[value]'";\
	} else {\
		value = tgm_encode_text("[value]");\
	};

/// Generates a TGM string for an object's variables "{variables}".
#define TGM_VARS_BLOCK(variables) ("{\n\t[variables]\n\t}")

/// Generates a TGM string for a single variable assignment line.
#define TGM_VAR_LINE(variable, value) ("[variable] = [value]")

/**
 * Adds a TGM object to the map string with optional variables.
 *
 * Arguments:
 * map_string: The current map string being assembled (will be modified in-place).
 * typepath: The typepath to save.
 * variables_metadata: Variables formatted via generate_tgm_metadata().
 */
#define TGM_MAP_BLOCK(map_string, typepath, variables_metadata)\
	if(length(map_string)) {\
		map_string += ",\n";\
	};\
	map_string += "[typepath]";\
	if(length(variables_metadata)) {\
		map_string += "[variables_metadata]";\
	};

/**
 * Adds a variable/value pair only when it differs from the typepath default.
 */
#define TGM_ADD_TYPEPATH_VAR(variables_to_add, typepath, var, value)\
	if(!IS_TYPEPATH_DEFAULT_VAR(typepath, var, value)) {\
		variables_to_add[NAMEOF(typepath, var)] = value;\
	};

// same as above but for static typepaths
#define TGM_ADD_STATIC_TYPEPATH_VAR(variables_to_add, typepath, var, value)\
	if(!IS_TYPEPATH_DEFAULT_VAR(typepath, var, value)) {\
		variables_to_add[nameof(##typepath::##var)] = value;\
	};

/// Checks if a value matches the compile-time default value of a typepath variable.
#define IS_TYPEPATH_DEFAULT_VAR(datum, variable, new_var) (##datum::variable == new_var)

/// Increment object counter (per turf).
#define INCREMENT_OBJ_COUNT(...) \
	do { \
		GLOB.TGM_objs++; \
		GLOB.TGM_total_objs++; \
	} while(FALSE); \

/// Increment mob counter (per turf).
#define INCREMENT_MOB_COUNT(...) \
	do { \
		GLOB.TGM_mobs++; \
		GLOB.TGM_total_mobs++; \
	} while(FALSE); \

/// Increment turf counter.
#define INCREMENT_TURF_COUNT (GLOB.TGM_total_turfs++)

/// Increment area counter.
#define INCREMENT_AREA_COUNT (GLOB.TGM_total_areas++)

/// Check if object limit is exceeded.
#define OBJECT_LIMIT_EXCEEDED (GLOB.TGM_objs >= CONFIG_GET(number/persistent_max_object_limit_per_turf))

/// Check if mob limit is exceeded.
#define MOB_LIMIT_EXCEEDED (GLOB.TGM_mobs >= CONFIG_GET(number/persistent_max_mob_limit_per_turf))
