/**
 * Making a colony single-role must not take any job out of SSjob's lookups.
 *
 * This is the regression test for how the first attempt at this failed. Upstream removes a job outright when a
 * map zeroes both of its position counts, which drops it from `name_occupations` and `type_occupations` as well
 * as the selection pool. Everything that asks for a job by name then gets null, and two callers CRASH on
 * exactly that: set_overflow_role() and setup_officer_positions(). Unit tests passed while the live round threw
 * nine runtimes, so the assertion that matters is not "colonist works" - it is "nothing else broke".
 */
/datum/unit_test/rimstation_colonist_job_keeps_station_jobs_findable

/datum/unit_test/rimstation_colonist_job_keeps_station_jobs_findable/Run()
	// The two the crashing callers ask for by name.
	TEST_ASSERT_NOTNULL(SSjob.get_job(JOB_ASSISTANT), "The assistant job is not findable by name, so set_overflow_role() would CRASH the round.")
	TEST_ASSERT_NOTNULL(SSjob.get_job(JOB_SECURITY_OFFICER), "The security officer job is not findable by name, so setup_officer_positions() would CRASH the round.")
	TEST_ASSERT_NOTNULL(SSjob.get_job_type(SSjob.overflow_role), "The overflow role is not findable by type, so the round could not place a player who got no job.")

	// The colonist job itself has to be a real job the subsystem knows about, whatever map is loaded.
	var/datum/job/colonist/colonist = SSjob.get_job(JOB_COLONIST)
	TEST_ASSERT_NOTNULL(colonist, "The colonist job is not registered with SSjob at all.")
	TEST_ASSERT(istype(colonist), "The job registered under '[JOB_COLONIST]' is not the colonist job.")

	// Every job still resolves both ways round, which is what the removal path broke.
	for(var/datum/job/job as anything in SSjob.all_occupations)
		TEST_ASSERT_NOTNULL(SSjob.get_job(job.title), "Job '[job.title]' is in all_occupations but cannot be found by name.")
		TEST_ASSERT_NOTNULL(SSjob.get_job_type(job.type), "Job '[job.title]' is in all_occupations but cannot be found by type.")


/**
 * Off a colony map, the colonist job is not on the menu - and the station's roster is untouched.
 *
 * The test suite runs on an ordinary map, so this is the negative case: declaring a colonist job must not leak
 * it into every station round, and must not quietly take station jobs away either.
 */
/datum/unit_test/rimstation_colonist_job_hidden_off_colony

/datum/unit_test/rimstation_colonist_job_hidden_off_colony/Run()
	TEST_ASSERT(!is_colonist_only_map(), "The unit test map declares itself a colony, so this test cannot check the station case.")

	var/datum/job/colonist = SSjob.get_job(JOB_COLONIST)
	TEST_ASSERT_NOTNULL(colonist, "The colonist job vanished entirely instead of merely being unavailable.")
	TEST_ASSERT(!(colonist in SSjob.joinable_occupations), "The colonist job is joinable on a map that is not a colony.")

	// The station keeps its own roster. If this fails, the hide rule is inverted somewhere.
	var/datum/job/assistant = SSjob.get_job(JOB_ASSISTANT)
	TEST_ASSERT(assistant in SSjob.joinable_occupations, "Adding a colonist job made the assistant unjoinable on an ordinary station map.")


/**
 * Newcomers walk in from the edge; people who already live here start at the settlement.
 *
 * The distinction is the whole arrival split, and it is drawn from the roster rather than from anything about
 * the player - somebody returning after three chapters away is still a resident.
 */
/datum/unit_test/rimstation_colonist_chapter/arrival_split

/datum/unit_test/rimstation_colonist_chapter/arrival_split/Run()
	begin_test_campaign()

	var/turf/edge_turf = run_loc_floor_bottom_left
	var/obj/effect/landmark/rimstation_colony_spawn/landmark = allocate(/obj/effect/landmark/rimstation_colony_spawn, edge_turf)

	var/datum/colonist_record/newcomer = SScampaign.roster.find_or_create("playerone", "Sasha Ilves", generation_number = 1, chapter = 1)
	TEST_ASSERT_EQUAL(get_colonist_arrival_turf(newcomer, returning = FALSE), get_turf(landmark), "A newcomer did not arrive at the edge landmark.")

	// With no core placed, a returner has nowhere better than the edge, and must not be left in nullspace.
	var/datum/colonist_record/resident = SScampaign.roster.find_or_create("playertwo", "Vera Holt", generation_number = 1, chapter = 1)
	resident.chapters_attended = 4
	TEST_ASSERT_EQUAL(get_colonist_arrival_turf(resident, returning = TRUE), get_turf(landmark), "A returning colonist with no core to go to was not fallen back to the edge landmark.")

	// With a core, a returner starts at the settlement instead.
	var/obj/structure/colony_core/core = allocate(/obj/structure/colony_core, run_loc_floor_top_right)
	var/turf/returner_arrival = get_colonist_arrival_turf(resident, returning = TRUE)
	TEST_ASSERT_NOTNULL(returner_arrival, "A returning colonist was given nowhere to arrive at all.")
	TEST_ASSERT(get_dist(returner_arrival, get_turf(core)) <= 1, "A returning colonist did not arrive at the colony core.")


