/**
 * Campaign time has to be one number, and it has to be the same number everywhere.
 *
 * The clock is derived from two immutable origins rather than counted up, so these drive the real lifecycle -
 * chapters starting, snapshots, commits, defeat, a new generation - and read the clock the way the rest of the
 * campaign reads it. Elapsed time is simulated by moving an origin backwards rather than by sleeping, because
 * what is under test is the derivation, and a test that waited two hours of world time to prove it would take
 * two hours.
 */
/datum/unit_test/campaign_failure_path/rimstation_campaign_clock_is_derived
	test_campaign_id = "unit-test-clock-derived"

/datum/unit_test/campaign_failure_path/rimstation_campaign_clock_is_derived/Run()
	take_campaign()

	// Before anything is played there is no chapter contributing time, so the stored clock is the whole answer.
	TEST_ASSERT_EQUAL(SScampaign.get_campaign_time(), 0, "The campaign clock read something before any campaign existed.")

	TEST_ASSERT(SScampaign.create_campaign(test_campaign_id, "admin-key"), "A campaign could not be created.")
	TEST_ASSERT_NOTNULL(SScampaign.chapter_clock_origin, "Starting a chapter did not start the campaign clock.")
	TEST_ASSERT_NOTNULL(SScampaign.chapter_world_time_origin, "The campaign clock has no world time to measure against.")
	TEST_ASSERT_EQUAL(SScampaign.get_campaign_time(), 0, "A brand new campaign did not begin at zero.")

	// Ten minutes of chapter, simulated by moving the origin back rather than by waiting for it.
	SScampaign.chapter_world_time_origin -= 6000
	TEST_ASSERT_EQUAL(SScampaign.get_campaign_time(), 6000, "The live clock is not the stored clock plus the time this chapter has been running.")

	// Syncing copies; it must never rebase. Two syncs in a row are the cheapest way to prove it, because a
	// rebasing sync would fold the elapsed time in twice and read 12000 here.
	SScampaign.sync_campaign_time()
	TEST_ASSERT_EQUAL(SScampaign.manifest.campaign_clock, 6000, "Syncing did not write the live clock into the manifest.")
	SScampaign.sync_campaign_time()
	TEST_ASSERT_EQUAL(SScampaign.manifest.campaign_clock, 6000, "Syncing twice counted the same elapsed time twice.")
	TEST_ASSERT_EQUAL(SScampaign.get_campaign_time(), 6000, "Syncing moved the live clock, so the origins were rebased.")

	// And it keeps running afterwards from the same origin rather than from the value just written.
	SScampaign.chapter_world_time_origin -= 3000
	TEST_ASSERT_EQUAL(SScampaign.get_campaign_time(), 9000, "The clock stopped advancing after being synced.")

	// A world time that appears to have gone backwards must not run the campaign's history backwards with it:
	// entries would stamp before ones already written, and the clock would fail the manifest's own validation.
	SScampaign.chapter_world_time_origin = world.time + 5000
	TEST_ASSERT_EQUAL(SScampaign.get_campaign_time(), SScampaign.chapter_clock_origin, "A backwards world time delta ran the campaign clock backwards.")
	TEST_ASSERT(SScampaign.get_campaign_time() >= 0, "The campaign clock went negative, which the manifest would refuse to validate.")


/// Everything that stamps a moment has to stamp the live one, not whatever the last write happened to store.
/datum/unit_test/campaign_failure_path/rimstation_campaign_clock_stamps_records
	test_campaign_id = "unit-test-clock-stamps"

/datum/unit_test/campaign_failure_path/rimstation_campaign_clock_stamps_records/Run()
	take_campaign()
	TEST_ASSERT(SScampaign.create_campaign(test_campaign_id, "admin-key"), "A campaign could not be created.")

	SScampaign.chapter_world_time_origin -= 4500
	TEST_ASSERT_EQUAL(SScampaign.manifest.campaign_clock, 0, "The stored clock moved without anything syncing it, so this proves nothing.")

	// The ledger is the case this was built for: entries are written continuously, and almost never at the
	// moment of a commit, so a stored clock would stamp an entire chapter's accounts with the same reading.
	// Bounded, not exact: this is a running clock, and the work between rewinding the origin and reading the
	// entry back is real work that can cross a tick. What is being tested is that the entry took the live
	// reading rather than the stored zero, so the window is what separates those two answers.
	TEST_ASSERT(SScampaign.adjust_resource("food", 5, LEDGER_CATEGORY_SALVAGE, "gathered", null, null), "A resource change was refused.")
	var/datum/settlement_ledger/settlement = SScampaign.get_ledger()
	var/list/entry = settlement.entries[length(settlement.entries)]
	TEST_ASSERT(entry["campaign_clock"] >= 4500, "A ledger entry was stamped with the stored clock instead of the live one.")
	TEST_ASSERT(entry["campaign_clock"] < 4500 + 10 SECONDS, "A ledger entry was stamped far beyond the live clock.")
	TEST_ASSERT(entry["campaign_clock"] > SScampaign.manifest.campaign_clock, "A ledger entry read the stored clock, which has not been synced since the chapter began.")

	// A snapshot is a picture of now, so it carries the live clock - and promotes nothing while doing it.
	var/before_snapshot = SScampaign.manifest.active_checkpoint_id
	SScampaign.chapter_world_time_origin -= 1500
	TEST_ASSERT(SScampaign.create_snapshot("clock-snapshot", "admin-key"), "A snapshot could not be written.")
	TEST_ASSERT(SScampaign.manifest.campaign_clock >= 6000, "A snapshot did not carry the live campaign clock.")
	TEST_ASSERT(SScampaign.manifest.campaign_clock < 6000 + 10 SECONDS, "A snapshot carried a clock far beyond the live one.")
	TEST_ASSERT_EQUAL(SScampaign.manifest.active_checkpoint_id, before_snapshot, "A snapshot promoted itself.")


