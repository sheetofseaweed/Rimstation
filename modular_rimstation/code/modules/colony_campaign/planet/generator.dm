/**
 * Cave generator for the colony surface, seeded from a planet definition.
 *
 * The inherited generator builds its cave shape with rustg_cave_system_generator_generate(), which takes no
 * seed argument, so a campaign cannot ask it for the same caves twice. This subtype replaces only that step
 * with thresholded coordinate noise, which is seedable and already spatially smooth enough to read as caves
 * without a separate cellular-automata pass. Every other generator keeps the BSP implementation.
 */
/datum/map_generator/cave_generator/rimstation_colony
	name = "Rimstation Colony Caves"
	generation_seed_namespace = "colony_surface"
	// Exactly one type per side, because the inherited non-biome path picks with pick() and a second entry
	// would put an unseeded roll back into terrain. rimstation_colony_generator_determinism guards this.
	weighted_open_turf_types = list(/turf/open/misc/dirt/planet/rimstation = 1)
	weighted_closed_turf_types = list(/turf/closed/mineral/random/rimstation = 1)

	/**
	 * Earthlike ecology, replacing the lavaland defaults the parent installs in New().
	 *
	 * Left unset, a colony that starts with a knife and a shovel would share its surface with goliaths,
	 * hivelords and whatever GLOB.megafauna_spawn_list holds. These are animals a new settlement can hunt,
	 * herd or survive, which is the point of the opening.
	 */
	weighted_mob_spawn_list = list(
		/mob/living/basic/rabbit = 5,
		/mob/living/basic/chicken = 4,
		/mob/living/basic/deer = 3,
		/mob/living/basic/goat = 2,
		/mob/living/basic/cow = 1,
	)
	// Megafauna are excluded by the wilds area withholding MEGAFAUNA_SPAWN_ALLOWED rather than by emptying
	// the list here: an empty list is truthy in DM, so the parent would still expand_weights() it and
	// divide by a greatest common factor of nothing.
	/// Trees are the renewable wood the opening package primes with, so they lead the table.
	weighted_flora_spawn_list = list(
		/obj/structure/flora/tree/dead = 4,
		/obj/structure/flora/bush/ferny = 3,
		/obj/structure/flora/bush/flowers_yw = 1,
		/obj/structure/flora/bush/flowers_br = 1,
		/obj/structure/flora/rock = 2,
	)
	/// Ore vents give the colony a reason to dig. Geysers are lavaland set dressing and are dropped.
	weighted_feature_spawn_list = list(/obj/structure/ore_vent/random = 1)

/datum/map_generator/cave_generator/rimstation_colony/New()
	. = ..()
	generation_seed_provider = get_active_colony_planet()

/**
 * TRUE when this coordinate should be open floor.
 *
 * Coordinates are divided by perlin_zoom because the noise is only interesting between lattice points; sampling
 * raw integers returns a near-constant field.
 */
/datum/map_generator/cave_generator/rimstation_colony/proc/resolve_cave_openness(cave_seed, x, y)
	var/noise = text2num(rustg_noise_get_at_coordinates("[cave_seed]", "[x / perlin_zoom]", "[y / perlin_zoom]"))
	return noise > (noise_percent / 100)

/// Builds the same open/closed grid string the inherited generator returns, but reproducibly.
/datum/map_generator/cave_generator/rimstation_colony/proc/build_seeded_cave_string(cave_seed)
	var/list/grid = new /list(world.maxx * world.maxy)
	for(var/y in 1 to world.maxy)
		for(var/x in 1 to world.maxx)
			grid[world.maxx * (y - 1) + x] = resolve_cave_openness(cave_seed, x, y) ? "1" : "0"
		CHECK_TICK
	return grid.Join("")

/datum/map_generator/cave_generator/rimstation_colony/generate_cave(area/generate_in)
	var/cave_seed = resolve_generation_seed(PLANET_STREAM_TERRAIN, generate_in.z)
	if(isnull(cave_seed))
		// No planet bound, so there is nothing to be reproducible about. Behave like any other cave generator.
		return ..()
	return build_seeded_cave_string(cave_seed)


/**
 * Binds one planet definition to the generators that build its surface.
 *
 * This is the seam between "what world is this" and "how is it drawn": the planet owns the seeds, the map
 * generators own the terrain rules, and this adapter is the only thing that knows about both.
 */
/datum/colony_planet_generator
	/// The world being generated.
	var/datum/planet_definition/planet
	/// The surface cave generator this adapter drives.
	var/datum/map_generator/cave_generator/rimstation_colony/surface_generator

/datum/colony_planet_generator/New(datum/planet_definition/planet)
	. = ..()
	src.planet = planet
	surface_generator = new
	bind_generator(surface_generator)

/datum/colony_planet_generator/Destroy(force)
	QDEL_NULL(surface_generator)
	planet = null
	return ..()

/// Points a generator at this adapter's planet. Namespace defaults to whatever the generator already declares.
/datum/colony_planet_generator/proc/bind_generator(datum/map_generator/cave_generator/generator, namespace)
	if(!istype(generator))
		CRASH("Tried to bind a non-cave-generator to a colony planet generator.")
	generator.generation_seed_provider = planet
	if(namespace)
		generator.generation_seed_namespace = namespace
	return generator

/**
 * A stable hash of the terrain this planet produces on one z level.
 *
 * Deliberately computed from the generator's decisions rather than by generating and inspecting real turfs:
 * a fingerprint that mutated the map could not be taken twice, and could not be taken at all during a round.
 *
 * Covers exactly what the sampled turf type at a coordinate depends on - the open/closed cave shape and the
 * inputs to biome selection. It does not cover flora, features or fauna, which are objects placed on top of
 * the terrain by unseeded picks; a matching fingerprint means the ground matches, not that the ecology does.
 */
/datum/colony_planet_generator/proc/terrain_fingerprint(z, sample_count = 64)
	if(isnull(planet))
		return null

	var/cave_seed = surface_generator.resolve_generation_seed(PLANET_STREAM_TERRAIN, z)
	if(isnull(cave_seed))
		return null

	var/list/parts = list()
	for(var/stream in list(PLANET_STREAM_TERRAIN, PLANET_STREAM_BIOME_HEAT, PLANET_STREAM_BIOME_HUMIDITY))
		parts += "[stream]=[surface_generator.resolve_generation_seed(stream, z)]"

	// Coprime strides walk the map instead of sampling one band, without needing to visit every tile.
	for(var/i in 1 to sample_count)
		var/sample_x = ((i * 7) % world.maxx) + 1
		var/sample_y = ((i * 13) % world.maxy) + 1
		var/open = surface_generator.resolve_cave_openness(cave_seed, sample_x, sample_y)
		var/drift_x = surface_generator.resolve_biome_drift(cave_seed, sample_x, sample_y, BIOME_DRIFT_AXIS_X)
		var/drift_y = surface_generator.resolve_biome_drift(cave_seed, sample_x, sample_y, BIOME_DRIFT_AXIS_Y)
		parts += "[sample_x],[sample_y]:[open ? "open" : "closed"]:[drift_x],[drift_y]"

	return rustg_hash_string(RUSTG_HASH_SHA256, parts.Join("|"))
