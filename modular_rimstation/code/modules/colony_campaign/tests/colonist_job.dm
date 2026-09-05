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

	// Every colony role goes with it. The gate reads a flag now, so a role that forgot to set it leaks here.
	for(var/datum/job/job as anything in SSjob.all_occupations)
		if(!job.colony_role)
			continue
		TEST_ASSERT(!(job in SSjob.joinable_occupations), "Colony role '[job.title]' is joinable on a map that is not a colony.")


/**
 * The leader is a colony role with three slots, and its card opens a communications console.
 *
 * The access is the entire point of the job: the console refuses anyone without ACCESS_COMMAND, so an incident
 * asking the colony a question would sit unanswered until it expired.
 */
/datum/unit_test/rimstation_colony_leader_carries_command_access

/datum/unit_test/rimstation_colony_leader_carries_command_access/Run()
	var/datum/job/colony_leader/leader = SSjob.get_job(JOB_COLONY_LEADER)
	TEST_ASSERT_NOTNULL(leader, "The colony leader job is not registered with SSjob at all.")
	TEST_ASSERT(istype(leader), "The job registered under '[JOB_COLONY_LEADER]' is not the colony leader job.")
	TEST_ASSERT(leader.colony_role, "The colony leader is not marked as a colony role, so a station round would offer it.")
	TEST_ASSERT_EQUAL(leader.total_positions, 3, "The colony leader does not have three slots.")
	TEST_ASSERT_EQUAL(leader.spawn_positions, 3, "The colony leader does not have three roundstart slots.")

	var/datum/id_trim/job/colony_leader/trim = SSid_access.trim_singletons_by_path[/datum/id_trim/job/colony_leader]
	TEST_ASSERT_NOTNULL(trim, "The colony leader trim has no singleton, so no card can ever be stamped with it.")
	TEST_ASSERT(ACCESS_COMMAND in trim.access, "The colony leader trim does not grant ACCESS_COMMAND, so a communications console will not log them in.")

	// The console checks its own req_access, so ask a real one rather than re-deriving what it wants.
	var/obj/machinery/computer/communications/console = allocate(/obj/machinery/computer/communications)
	var/obj/item/card/id/advanced/card = allocate(/obj/item/card/id/advanced)
	SSid_access.apply_trim_to_card(card, /datum/id_trim/job/colony_leader)
	TEST_ASSERT(console.check_access(card), "A colony leader's card was refused by a communications console.")


/**
 * A promoted colonist collecting last chapter's card gets this chapter's rank written onto it.
 *
 * Their stored card was stamped whenever they last put it away, so somebody elected between chapters would
 * otherwise come back holding a colonist's card and find the console shut to them.
 */
/datum/unit_test/rimstation_colony_leader_restamps_stored_card

/datum/unit_test/rimstation_colony_leader_restamps_stored_card/Run()
	var/mob/living/carbon/human/consistent/leader = allocate(/mob/living/carbon/human/consistent)
	leader.mind_initialize()
	leader.mind.assigned_role = SSjob.get_job(JOB_COLONY_LEADER)
	// A card only reaches the ID slot on somebody wearing a uniform, and that slot is where collection puts it.
	leader.equip_to_appropriate_slot(new /obj/item/clothing/under/color/grey)

	// What they stored last chapter: their own card, carrying a colonist's access.
	var/obj/item/card/id/advanced/stored = allocate(/obj/item/card/id/advanced)
	SSid_access.apply_trim_to_card(stored, /datum/id_trim/job/assistant)
	var/list/colonist_access = stored.access.Copy()
	TEST_ASSERT(!(ACCESS_COMMAND in colonist_access), "An assistant-trimmed card already carried ACCESS_COMMAND, so this test proves nothing.")
	TEST_ASSERT(leader.equip_to_appropriate_slot(stored), "The test could not put a stored card into the colonist's ID slot.")

	TEST_ASSERT(stamp_colony_leader_access(leader), "Collecting a stored card did not re-stamp it for a leader with no command access.")
	TEST_ASSERT(ACCESS_COMMAND in stored.access, "A re-stamped card still does not open a communications console.")
	TEST_ASSERT(!stamp_colony_leader_access(leader), "A card that already carries command access was re-stamped a second time.")

	// Applying a trim clears the card first, so the leader trim has to be a superset of the colonist one.
	for(var/access in colonist_access)
		TEST_ASSERT(access in stored.access, "Re-stamping a card took away access '[access]' the colonist already had.")


/// An ordinary colonist collecting their things is left alone; the stamp reads the job, not the roster.
/datum/unit_test/rimstation_colonist_card_is_not_promoted

