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

#undef PLANET_TEST_SEED
