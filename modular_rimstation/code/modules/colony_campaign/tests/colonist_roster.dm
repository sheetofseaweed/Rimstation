/**
 * The roster recognises a returning colonist and refuses to confuse two different ones.
 *
 * Identity is looked up by player and character name together, because neither is enough alone: one player may
 * play several colonists, and two players may pick the same name. The id the roster issues is what everything
 * else keys on, so getting this wrong means a colonist inherits someone else's history.
 */
/datum/unit_test/rimstation_colonist_roster_identity

/datum/unit_test/rimstation_colonist_roster_identity/Run()
	var/datum/colonist_roster/roster = new
	allocated += roster

	var/datum/colonist_record/vera = roster.find_or_create("playerone", "Vera Holt", generation_number = 1, chapter = 1)
	TEST_ASSERT_NOTNULL(vera, "The roster would not admit a new colonist.")
	TEST_ASSERT_NOTNULL(vera.colonist_id, "A colonist was admitted without an id.")
	TEST_ASSERT_EQUAL(vera.chapter_joined, 1, "A colonist did not record the chapter they arrived in.")

	var/datum/colonist_record/vera_again = roster.find_or_create("playerone", "Vera Holt", generation_number = 1, chapter = 4)
	TEST_ASSERT_EQUAL(vera_again.colonist_id, vera.colonist_id, "A returning colonist was issued a second identity instead of being recognised.")
	TEST_ASSERT_EQUAL(vera_again.chapter_joined, 1, "Recognising a returning colonist overwrote the chapter they originally arrived in.")
	TEST_ASSERT_EQUAL(length(roster.records), 1, "Recognising a returning colonist added a second record.")

	// Same name, different player: two people who happen to have picked the same name are still two people.
	var/datum/colonist_record/impostor = roster.find_or_create("playertwo", "Vera Holt", generation_number = 1, chapter = 4)
	TEST_ASSERT(impostor.colonist_id != vera.colonist_id, "Two different players sharing a character name were treated as one colonist.")

	// Same player, different character: one player may live in the colony as more than one person.
	var/datum/colonist_record/second_character = roster.find_or_create("playerone", "Dan Reyes", generation_number = 1, chapter = 4)
	TEST_ASSERT(second_character.colonist_id != vera.colonist_id, "One player's second character was mistaken for their first.")
	TEST_ASSERT_EQUAL(length(roster.records), 3, "The roster does not hold the three colonists it was given.")

	// Names arrive from a text field, so they arrive with whatever spacing and capitalisation a player typed.
	var/datum/colonist_record/sloppily_typed = roster.find_or_create("playerone", "  vera holt ", generation_number = 1, chapter = 5)
	TEST_ASSERT_EQUAL(sloppily_typed.colonist_id, vera.colonist_id, "A returning colonist was not recognised because their name was typed with different spacing or capitalisation.")
	TEST_ASSERT_EQUAL(sloppily_typed.display_name, "Vera Holt", "Recognising a colonist overwrote the name they are known by with the way it was typed this time.")


/**
 * A roster survives the trip to disk and back with every colonist intact.
 *
 * This is the trip that matters: the roster is stored inside the manifest, which is read and rewritten every
 * chapter. A roster that loses a colonist on the way through loses them permanently.
 */
/datum/unit_test/rimstation_colonist_roster_round_trip

/datum/unit_test/rimstation_colonist_roster_round_trip/Run()
	var/datum/colonist_roster/roster = new
	allocated += roster

	var/datum/colonist_record/vera = roster.find_or_create("playerone", "Vera Holt", generation_number = 1, chapter = 1)
	vera.chapters_attended = 5
	vera.skills = list("/datum/skill/mining" = 900)
	var/datum/colonist_record/dan = roster.find_or_create("playertwo", "Dan Reyes", generation_number = 1, chapter = 3)
	dan.status = COLONIST_STATUS_DEAD

	var/datum/colonist_roster/restored = new
	allocated += restored
	TEST_ASSERT(restored.deserialize(json_decode(json_encode(roster.serialize()))), "A roster did not survive a JSON round trip.")
	TEST_ASSERT_EQUAL(length(restored.records), 2, "A roster came back holding a different number of colonists.")

	var/datum/colonist_record/vera_restored = restored.get_record(vera.colonist_id)
	TEST_ASSERT_NOTNULL(vera_restored, "A colonist was lost on the way through disk.")
	TEST_ASSERT_EQUAL(vera_restored.chapters_attended, 5, "A restored colonist forgot how long they had lived here.")
	TEST_ASSERT_EQUAL(vera_restored.skills["/datum/skill/mining"], 900, "A restored colonist forgot a skill.")

	var/datum/colonist_record/dan_restored = restored.get_record(dan.colonist_id)
	TEST_ASSERT_NOTNULL(dan_restored, "A dead colonist was dropped from the roster instead of being remembered.")
	TEST_ASSERT_EQUAL(dan_restored.status, COLONIST_STATUS_DEAD, "A dead colonist came back in a different state.")

	// The lookup has to work on the far side too, or a returning player is issued a new identity every reboot.
	var/datum/colonist_record/found_again = restored.find_or_create("playerone", "Vera Holt", generation_number = 1, chapter = 6)
	TEST_ASSERT_EQUAL(found_again.colonist_id, vera.colonist_id, "A colonist was not recognised after their roster was reloaded.")
	TEST_ASSERT_EQUAL(length(restored.records), 2, "Recognising a reloaded colonist added a duplicate record.")

	// Issuing ids must not restart from one after a reload, or the next colonist collides with the first.
	var/datum/colonist_record/newcomer = restored.find_or_create("playerthree", "Sasha Ilves", generation_number = 1, chapter = 6)
	TEST_ASSERT_NULL(roster.get_record(newcomer.colonist_id), "A colonist admitted after a reload was issued an id that already belonged to someone else.")


