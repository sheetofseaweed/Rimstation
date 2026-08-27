/**
 * Shared setup for tests that drive SScampaign's roster.
 *
 * These tests run against the live subsystem, because the roster's whole job is to be the thing SScampaign
 * carries between chapters, and a copy of it proves nothing about that. Everything the subsystem owned before
 * the test is put back afterwards, or the next test in the suite inherits a colony it never asked for.
 */
/datum/unit_test/rimstation_colonist_chapter
	abstract_type = /datum/unit_test/rimstation_colonist_chapter
	var/saved_state
	var/datum/campaign_manifest/saved_manifest
	var/datum/colonist_roster/saved_roster
	var/list/saved_seen
	var/list/saved_bodies
	var/saved_seen_chapter
	/// The region and the accounts. Borrowed like the rest, because a test that forms an expedition or spends
	/// the colony's food would otherwise leave both behind for whatever test runs next.
	var/datum/overworld_state/saved_overworld
	var/datum/settlement_ledger/saved_ledger

/// Puts SScampaign on a throwaway campaign with an empty roster, and returns its manifest.
/datum/unit_test/rimstation_colonist_chapter/proc/begin_test_campaign()
	RETURN_TYPE(/datum/campaign_manifest)
	saved_state = SScampaign.campaign_state
	saved_manifest = SScampaign.manifest
	saved_roster = SScampaign.roster
	saved_seen = SScampaign.colonists_seen_this_chapter
	saved_bodies = SScampaign.active_colonist_bodies
	saved_seen_chapter = SScampaign.seen_chapter
	saved_overworld = SScampaign.overworld
	saved_ledger = SScampaign.ledger

	var/datum/campaign_manifest/manifest = new("unit-test-colonists", "generation-1")
	allocated += manifest
	SScampaign.manifest = manifest
	SScampaign.campaign_state = CAMPAIGN_STATE_ACTIVE
	SScampaign.roster = new
	SScampaign.colonists_seen_this_chapter = list()
	SScampaign.active_colonist_bodies = list()
	SScampaign.overworld = null
	SScampaign.ledger = null
	// Null rather than the test's chapter, so the first binding opens a window belonging to this test.
	SScampaign.seen_chapter = null
	return manifest

/datum/unit_test/rimstation_colonist_chapter/Destroy()
	// The roster the test built is the subsystem's now, so it is destroyed here rather than left to leak.
	if(SScampaign.roster != saved_roster)
		QDEL_NULL(SScampaign.roster)
	if(SScampaign.overworld != saved_overworld)
		QDEL_NULL(SScampaign.overworld)
	if(SScampaign.ledger != saved_ledger)
		QDEL_NULL(SScampaign.ledger)
	SScampaign.campaign_state = saved_state
	SScampaign.manifest = saved_manifest
	SScampaign.roster = saved_roster
	SScampaign.colonists_seen_this_chapter = saved_seen
	SScampaign.active_colonist_bodies = saved_bodies
	SScampaign.seen_chapter = saved_seen_chapter
	SScampaign.overworld = saved_overworld
	SScampaign.ledger = saved_ledger
	saved_manifest = null
	saved_roster = null
	saved_seen = null
	saved_bodies = null
	saved_overworld = null
	saved_ledger = null
	return ..()


/**
 * A chapter ends, and the colony writes down who was actually here.
 *
 * This is the whole point of the roster: attendance is the record, and it has to distinguish somebody who
 * played this chapter from somebody who did not without punishing the second. A colonist nobody played must
 * come back later with everything they had - the colony simply did not see them for a while.
 */
/datum/unit_test/rimstation_colonist_chapter/capture

