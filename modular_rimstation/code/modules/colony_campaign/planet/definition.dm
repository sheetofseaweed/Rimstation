/**
 * The persistent identity of one campaign world.
 *
 * This record is the only input a colony surface is generated from, so it is deliberately small, serializable,
 * and version-stamped. Generation reads derived stream seeds from here instead of calling rand(), which is what
 * lets a campaign rebuild the same planet next chapter.
 */
/datum/planet_definition
	/// Layout version of this record. Refuses to load anything it was not written to understand.
	var/schema_version = PLANET_DEFINITION_SCHEMA_VERSION
	/// Generation behaviour version. Mixed into every derived seed, so bumping it retires existing worlds.
	var/generation_version = PLANET_GENERATION_VERSION
	/// Campaign-facing identifier. Free-form; the seed is what determines the world.
	var/planet_id
	/// The single value every stream seed is derived from. Text, so the hash input is byte-stable.
	var/root_seed

	/// Breathable mix identifier for the surface.
	var/atmosphere = "standard"
	var/gravity = STANDARD_GRAVITY
	/// Mean surface temperature in kelvin.
	var/mean_temperature = T20C
	/// Surface water availability, 0 to 100.
	var/moisture = 50
	/// Broad rock/soil character, used to pick mineral and turf sets.
	var/geology = "sedimentary"
	/// Which resource table the surface draws from.
	var/resource_profile = "temperate"
	/// Which flora and fauna table the surface draws from.
	var/ecology_profile = "temperate"
	/// Which weather set the planet schedules from.
	var/weather_set = "temperate"
	/// Which ruin table the surface draws from.
	var/ruin_theme = "abandoned_colony"

	/// Cache of derived stream seeds. Derivation is pure, so this is purely to avoid rehashing.
	var/list/derived_seeds

/datum/planet_definition/New(root_seed, planet_id, generation_version = PLANET_GENERATION_VERSION)
	. = ..()
	src.root_seed = root_seed
	src.planet_id = planet_id
	src.generation_version = generation_version

/**
 * Returns the derived seed for one generation stream, or null if the stream is not one we know.
 *
 * Derivation never touches BYOND's global RNG, so generation order cannot change a planet's shape.
 */
/datum/planet_definition/proc/get_stream_seed(stream)
	if(!(stream in PLANET_GENERATION_STREAMS))
		stack_trace("Unknown planet generation stream '[stream]'.")
		return null
	if(!root_seed)
		stack_trace("Planet definition has no root seed, cannot derive stream '[stream]'.")
		return null

	LAZYINITLIST(derived_seeds)
	var/cached = derived_seeds[stream]
	if(cached)
		return cached

	var/derived = copytext(rustg_hash_string(RUSTG_HASH_SHA256, "[generation_version]:[root_seed]:[stream]"), 1, PLANET_STREAM_SEED_LENGTH + 1)
	derived_seeds[stream] = derived
	return derived

/// Flat list form for JSON storage. Keep in step with deserialize().
/datum/planet_definition/proc/serialize()
	RETURN_TYPE(/list)
	return list(
		"schema_version" = schema_version,
		"generation_version" = generation_version,
		"planet_id" = planet_id,
		"root_seed" = root_seed,
		"atmosphere" = atmosphere,
		"gravity" = gravity,
		"mean_temperature" = mean_temperature,
		"moisture" = moisture,
		"geology" = geology,
		"resource_profile" = resource_profile,
		"ecology_profile" = ecology_profile,
		"weather_set" = weather_set,
		"ruin_theme" = ruin_theme,
	)

/**
 * Loads a record produced by serialize(). Returns TRUE on success, FALSE if the record was refused.
 *
 * A refused record must never leave the datum half-populated, because a partially applied planet would
 * generate a different world than the campaign committed to. Everything is validated before anything is set.
 */
/datum/planet_definition/proc/deserialize(list/data)
	// Records come off disk and may be hand-edited or written by an older build, so a bad one is an expected
	// outcome to report, not a code fault to stack_trace.
	if(!islist(data))
		log_game("Planet record rejected: not a list.")
		return FALSE

	var/incoming_schema = data["schema_version"]
	if(!isnum(incoming_schema) || incoming_schema != PLANET_DEFINITION_SCHEMA_VERSION)
		log_game("Planet record rejected: unsupported schema version '[incoming_schema]'.")
		return FALSE

	var/incoming_generation = data["generation_version"]
	if(!isnum(incoming_generation) || incoming_generation < 1 || incoming_generation != round(incoming_generation))
		log_game("Planet record rejected: invalid generation version '[incoming_generation]'.")
		return FALSE

	// Text keeps the hash input byte-stable; a number could stringify differently and silently move the world.
	var/incoming_seed = data["root_seed"]
	if(!istext(incoming_seed) || !length(incoming_seed))
		log_game("Planet record rejected: invalid root seed.")
		return FALSE

	for(var/numeric_field in list("gravity", "mean_temperature", "moisture"))
		if(!isnum(data[numeric_field]))
			log_game("Planet record rejected: field '[numeric_field]' is not a number.")
			return FALSE

	for(var/text_field in list("atmosphere", "geology", "resource_profile", "ecology_profile", "weather_set", "ruin_theme"))
		if(!istext(data[text_field]) || !length(data[text_field]))
			log_game("Planet record rejected: field '[text_field]' is not a non-empty string.")
			return FALSE

	schema_version = incoming_schema
	generation_version = incoming_generation
	root_seed = incoming_seed
	planet_id = data["planet_id"]
	atmosphere = data["atmosphere"]
	gravity = data["gravity"]
	mean_temperature = data["mean_temperature"]
	moisture = data["moisture"]
	geology = data["geology"]
	resource_profile = data["resource_profile"]
	ecology_profile = data["ecology_profile"]
	weather_set = data["weather_set"]
	ruin_theme = data["ruin_theme"]
	derived_seeds = null
	return TRUE

/**
 * The planet the colony map is currently generated from.
 *
 * A placeholder seam. Phase 2 gives SScampaign ownership of this, loading the record from the campaign
 * manifest so a saved town regenerates on the world it was built on. Until then it hands out one fixed
 * development world, which is still reproducible - just not yet chosen per campaign.
 */
GLOBAL_DATUM(rimstation_active_planet, /datum/planet_definition)

/proc/get_active_colony_planet()
	RETURN_TYPE(/datum/planet_definition)
	if(!GLOB.rimstation_active_planet)
		GLOB.rimstation_active_planet = new /datum/planet_definition(RIMSTATION_DEVELOPMENT_PLANET_SEED, "rimstation-development")
	return GLOB.rimstation_active_planet

/// TRUE when both records would generate the same world and carry the same campaign metadata.
/datum/planet_definition/proc/equals(datum/planet_definition/other)
	if(!istype(other))
		return FALSE
	var/list/ours = serialize()
	var/list/theirs = other.serialize()
	if(length(ours) != length(theirs))
		return FALSE
	for(var/key in ours)
		if(ours[key] != theirs[key])
			return FALSE
	return TRUE