/datum/unit_test/rimstation_colonist_card_is_not_promoted/Run()
	var/mob/living/carbon/human/consistent/colonist = allocate(/mob/living/carbon/human/consistent)
	colonist.mind_initialize()
	colonist.mind.assigned_role = SSjob.get_job(JOB_COLONIST)
	colonist.equip_to_appropriate_slot(new /obj/item/clothing/under/color/grey)

	var/obj/item/card/id/advanced/stored = allocate(/obj/item/card/id/advanced)
	SSid_access.apply_trim_to_card(stored, /datum/id_trim/job/assistant)
	TEST_ASSERT(colonist.equip_to_appropriate_slot(stored), "The test could not put a stored card into the colonist's ID slot.")

	TEST_ASSERT(!stamp_colony_leader_access(colonist), "A plain colonist was handed command access for collecting their own things.")
	TEST_ASSERT(!(ACCESS_COMMAND in stored.access), "A plain colonist's card came out of storage able to open a communications console.")


/**
 * The whole path a returning leader actually walks: empty the stash, then use the console.
 *
 * Asserted against a real collection rather than against the stamp alone, because a returner is undressed when
 * they arrive and the card only reaches a slot the console reads if the uniform is put on first.
 */
/datum/unit_test/rimstation_colony_leader_collects_a_working_card

/datum/unit_test/rimstation_colony_leader_collects_a_working_card/Run()
	var/mob/living/carbon/human/consistent/leader = allocate(/mob/living/carbon/human/consistent)
	leader.mind_initialize()
	leader.mind.assigned_role = SSjob.get_job(JOB_COLONY_LEADER)

	// What the colony kept for them: last chapter's clothes and last chapter's card.
	var/obj/structure/closet/colonist_storage/stash/stash = allocate(/obj/structure/closet/colonist_storage/stash)
	var/obj/item/card/id/advanced/stored = new(stash)
	SSid_access.apply_trim_to_card(stored, /datum/id_trim/job/assistant)
	new /obj/item/clothing/under/color/grey(stash)
	new /obj/item/clothing/shoes/workboots(stash)

	TEST_ASSERT(return_colonist_belongings(stash, leader), "A leader collected nothing at all out of the colony stash.")

	var/obj/machinery/computer/communications/console = allocate(/obj/machinery/computer/communications)
	var/obj/item/card/id/carried = leader.get_idcard(hand_first = FALSE)
	TEST_ASSERT_NOTNULL(carried, "A leader who emptied the stash is not carrying an ID card anywhere the console looks.")
	TEST_ASSERT(console.check_access(carried), "A leader collected their belongings and still cannot log into a communications console.")


/**
 * Somebody joining mid-chapter is built on the planet, not on the hub the rest of the fork latejoins to.
 *
 * settle_colonist() moves every arrival anyway, so this is only about where the body is made. It matters
 * because that move needs a roster to look the player up in: a round with no campaign has none, and without
 * this the latejoiner is left standing on a z-level with no way to reach the colony.
 */
/datum/unit_test/rimstation_colony_jobs_latejoin_on_the_planet

/datum/unit_test/rimstation_colony_jobs_latejoin_on_the_planet/Run()
	var/obj/effect/landmark/rimstation_colony_spawn/landmark = allocate(/obj/effect/landmark/rimstation_colony_spawn, run_loc_floor_bottom_left)

	for(var/datum/job/job as anything in SSjob.all_occupations)
		if(!job.colony_role)
			continue
		TEST_ASSERT_EQUAL(job.get_latejoin_spawn_point(), landmark, "Colony role '[job.title]' latejoins somewhere other than the colony's own landmark.")

	// A station job on the same map is untouched; this must not redirect the whole roster.
	var/datum/job/assistant = SSjob.get_job(JOB_ASSISTANT)
	TEST_ASSERT_NOTNULL(assistant, "The assistant job is missing, so this test cannot check the station case.")
	TEST_ASSERT(assistant.get_latejoin_spawn_point() != landmark, "A station job was sent to the colony's landmark.")


/// With no landmark placed, a colony job falls back to the ordinary latejoin point rather than to nowhere.
/datum/unit_test/rimstation_colony_jobs_latejoin_falls_back

/datum/unit_test/rimstation_colony_jobs_latejoin_falls_back/Run()
	TEST_ASSERT(!length(GLOB.rimstation_colony_spawns), "A colony spawn landmark outlived the test that made it, so the fallback cannot be checked.")

	var/datum/job/colonist = SSjob.get_job(JOB_COLONIST)
	TEST_ASSERT_NOTNULL(colonist, "The colonist job is missing entirely.")
	TEST_ASSERT_NOTNULL(colonist.get_latejoin_spawn_point(), "With no colony landmark placed, a colonist had nowhere at all to latejoin to.")


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
