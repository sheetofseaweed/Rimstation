#define PLANET_TEST_SEED "rimstation-planet-test"

/// A planet has to rebuild identically from its root seed, and each stream has to move independently.
/datum/unit_test/rimstation_planet_definition

/datum/unit_test/rimstation_planet_definition/Run()
	var/datum/planet_definition/first = new(PLANET_TEST_SEED)
	var/datum/planet_definition/second = new(PLANET_TEST_SEED)
	allocated += first
	allocated += second

	var/list/seen_seeds = list()
	for(var/stream in PLANET_GENERATION_STREAMS)
		var/first_seed = first.get_stream_seed(stream)
		TEST_ASSERT_NOTNULL(first_seed, "Stream '[stream]' produced no seed.")
		TEST_ASSERT_EQUAL(first_seed, second.get_stream_seed(stream), "Stream '[stream]' was not reproducible from an identical root seed.")
		// Independent streams are the point: adding content to one must not reshuffle the others.
		TEST_ASSERT(!(first_seed in seen_seeds), "Stream '[stream]' collided with an earlier stream's seed.")
		seen_seeds += first_seed

	// Repeated reads must stay stable, since generation calls the same stream many times.
	TEST_ASSERT_EQUAL(first.get_stream_seed(PLANET_STREAM_TERRAIN), first.get_stream_seed(PLANET_STREAM_TERRAIN), "Reading a stream twice returned different seeds.")

	// A generation revision is how we deliberately retire old worlds, so it must change every stream.
	var/datum/planet_definition/revised = new(PLANET_TEST_SEED, null, first.generation_version + 1)
	allocated += revised
	for(var/stream in PLANET_GENERATION_STREAMS)
		TEST_ASSERT_NOTEQUAL(revised.get_stream_seed(stream), first.get_stream_seed(stream), "Stream '[stream]' ignored the generation version.")

	var/datum/planet_definition/other_world = new("[PLANET_TEST_SEED]-2")
	allocated += other_world
	TEST_ASSERT_NOTEQUAL(other_world.get_stream_seed(PLANET_STREAM_TERRAIN), first.get_stream_seed(PLANET_STREAM_TERRAIN), "Two different root seeds produced the same terrain stream.")

	// Asking for an undefined stream is a typo in caller code, so get_stream_seed() stack_traces on purpose.
	// That is deliberately not asserted here: exercising it would raise the runtime it is meant to raise.


/// A planet record is campaign-critical state, so a bad record must be refused rather than quietly regenerated.
/datum/unit_test/rimstation_planet_definition_serialization

/datum/unit_test/rimstation_planet_definition_serialization/Run()
	var/datum/planet_definition/original = new(PLANET_TEST_SEED, "colony-alpha")
	allocated += original

	var/list/decoded = json_decode(json_encode(original.serialize()))
	TEST_ASSERT_NOTNULL(decoded, "A serialized planet record did not survive JSON encoding.")

	var/datum/planet_definition/restored = new()
	allocated += restored
	TEST_ASSERT(restored.deserialize(decoded), "A well-formed planet record was rejected.")
	TEST_ASSERT(original.equals(restored), "A planet record did not survive a JSON round trip.")
	for(var/stream in PLANET_GENERATION_STREAMS)
		TEST_ASSERT_EQUAL(restored.get_stream_seed(stream), original.get_stream_seed(stream), "Stream '[stream]' changed across a JSON round trip.")

	var/datum/planet_definition/reject = new()
	allocated += reject

	var/list/missing_version = decoded.Copy()
	missing_version -= "schema_version"
	TEST_ASSERT(!reject.deserialize(missing_version), "A record with no schema version was accepted.")

	var/list/future_version = decoded.Copy()
	future_version["schema_version"] = PLANET_DEFINITION_SCHEMA_VERSION + 1
	TEST_ASSERT(!reject.deserialize(future_version), "A record from an unknown future schema was accepted.")

	var/list/blank_seed = decoded.Copy()
	blank_seed["root_seed"] = ""
	TEST_ASSERT(!reject.deserialize(blank_seed), "A record with an empty root seed was accepted.")

	// Numbers stringify differently across BYOND versions, so the hash input has to stay text.
	var/list/numeric_seed = decoded.Copy()
	numeric_seed["root_seed"] = 12345
	TEST_ASSERT(!reject.deserialize(numeric_seed), "A record with a non-text root seed was accepted.")

	var/list/bad_generation = decoded.Copy()
	bad_generation["generation_version"] = 0
	TEST_ASSERT(!reject.deserialize(bad_generation), "A record with a non-positive generation version was accepted.")


/// The seed contract has to be opt-in: bound generators become reproducible, inherited ones must not change.
/datum/unit_test/rimstation_planet_seed_contract