/datum/unit_test/rimstation_colonist_chapter/capture/Run()
	var/datum/campaign_manifest/manifest = begin_test_campaign()
	manifest.chapter = 4

	var/datum/colonist_record/vera = SScampaign.roster.find_or_create("playerone", "Vera Holt", generation_number = 1, chapter = 1)
	vera.chapters_attended = 3
	var/datum/colonist_record/dan = SScampaign.roster.find_or_create("playertwo", "Dan Reyes", generation_number = 1, chapter = 2)
	dan.chapters_attended = 1
	var/datum/colonist_record/sasha = SScampaign.roster.find_or_create("playerthree", "Sasha Ilves", generation_number = 1, chapter = 1)
	sasha.chapters_attended = 2
	sasha.skills = list("/datum/skill/mining" = 900)
	sasha.home_point = list("x" = 12, "y" = 14, "z" = 2, "bed_type" = "/obj/structure/bed")
	sasha.status = COLONIST_STATUS_ACTIVE

	// Two of the three turned up this chapter.
	var/mob/living/carbon/human/vera_body = allocate(/mob/living/carbon/human/consistent)
	var/mob/living/carbon/human/dan_body = allocate(/mob/living/carbon/human/consistent)
	TEST_ASSERT(SScampaign.bind_colonist(vera_body, vera), "A colonist could not be bound to the body playing them.")
	TEST_ASSERT(SScampaign.bind_colonist(dan_body, dan), "A second colonist could not be bound to a body.")

	TEST_ASSERT(SScampaign.capture_roster(), "The colony could not write down who was here this chapter.")

	TEST_ASSERT_EQUAL(vera.status, COLONIST_STATUS_ACTIVE, "A colonist who played this chapter was not recorded as active.")
	TEST_ASSERT_EQUAL(vera.chapters_attended, 4, "A colonist who played this chapter did not have the chapter counted.")
	TEST_ASSERT_EQUAL(dan.chapters_attended, 2, "A second present colonist did not have the chapter counted.")

	TEST_ASSERT_EQUAL(sasha.status, COLONIST_STATUS_AWAY, "A colonist nobody played was not recorded as away.")
	TEST_ASSERT_EQUAL(sasha.chapters_attended, 2, "A colonist nobody played was credited with a chapter they were not in.")
	TEST_ASSERT_EQUAL(sasha.skills["/datum/skill/mining"], 900, "A colonist lost a skill by not being played for a chapter.")
	TEST_ASSERT_NOTNULL(sasha.home_point, "A colonist lost their home by not being played for a chapter.")

	// Capturing has to actually reach the manifest, since that is the only part a commit writes to disk.
	TEST_ASSERT(length(manifest.roster_record), "The chapter's roster was never written into the manifest.")
	var/datum/colonist_roster/from_manifest = new
	allocated += from_manifest
	TEST_ASSERT(from_manifest.deserialize(manifest.roster_record), "The roster written into the manifest could not be read back.")
	TEST_ASSERT_EQUAL(length(from_manifest.records), 3, "The roster written into the manifest is missing colonists.")

	// Capture happens once per chapter, but a commit can be attempted more than once after a failure.
	TEST_ASSERT(SScampaign.capture_roster(), "The colony could not write down its roster a second time.")
	TEST_ASSERT_EQUAL(vera.chapters_attended, 4, "Capturing the roster twice counted the same chapter twice.")


/**
 * Somebody who joined before the chapter formally began still played that chapter.
 *
 * Roundstart colonists are bound during the ticker's equip_characters(), which runs *before* the signal that
 * starts the chapter. A chapter that cleared its attendance on starting would therefore forget everyone who
 * spawned with the round and mark the entire colony absent from a chapter it spent playing. Attendance is
 * keyed on the chapter number instead, so the order these two happen in stops mattering.
 */
/datum/unit_test/rimstation_colonist_chapter/attendance_survives_chapter_start