/**
 * Arriving writes a player into the roster, binds their body, and moves them.
 *
 * One call has to do all three or the halves drift: a colonist who is recorded but not bound is marked absent
 * from a chapter they played, and one who is bound but never recorded is attendance for somebody who does not
 * exist.
 */
/datum/unit_test/rimstation_colonist_chapter/settling_records_and_binds

/datum/unit_test/rimstation_colonist_chapter/settling_records_and_binds/Run()
	var/datum/campaign_manifest/manifest = begin_test_campaign()
	manifest.chapter = 5
	manifest.generation_number = 2

	var/turf/edge_turf = run_loc_floor_bottom_left
	allocate(/obj/effect/landmark/rimstation_colony_spawn, edge_turf)

	var/mob/living/carbon/human/body = allocate(/mob/living/carbon/human/consistent)
	body.real_name = "Vera Holt"

	var/datum/colonist_record/record = settle_colonist(body, "playerone")
	TEST_ASSERT_NOTNULL(record, "Arriving did not put the player into the roster.")
	TEST_ASSERT_EQUAL(record.display_name, "Vera Holt", "A colonist was written down under a different name than the body carried.")
	TEST_ASSERT_EQUAL(record.chapter_joined, 5, "A colonist did not record the chapter they arrived in.")
	TEST_ASSERT_EQUAL(record.generation_joined, 2, "A colonist did not record the generation they arrived in.")
	TEST_ASSERT_EQUAL(record.chapters_attended, 1, "Arriving did not count as attending the chapter.")
	TEST_ASSERT_EQUAL(SScampaign.get_colonist_body(record.colonist_id), body, "Arriving did not bind the body to the colonist playing it.")
	TEST_ASSERT_EQUAL(get_turf(body), edge_turf, "A newcomer was not moved to the edge landmark.")

	// The same player arriving again - a reconnect - is the same colonist, counted once.
	var/mob/living/carbon/human/second_body = allocate(/mob/living/carbon/human/consistent)
	second_body.real_name = "Vera Holt"
	var/datum/colonist_record/again = settle_colonist(second_body, "playerone")
	TEST_ASSERT_EQUAL(again?.colonist_id, record.colonist_id, "A reconnecting player was issued a second colonist identity.")
	TEST_ASSERT_EQUAL(record.chapters_attended, 1, "A reconnecting player was credited with the chapter twice.")
	TEST_ASSERT_EQUAL(length(SScampaign.roster.records), 1, "A reconnecting player added a second record to the roster.")


/// Outside a campaign the colonist job still works; it simply has no colony to file anybody into.
/datum/unit_test/rimstation_colonist_settling_without_a_campaign
	var/saved_state
	var/datum/campaign_manifest/saved_manifest

/datum/unit_test/rimstation_colonist_settling_without_a_campaign/Run()
	saved_state = SScampaign.campaign_state
	saved_manifest = SScampaign.manifest
	SScampaign.manifest = null
	SScampaign.campaign_state = CAMPAIGN_STATE_NONE

	var/mob/living/carbon/human/body = allocate(/mob/living/carbon/human/consistent)
	body.real_name = "Vera Holt"
	var/turf/before = get_turf(body)

	TEST_ASSERT_NULL(settle_colonist(body, "playerone"), "A colonist was filed into a colony that does not exist.")
	TEST_ASSERT_EQUAL(get_turf(body), before, "A round with no campaign moved a player who had nowhere to be moved to.")

/datum/unit_test/rimstation_colonist_settling_without_a_campaign/Destroy()
	SScampaign.campaign_state = saved_state
	SScampaign.manifest = saved_manifest
	saved_manifest = null
	return ..()