/datum/unit_test/rimstation_planet_seed_contract/Run()
	var/datum/planet_definition/planet = new(PLANET_TEST_SEED)
	allocated += planet

	var/datum/map_generator/cave_generator/legacy = new
	allocated += legacy
	TEST_ASSERT_NULL(legacy.resolve_generation_seed(PLANET_STREAM_BIOME_HEAT, 1), "A generator with no planet bound returned a seed instead of deferring to rand().")

	var/datum/map_generator/cave_generator/bound = new
	allocated += bound
	bound.generation_seed_provider = planet
	bound.generation_seed_namespace = "surface"

	var/heat = bound.resolve_generation_seed(PLANET_STREAM_BIOME_HEAT, 1)
	TEST_ASSERT_NOTNULL(heat, "A bound generator produced no heat seed.")
	TEST_ASSERT_EQUAL(heat, bound.resolve_generation_seed(PLANET_STREAM_BIOME_HEAT, 1), "Resolving the same stream twice returned different seeds.")
	// The noise generators are fed values in this range, so staying inside it keeps behaviour comparable.
	TEST_ASSERT(heat >= 0 && heat < 50000, "A resolved seed fell outside the 0-50000 range the noise generators expect.")

	TEST_ASSERT_NOTEQUAL(heat, bound.resolve_generation_seed(PLANET_STREAM_BIOME_HUMIDITY, 1), "Heat and humidity resolved to the same seed on one z level.")
	// One planet covers several z levels, which must not come out identical.
	TEST_ASSERT_NOTEQUAL(heat, bound.resolve_generation_seed(PLANET_STREAM_BIOME_HEAT, 2), "Two z levels resolved to the same heat seed.")

	var/datum/map_generator/cave_generator/other_namespace = new
	allocated += other_namespace
	other_namespace.generation_seed_provider = planet
	other_namespace.generation_seed_namespace = "underground"
	TEST_ASSERT_NOTEQUAL(heat, other_namespace.resolve_generation_seed(PLANET_STREAM_BIOME_HEAT, 1), "Two generator namespaces sharing a planet resolved to the same seed.")


/// Biome drift decides which sample each border tile reads, so it has to be reproducible too.
/datum/unit_test/rimstation_planet_biome_drift

/datum/unit_test/rimstation_planet_biome_drift/Run()
	var/datum/planet_definition/planet = new(PLANET_TEST_SEED)
	allocated += planet

	var/datum/map_generator/cave_generator/bound = new
	allocated += bound
	bound.generation_seed_provider = planet
	bound.generation_seed_namespace = "surface"

	var/drift_seed = bound.resolve_generation_seed(PLANET_STREAM_TERRAIN, 1)
	TEST_ASSERT_NOTNULL(drift_seed, "A bound generator produced no terrain seed to drift with.")

	var/drift_range = bound.get_biome_drift_range()
	var/seen_variation = FALSE
	var/first_sample = bound.resolve_biome_drift(drift_seed, 40, 40, BIOME_DRIFT_AXIS_X)
	for(var/x in 1 to 60)
		for(var/axis in list(BIOME_DRIFT_AXIS_X, BIOME_DRIFT_AXIS_Y))
			var/drift = bound.resolve_biome_drift(drift_seed, x, 40, axis)
			TEST_ASSERT(drift >= -drift_range && drift <= drift_range, "Seeded drift left the legacy drift range at x=[x], axis [axis], with value [drift].")
			TEST_ASSERT_EQUAL(drift, bound.resolve_biome_drift(drift_seed, x, 40, axis), "Seeded drift was not stable for a fixed coordinate at x=[x].")
			if(drift != first_sample)
				seen_variation = TRUE
	TEST_ASSERT(seen_variation, "Seeded drift returned one constant value, which would remove biome border intermingling.")

	// Without a seed the legacy rand() path has to stay in place. If this ever came back constant, every
	// inherited map would quietly start generating the same terrain each round.
	var/legacy_varied = FALSE
	var/first_legacy_drift = bound.resolve_biome_drift(null, 40, 40, BIOME_DRIFT_AXIS_X)
	for(var/i in 1 to 40)
		var/legacy_drift = bound.resolve_biome_drift(null, 40, 40, BIOME_DRIFT_AXIS_X)
		TEST_ASSERT(legacy_drift >= -drift_range && legacy_drift <= drift_range, "Unseeded drift left the legacy range with value [legacy_drift].")
		if(legacy_drift != first_legacy_drift)
			legacy_varied = TRUE
	TEST_ASSERT(legacy_varied, "Unseeded drift stopped being random, which would make inherited maps repeat their terrain.")


/// One planet record and optional overmap-cell identity rebuild one complete landscape plan.
/datum/unit_test/rimstation_planet_terrain_fingerprint

/datum/unit_test/rimstation_planet_terrain_fingerprint/Run()
	var/datum/planet_definition/planet = new(PLANET_TEST_SEED)
	var/datum/planet_definition/same_planet = new(PLANET_TEST_SEED)
	var/datum/planet_definition/other_planet = new("[PLANET_TEST_SEED]-elsewhere")
	allocated += planet
	allocated += same_planet
	allocated += other_planet

	var/datum/colony_planet_generator/generator = new(planet)
	var/datum/colony_planet_generator/same_generator = new(same_planet)
	var/datum/colony_planet_generator/other_generator = new(other_planet)
	allocated += generator
	allocated += same_generator
	allocated += other_generator

	var/fingerprint = generator.terrain_fingerprint()
	TEST_ASSERT_NOTNULL(fingerprint, "The colony generator produced no terrain fingerprint.")
	TEST_ASSERT_EQUAL(fingerprint, generator.terrain_fingerprint(), "One generator produced two different fingerprints for the same landscape.")
	TEST_ASSERT_EQUAL(fingerprint, same_generator.terrain_fingerprint(), "An identical planet record produced a different landscape.")
	TEST_ASSERT_NOTEQUAL(fingerprint, other_generator.terrain_fingerprint(), "Two different root seeds produced the same landscape.")
	TEST_ASSERT_NOTEQUAL(fingerprint, generator.terrain_fingerprint(cell_identity = "overmap:12,7"), "Adding a chosen overmap cell did not namespace the landscape plan.")


#undef PLANET_TEST_SEED