/datum/unit_test/rimstation_colonist_chapter/attendance_survives_chapter_start/Run()
	var/datum/campaign_manifest/manifest = begin_test_campaign()
	manifest.chapter = 3

	var/datum/colonist_record/vera = SScampaign.roster.find_or_create("playerone", "Vera Holt", generation_number = 1, chapter = 1)
	vera.chapters_attended = 2

	// Bound first, exactly as a roundstart colonist is.
	var/mob/living/carbon/human/vera_body = allocate(/mob/living/carbon/human/consistent)
	TEST_ASSERT(SScampaign.bind_colonist(vera_body, vera), "A colonist could not be bound before the chapter began.")

	// The chapter then formally starts, which is where the attendance window used to be thrown away.
	TEST_ASSERT(SScampaign.restore_roster(), "The chapter could not start after a colonist had already joined.")

	TEST_ASSERT(SScampaign.capture_roster(), "The colony could not write down the chapter.")
	TEST_ASSERT_EQUAL(vera.status, COLONIST_STATUS_ACTIVE, "A colonist who joined before the chapter began was marked absent from it.")
	TEST_ASSERT_EQUAL(vera.chapters_attended, 3, "A colonist who joined before the chapter began was not credited for it.")
	TEST_ASSERT_NOTNULL(SScampaign.get_colonist_body(vera.colonist_id), "Starting the chapter forgot which body was playing a colonist who had already joined.")

	// A genuinely new chapter still starts from nobody, or attendance would accumulate across chapters forever.
	manifest.chapter = 4
	TEST_ASSERT(SScampaign.restore_roster(), "The next chapter could not start.")
	TEST_ASSERT(SScampaign.capture_roster(), "The colony could not write down a chapter nobody played.")
	TEST_ASSERT_EQUAL(vera.status, COLONIST_STATUS_AWAY, "A colonist counted as present in a later chapter they were never bound in.")
	TEST_ASSERT_EQUAL(vera.chapters_attended, 3, "A colonist was credited with a chapter they did not play.")


/**
 * The colony remembers that somebody died, and remembers it from the moment it happened.
 *
 * Death has to be recorded when it happens rather than worked out at the end of the chapter. A body that was
 * gibbed, dusted or otherwise deleted is not there to be inspected at commit time, so a colony that waited
 * until then would quietly lose exactly the deaths that mattered most.
 */
/datum/unit_test/rimstation_colonist_chapter/death_recorded

/datum/unit_test/rimstation_colonist_chapter/death_recorded/Run()
	var/datum/campaign_manifest/manifest = begin_test_campaign()
	manifest.chapter = 2

	var/datum/colonist_record/vera = SScampaign.roster.find_or_create("playerone", "Vera Holt", generation_number = 1, chapter = 1)
	vera.chapters_attended = 1

	var/mob/living/carbon/human/vera_body = allocate(/mob/living/carbon/human/consistent)
	TEST_ASSERT(SScampaign.bind_colonist(vera_body, vera), "A colonist could not be bound to a body.")
	TEST_ASSERT_EQUAL(vera.status, COLONIST_STATUS_ACTIVE, "A colonist was not active while being played.")

	vera_body.death()
	TEST_ASSERT_EQUAL(vera.status, COLONIST_STATUS_DEAD, "A colonist who died was not recorded as dead when it happened.")

	// They were still here for the chapter they died in.
	TEST_ASSERT(SScampaign.capture_roster(), "The colony could not write down a chapter somebody died in.")
	TEST_ASSERT_EQUAL(vera.status, COLONIST_STATUS_DEAD, "Ending the chapter overwrote a colonist's death.")
	TEST_ASSERT_EQUAL(vera.chapters_attended, 2, "A colonist who died was not counted as present for the chapter they died in.")

	// A body that is gone by the end of the chapter must not take the death record with it.
	QDEL_NULL(vera_body)
	TEST_ASSERT(SScampaign.capture_roster(), "The colony could not write down a chapter after a body was deleted.")
	TEST_ASSERT_EQUAL(vera.status, COLONIST_STATUS_DEAD, "A deleted body took its colonist's death record with it.")

	var/datum/colonist_roster/reloaded = new
	allocated += reloaded
	TEST_ASSERT(reloaded.deserialize(json_decode(json_encode(manifest.roster_record))), "A roster containing a dead colonist could not be reloaded.")
	var/datum/colonist_record/vera_reloaded = reloaded.get_record(vera.colonist_id)
	TEST_ASSERT_NOTNULL(vera_reloaded, "A dead colonist was dropped from the roster instead of being remembered.")
	TEST_ASSERT_EQUAL(vera_reloaded.status, COLONIST_STATUS_DEAD, "A dead colonist came back alive after a reload.")


/**
 * A colonist who was away for a chapter is not resurrected, and a dead one is not brought back by absence.
 *
 * The away rule sweeps everybody the chapter did not see, so it has to be the one rule that never touches the
 * dead. Otherwise a colony would forget its dead simply by playing a chapter without them - which is every
 * chapter after the one they died in.
 */
