/**
 * A colonist record survives the trip to disk and back unchanged.
 *
 * The record is the only thing standing between a colony and forgetting who built it, and it makes that trip
 * through JSON every chapter. Anything that does not survive encoding is a field the colony silently loses.
 */
/datum/unit_test/rimstation_colonist_record_round_trip

/datum/unit_test/rimstation_colonist_record_round_trip/Run()
	var/datum/colonist_record/record = new("colonist-1-abcd", "Vera Holt", "someckey")
	allocated += record
	record.generation_joined = 2
	record.chapter_joined = 3
	record.chapters_attended = 6
	record.status = COLONIST_STATUS_AWAY
	record.skills = list("/datum/skill/mining" = 900, "/datum/skill/construction" = 250)
	record.home_point = list("x" = 40, "y" = 55, "z" = 2, "bed_type" = "/obj/structure/bed")

	var/datum/colonist_record/restored = new
	allocated += restored
	TEST_ASSERT(restored.deserialize(json_decode(json_encode(record.serialize()))), "A colonist record did not survive a JSON round trip.")

	TEST_ASSERT_EQUAL(restored.colonist_id, record.colonist_id, "A colonist came back with a different id.")
	TEST_ASSERT_EQUAL(restored.display_name, record.display_name, "A colonist came back under a different name.")
	TEST_ASSERT_EQUAL(restored.owner_ckey, record.owner_ckey, "A colonist came back bound to a different player.")
	TEST_ASSERT_EQUAL(restored.generation_joined, record.generation_joined, "A colonist came back from a different generation.")
	TEST_ASSERT_EQUAL(restored.chapter_joined, record.chapter_joined, "A colonist came back having arrived in a different chapter.")
	TEST_ASSERT_EQUAL(restored.chapters_attended, record.chapters_attended, "A colonist came back having lived through a different number of chapters.")
	TEST_ASSERT_EQUAL(restored.status, record.status, "A colonist came back in a different state.")
	TEST_ASSERT_EQUAL(restored.skills["/datum/skill/mining"], 900, "A colonist came back having forgotten a skill.")
	TEST_ASSERT_EQUAL(restored.skills["/datum/skill/construction"], 250, "A colonist came back having forgotten a second skill.")
	TEST_ASSERT_EQUAL(restored.home_point["x"], 40, "A colonist came back without their home point.")
	TEST_ASSERT_EQUAL(restored.home_point["bed_type"], "/obj/structure/bed", "A colonist's home point came back without the bed it names.")


/**
 * A record stores what the campaign decided to store, and nothing else.
 *
 * The whole design rests on the record being thin: preferences own a character's appearance, the round owns
 * their role and their secrets, and the campaign owns only what a player cannot report for themselves. This
 * asserts the field list exactly, so widening it has to be a deliberate act with a reason, rather than
 * something that happens because a var was convenient to reach.
 */
/datum/unit_test/rimstation_colonist_record_stores_only_allowed_fields

/datum/unit_test/rimstation_colonist_record_stores_only_allowed_fields/Run()
	var/datum/colonist_record/record = new("colonist-1-abcd", "Vera Holt", "someckey")
	allocated += record

	var/list/serialized = record.serialize()
	var/list/allowed = COLONIST_RECORD_FIELDS

	for(var/field in serialized)
		TEST_ASSERT(field in allowed, "A colonist record stored '[field]', which is not a field the campaign is allowed to keep. Add it to COLONIST_RECORD_FIELDS deliberately, or stop storing it.")
	for(var/field in allowed)
		TEST_ASSERT(field in serialized, "A colonist record did not store '[field]', which COLONIST_RECORD_FIELDS says it should.")

	// Nothing in a record may be a datum: a stored reference is how a round's secrets and a mob's lifetime leak
	// into a file that outlives both.
	for(var/field in serialized)
		var/value = serialized[field]
		TEST_ASSERT(isnull(value) || istext(value) || isnum(value) || islist(value), "A colonist record stored '[field]' as something other than plain data.")


/// Records come off disk, so a corrupted or hand-edited one must not become a colonist the colony believes in.
/datum/unit_test/rimstation_colonist_record_validation

/datum/unit_test/rimstation_colonist_record_validation/Run()
	var/datum/colonist_record/record = new
	allocated += record

	TEST_ASSERT(!record.deserialize(null), "A null colonist record was accepted.")
	TEST_ASSERT(!record.deserialize(list()), "A record with no id was accepted.")

	var/datum/colonist_record/reference = new("colonist-1-abcd", "Vera Holt", "someckey")
	allocated += reference

	var/list/nameless = reference.serialize()
	nameless["display_name"] = ""
	TEST_ASSERT(!record.deserialize(nameless), "A colonist with no name was accepted.")

	var/list/unknown_status = reference.serialize()
	unknown_status["status"] = "vibing"
	TEST_ASSERT(!record.deserialize(unknown_status), "A colonist in a state the campaign does not have was accepted.")

	// A colonist cannot have attended a negative number of chapters, and a stored count that says so is the
	// kind of thing that turns into a divide-by-zero in a readout three chapters later.
	var/list/impossible_history = reference.serialize()
	impossible_history["chapters_attended"] = -4
	TEST_ASSERT(!record.deserialize(impossible_history), "A colonist who had attended a negative number of chapters was accepted.")

	// Skills come off disk too. A negative or non-numeric entry is dropped rather than restored, because the
	// alternative is a colonist who is worse than untrained at something.
	var/list/bad_skills = reference.serialize()
	bad_skills["skills"] = list("/datum/skill/mining" = -500, "/datum/skill/construction" = "lots", "/datum/skill/fishing" = 300)
	TEST_ASSERT(record.deserialize(bad_skills), "A record with an unusable skill entry was refused outright.")
	TEST_ASSERT(!record.skills["/datum/skill/mining"], "A negative skill value was restored.")
	TEST_ASSERT(!record.skills["/datum/skill/construction"], "A non-numeric skill value was restored.")
	TEST_ASSERT_EQUAL(record.skills["/datum/skill/fishing"], 300, "Dropping unusable skills also dropped a valid one.")