/// A roster is a set of distinct people, and a record naming an id that is already taken cannot join it.
/datum/unit_test/rimstation_colonist_roster_rejects_duplicates

/datum/unit_test/rimstation_colonist_roster_rejects_duplicates/Run()
	var/datum/colonist_roster/roster = new
	allocated += roster

	var/datum/colonist_record/first = new("colonist-1-abcd", "Vera Holt", "playerone")
	TEST_ASSERT(roster.add_record(first), "The roster refused a valid colonist.")

	var/datum/colonist_record/collision = new("colonist-1-abcd", "Dan Reyes", "playertwo")
	allocated += collision
	TEST_ASSERT(!roster.add_record(collision), "The roster accepted a second colonist claiming an id it had already issued.")
	TEST_ASSERT_EQUAL(length(roster.records), 1, "A rejected colonist was added to the roster anyway.")
	TEST_ASSERT_EQUAL(roster.get_record("colonist-1-abcd").display_name, "Vera Holt", "A rejected colonist overwrote the one already holding their id.")

	// The same has to hold for a record arriving off disk, which is where a hand-edited file would come in.
	var/list/stored = roster.serialize()
	var/list/duplicated_entry = stored["records"][1].Copy()
	stored["records"] += list(duplicated_entry)

	var/datum/colonist_roster/loaded = new
	allocated += loaded
	TEST_ASSERT(loaded.deserialize(stored), "A roster carrying a duplicate record was refused outright instead of dropping the duplicate.")
	TEST_ASSERT_EQUAL(length(loaded.records), 1, "A duplicated colonist was loaded twice.")


/**
 * The manifest carries the roster, and a campaign written before it existed still loads.
 *
 * Every campaign currently on disk predates the roster. Migration is what stops "the colony now remembers its
 * people" from meaning "the colony you already have can no longer be opened".
 */
/datum/unit_test/rimstation_colonist_roster_in_manifest

/datum/unit_test/rimstation_colonist_roster_in_manifest/Run()
	var/datum/campaign_manifest/manifest = new("unit-test-roster", "generation-1")
	allocated += manifest

	var/datum/colonist_roster/roster = new
	allocated += roster
	var/datum/colonist_record/vera = roster.find_or_create("playerone", "Vera Holt", generation_number = 1, chapter = 1)
	manifest.roster_record = roster.serialize()

	var/datum/campaign_manifest/reloaded = new
	allocated += reloaded
	TEST_ASSERT(reloaded.deserialize(json_decode(json_encode(manifest.serialize()))), "A manifest carrying a roster could not be reloaded.")

	var/datum/colonist_roster/from_manifest = new
	allocated += from_manifest
	TEST_ASSERT(from_manifest.deserialize(reloaded.roster_record), "A roster stored in a manifest could not be read back out of it.")
	TEST_ASSERT_NOTNULL(from_manifest.get_record(vera.colonist_id), "A colonist did not survive being carried inside a manifest.")

	// A campaign written before the roster existed arrives with an empty one rather than being refused.
	var/list/older_campaign = manifest.serialize()
	older_campaign["schema_version"] = 4
	older_campaign -= "roster_record"

	var/datum/campaign_manifest/migrated = new
	allocated += migrated
	TEST_ASSERT(migrated.deserialize(older_campaign), "A campaign from before the roster existed could no longer be loaded.")
	TEST_ASSERT_EQUAL(migrated.schema_version, CAMPAIGN_MANIFEST_SCHEMA_VERSION, "Loading an older campaign did not bring it up to the current schema.")
	TEST_ASSERT_NOTNULL(migrated.roster_record, "A migrated campaign has no roster field at all.")
	TEST_ASSERT(!length(migrated.roster_record), "A campaign from before the roster existed was given colonists it never had.")