/// Time is the one thing that survives a chapter ending, a reload, and a colony being lost entirely.
/datum/unit_test/campaign_failure_path/rimstation_campaign_clock_outlives_chapters
	test_campaign_id = "unit-test-clock-outlives"

/datum/unit_test/campaign_failure_path/rimstation_campaign_clock_outlives_chapters/Run()
	take_campaign()
	TEST_ASSERT(SScampaign.create_campaign(test_campaign_id, "admin-key"), "A campaign could not be created.")

	SScampaign.chapter_world_time_origin -= 7200
	TEST_ASSERT(SScampaign.resolve_chapter_at_round_end(), "The chapter could not be resolved.")

	// Bounded rather than exact, because committing is real work that takes real time and the clock is a clock:
	// it keeps running while the checkpoint is written. What matters is that it stored this chapter's elapsed
	// time rather than zero, and that it did not leap - so the window is the commit's own duration.
	var/committed = SScampaign.manifest.campaign_clock
	TEST_ASSERT(committed >= 7200, "A commit stored less than the time the chapter had been running, so the chapter's elapsed time was lost.")
	TEST_ASSERT(committed < 7200 + 10 SECONDS, "A commit stored a clock far beyond the chapter's elapsed time.")

	// On disk, because that is the copy the next boot reads. A clock kept only in memory is a clock reset by
	// every reboot, and the campaign would never get older than one round.
	var/datum/campaign_manifest/on_disk = load_active_campaign_manifest(test_campaign_id)
	allocated += on_disk
	TEST_ASSERT_NOTNULL(on_disk, "The committed campaign was not written to disk.")
	TEST_ASSERT_EQUAL(on_disk.campaign_clock, committed, "The campaign clock did not reach disk, so a reboot would restart it.")

	// Boot the way the subsystem does. The next chapter has to resume from the committed reading rather than
	// from zero, and rather than from wherever this server's world time happens to be.
	SScampaign.campaign_state = CAMPAIGN_STATE_NONE
	SScampaign.manifest = null
	SScampaign.chapter_clock_origin = null
	SScampaign.chapter_world_time_origin = null
	TEST_ASSERT_EQUAL(SScampaign.get_campaign_time(), 0, "The clock read the previous chapter's time with no campaign loaded.")

	TEST_ASSERT(SScampaign.begin_load(on_disk), "The committed campaign could not be loaded.")
	TEST_ASSERT_EQUAL(SScampaign.get_campaign_time(), committed, "A loaded campaign did not report the clock it was committed on.")
	TEST_ASSERT(SScampaign.begin_chapter(), "The next chapter could not be started.")
	TEST_ASSERT_EQUAL(SScampaign.chapter_clock_origin, committed, "The next chapter did not take the committed clock as its floor.")

	SScampaign.chapter_world_time_origin -= 1800
	var/second_chapter = SScampaign.get_campaign_time()
	TEST_ASSERT(second_chapter >= committed + 1800, "The second chapter's time did not add to the first's.")

	// Defeat records the moment the generation ended, and then the campaign carries its age onto the new one.
	// The colony is gone; how long this has been going on is still true.
	TEST_ASSERT(SScampaign.declare_defeat("the core was destroyed"), "The generation could not be closed.")
	TEST_ASSERT(SScampaign.manifest.campaign_clock >= second_chapter, "Defeat did not record the clock the generation closed on.")
	var/at_defeat = SScampaign.manifest.campaign_clock

	TEST_ASSERT(SScampaign.begin_next_generation("the colony was lost"), "A new generation could not be opened.")
	TEST_ASSERT_EQUAL(SScampaign.manifest.generation_number, 2, "A new generation was not opened.")
	TEST_ASSERT(SScampaign.manifest.campaign_clock >= at_defeat, "A new generation restarted the campaign clock, losing how old the campaign is.")
	TEST_ASSERT(SScampaign.manifest.campaign_clock >= committed + 1800, "A new generation lost the time the previous one was played for.")