/datum/unit_test/rimstation_colonist_chapter/death_outlives_absence

/datum/unit_test/rimstation_colonist_chapter/death_outlives_absence/Run()
	begin_test_campaign()

	var/datum/colonist_record/dan = SScampaign.roster.find_or_create("playertwo", "Dan Reyes", generation_number = 1, chapter = 1)
	dan.status = COLONIST_STATUS_DEAD
	dan.chapters_attended = 5

	// Nobody is bound at all: this is a chapter played entirely by other people.
	TEST_ASSERT(SScampaign.capture_roster(), "The colony could not write down a chapter its dead were not in.")
	TEST_ASSERT_EQUAL(dan.status, COLONIST_STATUS_DEAD, "A dead colonist was quietly downgraded to merely away.")
	TEST_ASSERT_EQUAL(dan.chapters_attended, 5, "A dead colonist was credited with a chapter they were not alive for.")


/**
 * The roster the chapter starts with is the one the last chapter committed.
 *
 * Restoring is the other half of capture, and the half that decides whether any of this was worth storing.
 */
/datum/unit_test/rimstation_colonist_chapter/restores_at_chapter_start

/datum/unit_test/rimstation_colonist_chapter/restores_at_chapter_start/Run()
	var/datum/campaign_manifest/manifest = begin_test_campaign()

	var/datum/colonist_record/vera = SScampaign.roster.find_or_create("playerone", "Vera Holt", generation_number = 1, chapter = 1)
	vera.chapters_attended = 7
	vera.skills = list("/datum/skill/construction" = 500)
	var/datum/colonist_record/dan = SScampaign.roster.find_or_create("playertwo", "Dan Reyes", generation_number = 1, chapter = 3)
	dan.status = COLONIST_STATUS_DEAD
	var/stored_id = vera.colonist_id

	TEST_ASSERT(SScampaign.capture_roster(), "The colony could not write down its roster.")

	// A new chapter begins: the subsystem throws away the live roster and rebuilds it from what was committed.
	QDEL_NULL(SScampaign.roster)
	SScampaign.colonists_seen_this_chapter = list()
	TEST_ASSERT(SScampaign.restore_roster(), "A chapter could not start from the roster the last one committed.")
	TEST_ASSERT_NOTNULL(SScampaign.roster, "Restoring the roster left the colony without one.")
	TEST_ASSERT_EQUAL(length(SScampaign.roster.records), 2, "A chapter started having forgotten some of the colony.")

	var/datum/colonist_record/vera_restored = SScampaign.roster.get_record(stored_id)
	TEST_ASSERT_NOTNULL(vera_restored, "A colonist did not survive the chapter boundary.")
	TEST_ASSERT_EQUAL(vera_restored.chapters_attended, 7, "A colonist crossed the chapter boundary having forgotten how long they had lived here.")
	TEST_ASSERT_EQUAL(vera_restored.skills["/datum/skill/construction"], 500, "A colonist crossed the chapter boundary having forgotten a skill.")
	TEST_ASSERT_EQUAL(SScampaign.roster.get_record(dan.colonist_id).status, COLONIST_STATUS_DEAD, "A dead colonist came back alive at the start of the next chapter.")

	// The returning player has to be recognised as the same colonist on the far side, not issued a new identity.
	var/datum/colonist_record/recognised = SScampaign.roster.find_or_create("playerone", "Vera Holt", generation_number = 1, chapter = 8)
	TEST_ASSERT_EQUAL(recognised.colonist_id, stored_id, "A returning player was not recognised after the chapter boundary.")

	// A campaign that has never written a roster starts with an empty one rather than refusing to begin.
	QDEL_NULL(SScampaign.roster)
	manifest.roster_record = list()
	TEST_ASSERT(SScampaign.restore_roster(), "A campaign with no roster yet could not start a chapter.")
	TEST_ASSERT_NOTNULL(SScampaign.roster, "A campaign with no roster yet was left without one.")
	TEST_ASSERT(!length(SScampaign.roster.records), "A campaign with no roster yet was given colonists it never had.")
