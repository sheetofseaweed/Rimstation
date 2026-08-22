/**
 * The storyteller can buy a raid, and a raid is what it gets.
 *
 * Raids were startable only from an admin verb, which meant the colony's central threat was the one thing the
 * storyteller could not pace. Making a raid an incident hands it the budget, the tracks, the repetition
 * weighting and the recovery rule that every other colony event already goes through.
 */
/datum/unit_test/campaign_failure_path/rimstation_raid_is_a_threat_incident

/datum/unit_test/campaign_failure_path/rimstation_raid_is_a_threat_incident/Run()
	test_campaign_id = "unit-test-raid-category"
	take_campaign()
	TEST_ASSERT(SScampaign.create_campaign(test_campaign_id, "admin-key"), "A campaign could not be created.")

	// The category has to be one the storyteller can actually buy, and it has to lead to a raid.
	var/list/categories = COLONY_INCIDENT_CATEGORIES
	TEST_ASSERT(COLONY_INCIDENT_CATEGORY_THREAT in categories, "Threat is not a category the storyteller can schedule.")

	var/list/eligible = SScampaign.get_eligible_incident_types(COLONY_INCIDENT_CATEGORY_THREAT)
	TEST_ASSERT(length(eligible), "The threat category offers the storyteller nothing to buy, so it would spend points on nothing.")
	TEST_ASSERT(/datum/colony_incident/raid in eligible, "A raid is not among the threats the storyteller can schedule.")

	// Every category needs a control, or the category exists and nothing ever reaches it. Asked of the live
	// instances SSevents built rather than of the typepaths: initial() returns nothing at all for a list var,
	// so reading tags off a path would silently report that the control carries none.
	var/datum/round_event_control/colony_incident/threat_control
	for(var/datum/round_event_control/colony_incident/control in SSevents.control)
		if(control.incident_category == COLONY_INCIDENT_CATEGORY_THREAT)
			threat_control = control
			break

	TEST_ASSERT_NOTNULL(threat_control, "No storyteller control schedules the threat category, so nothing ever reaches it.")
	TEST_ASSERT(TAG_DESTRUCTIVE in threat_control.tags, "The raid control is not tagged destructive, so a recovering colony would still be raided.")
	TEST_ASSERT_EQUAL(threat_control.typepath, /datum/round_event/colony_incident, "The threat control does not run a colony incident.")


/**
 * A raid incident refuses when a raid is already happening.
 *
 * Two raids at once is not twice the story. They compete for the same insertion points and the same core, and
 * the colony cannot tell which attack it is losing to.
 */
/datum/unit_test/campaign_failure_path/rimstation_raid_incident_refuses_to_double_up

/datum/unit_test/campaign_failure_path/rimstation_raid_incident_refuses_to_double_up/Run()
	test_campaign_id = "unit-test-raid-double"
	take_campaign()
	TEST_ASSERT(SScampaign.create_campaign(test_campaign_id, "admin-key"), "A campaign could not be created.")

	var/obj/structure/colony_core/core = allocate(/obj/structure/colony_core)
	TEST_ASSERT_NOTNULL(core, "The test needs a colony core for a raid to aim at.")

	var/datum/colony_incident/raid/incident = new
	allocated += incident
	TEST_ASSERT(incident.can_begin(), "A raid incident refused to begin against a colony with a core and no raid running.")

	// A raid that exists but has not resolved blocks another.
	var/datum/colony_raid/running = new
	allocated += running
	TEST_ASSERT(is_colony_raid_running(), "A live raid did not register as running.")
	TEST_ASSERT(!incident.can_begin(), "A second raid was scheduled while one was already happening.")

	// Once it is over, the way is clear again.
	running.resolve_raid(COLONY_RAID_OUTCOME_REPELLED, "the test said so")
	TEST_ASSERT(!is_colony_raid_running(), "A resolved raid still counted as running, so no raid could ever be scheduled again.")
	TEST_ASSERT(incident.can_begin(), "A colony that had survived a raid could never be raided again.")


/// A raid that finishes finishes its incident with it, rather than leaving the carrier to time out and call it ignored.
/datum/unit_test/campaign_failure_path/rimstation_raid_incident_follows_its_raid

/datum/unit_test/campaign_failure_path/rimstation_raid_incident_follows_its_raid/Run()
	test_campaign_id = "unit-test-raid-follows"
	take_campaign()
	TEST_ASSERT(SScampaign.create_campaign(test_campaign_id, "admin-key"), "A campaign could not be created.")

	var/datum/colony_incident/raid/incident = new
	allocated += incident
	var/datum/colony_raid/carried = new
	allocated += carried

	// Wire them up the way execute() does, without needing the raid to actually deploy.
	incident.raid = carried
	incident.RegisterSignal(carried, COMSIG_COLONY_RAID_RESOLVED, TYPE_PROC_REF(/datum/colony_incident/raid, on_raid_resolved))
	incident.set_state(COLONY_INCIDENT_WARNING)
	incident.set_state(COLONY_INCIDENT_ACTIVE)

	carried.resolve_raid(COLONY_RAID_OUTCOME_REPELLED, "the settlement held")
	TEST_ASSERT(incident.is_finished(), "An incident carrying a finished raid was still running.")
	TEST_ASSERT_EQUAL(incident.result?.outcome, COLONY_INCIDENT_OUTCOME_SUCCEEDED, "Repelling a raid was not recorded as the colony succeeding.")

	// The active window has to outlast a real raid, or the carrier resolves it as ignored mid-fight.
	TEST_ASSERT(incident.active_duration > 10 MINUTES, "A raid incident's active window is shorter than a raid, so it would be called ignored while still being fought.")


/**
 * A raid finds the core on its own, however it was started.
 *
 * Everything a raid does hangs off its objective: the waypoint chain ends there, the contesting faction is
 * registered on it, and the capture clock only advances while it resolves. A raid built without one still
 * deploys and still walks - it simply has nowhere to walk to and nothing it can take, which reads in game as
 * attackers standing around at their landing site and a core that will not fall. That is far too quiet a
 * failure to leave to whoever writes the next thing that starts a raid.
 */
/datum/unit_test/rimstation_raid_finds_its_objective

/datum/unit_test/rimstation_raid_finds_its_objective/Run()
	var/obj/structure/colony_core/core = allocate(/obj/structure/colony_core)
	TEST_ASSERT_EQUAL(get_colony_core(), core, "The test's colony core is not the one a raid would find.")

	// A raid nobody handed an objective to.
	var/datum/colony_raid/unaimed = new
	allocated += unaimed
	TEST_ASSERT_NULL(unaimed.objective_ref, "A fresh raid already had an objective, so this proves nothing.")

	unaimed.begin_warning()
	TEST_ASSERT_NOTNULL(unaimed.objective_ref?.resolve(), "A raid started without an objective never found one, so its attackers would have nowhere to go and nothing to take.")
	TEST_ASSERT_EQUAL(unaimed.objective_ref.resolve(), core, "A raid aimed at something other than the colony core.")

	// An objective handed in is left alone.
	var/datum/colony_raid/aimed = new
	allocated += aimed
	aimed.objective_ref = WEAKREF(core)
	aimed.begin_warning()
	TEST_ASSERT_EQUAL(aimed.objective_ref.resolve(), core, "A raid given an objective had it replaced.")


/**
 * A finished raid stops marching.
 *
 * Survivors keep their own AI and will still defend themselves, but they stop walking at an objective that is
 * no longer theirs to take. It also stops queued pathfinding outliving the fight - a travel destination is a
 * turf, move loops do not watch turfs for deletion, and a generation reset deletes every turf on the map.
 */
/datum/unit_test/rimstation_raid_stands_down_on_resolve

/datum/unit_test/rimstation_raid_stands_down_on_resolve/Run()
	var/datum/colony_raid/raid = new
	allocated += raid

	var/mob/living/basic/trooper/pirate/melee/rimstation_raider/attacker = allocate(/mob/living/basic/trooper/pirate/melee/rimstation_raider)
	TEST_ASSERT_NOTNULL(attacker.ai_controller, "The test's raider has no AI controller to give orders to.")

	raid.roster += WEAKREF(attacker)
	attacker.ai_controller.set_blackboard_key(BB_TRAVEL_DESTINATION, run_loc_floor_top_right)
	TEST_ASSERT_NOTNULL(attacker.ai_controller.blackboard[BB_TRAVEL_DESTINATION], "The test could not give a raider somewhere to march.")

	raid.resolve_raid(COLONY_RAID_OUTCOME_REPELLED, "the settlement held")
	TEST_ASSERT_NULL(attacker.ai_controller.blackboard[BB_TRAVEL_DESTINATION], "A raider was still marching at the colony after the raid it belonged to had ended.")

	// The mob is left alive and still able to think for itself; only its orders are gone.
	TEST_ASSERT(!QDELETED(attacker), "Ending a raid deleted a surviving attacker instead of standing it down.")
	TEST_ASSERT_NOTNULL(attacker.ai_controller, "Standing an attacker down took away the AI it needs to defend itself.")


/// A raid with nothing to attack refuses to happen, rather than landing attackers who can never achieve anything.
/datum/unit_test/rimstation_raid_without_a_core_refuses

/datum/unit_test/rimstation_raid_without_a_core_refuses/Run()
	TEST_ASSERT_NULL(get_colony_core(), "A colony core exists in this test, so a coreless raid cannot be tested.")

	var/datum/colony_raid/pointless = new
	allocated += pointless
	TEST_ASSERT(!pointless.begin_warning(), "A raid deployed against a colony that has no core.")
	TEST_ASSERT_EQUAL(pointless.outcome, COLONY_RAID_OUTCOME_CANCELLED, "A raid with nothing to attack was not cancelled.")


/**
 * A raid is whole before anyone volunteers, and stays whole if nobody does.
 *
 * The point of the zero-volunteer rule is that the storyteller can schedule a raid without knowing whether
 * anybody is watching. A colony must never be safer because the server is empty, and a volunteer must never
 * make the attack bigger - they replace a unit that was already coming.
 */
/datum/unit_test/rimstation_raid_ghost_slots

/datum/unit_test/rimstation_raid_ghost_slots/Run()
	var/datum/colony_raid/raid = new
	allocated += raid

	var/mob/living/basic/trooper/pirate/melee/rimstation_raider/attacker = allocate(/mob/living/basic/trooper/pirate/melee/rimstation_raider)
	TEST_ASSERT_NOTNULL(attacker.ai_controller, "A raider was built without the AI that fights when nobody volunteers.")

	// Recorded before the offer rather than compared against a constant: an idle test room legitimately parks
	// AI controllers, so the claim being made here is "offering a unit changes nothing about it", not "the AI
	// is running right now".
	var/status_before = attacker.ai_controller.ai_status

	TEST_ASSERT(raid.offer_to_ghosts(attacker), "A raider could not be offered to ghosts.")
	TEST_ASSERT_NOTNULL(attacker.GetComponent(/datum/component/ghost_direct_control), "An offered raider cannot actually be claimed by a ghost.")

	// The unit is exactly the attacker it was before being offered - that is what makes volunteers optional.
	TEST_ASSERT_NOTNULL(attacker.ai_controller, "Offering a raider to ghosts took away the AI that fights when nobody comes.")
	TEST_ASSERT_EQUAL(attacker.ai_controller.ai_status, status_before, "Offering a raider to ghosts changed its AI state, so an unclaimed raider would behave differently for having been offered.")

	// Claiming moves a unit between the columns; it never adds one.
	raid.telemetry.ai_units = 4
	raid.telemetry.controlled_units = 0
	raid.on_attacker_claimed(attacker)
	TEST_ASSERT_EQUAL(raid.telemetry.controlled_units, 1, "Taking over a raider was not recorded.")
	TEST_ASSERT_EQUAL(raid.telemetry.ai_units, 3, "Taking over a raider did not take it out of the AI count, so the raid would report more attackers than it had.")
	TEST_ASSERT_EQUAL(raid.telemetry.ai_units + raid.telemetry.controlled_units, 4, "A volunteer changed the size of the raid.")

	// The count cannot go negative, however many hands a unit passes through.
	raid.telemetry.ai_units = 0
	raid.on_attacker_claimed(attacker)
	TEST_ASSERT_EQUAL(raid.telemetry.ai_units, 0, "A raid reported a negative number of AI attackers.")


/**
 * A colony that falls to a raid says which raid took it.
 *
 * The chapter outcome has carried a raid id and its telemetry since the beginning, and nothing ever passed
 * them - so a campaign could record that it had been lost, but not to what. A defeat nobody can attribute is a
 * defeat nobody can learn from.
 */
/datum/unit_test/campaign_failure_path/rimstation_core_loss_names_its_raid

/datum/unit_test/campaign_failure_path/rimstation_core_loss_names_its_raid/Run()
	test_campaign_id = "unit-test-raid-attribution"
	take_campaign()
	TEST_ASSERT(SScampaign.create_campaign(test_campaign_id, "admin-key"), "A campaign could not be created.")

	// A core lost with no raid running blames nobody, which is the honest record for a fire or an accident.
	var/obj/structure/colony_core/unattacked = allocate(/obj/structure/colony_core)
	TEST_ASSERT(unattacked.record_chapter_loss("the test burned it down"), "A colony core could not report its own loss.")

	var/datum/colony_chapter_outcome/accident = SScampaign.chapter_outcome
	TEST_ASSERT_EQUAL(accident.result, COLONY_OUTCOME_FAILURE, "A destroyed core did not lose the chapter.")
	TEST_ASSERT_NULL(accident.raid_id, "A colony that burned down blamed a raid that never happened.")

	// A fresh chapter, this time with an attacker.
	SScampaign.chapter_outcome = new
	allocated += SScampaign.chapter_outcome

	var/datum/colony_raid/attacker = new
	allocated += attacker
	var/obj/structure/colony_core/besieged = allocate(/obj/structure/colony_core)
	TEST_ASSERT(besieged.record_chapter_loss("the colony core was captured"), "A besieged core could not report its loss.")

	var/datum/colony_chapter_outcome/lost = SScampaign.chapter_outcome
	TEST_ASSERT_EQUAL(lost.raid_id, attacker.raid_id, "A colony lost to a raid could not say which raid took it.")
	TEST_ASSERT_EQUAL(lost.telemetry, attacker.telemetry, "A lost chapter kept no record of how the raid that took it went.")

	// A raid that has already finished is not blamed for a later loss.
	SScampaign.chapter_outcome = new
	allocated += SScampaign.chapter_outcome
	attacker.resolve_raid(COLONY_RAID_OUTCOME_REPELLED, "driven off")

	var/obj/structure/colony_core/afterwards = allocate(/obj/structure/colony_core)
	TEST_ASSERT(afterwards.record_chapter_loss("something else entirely"), "A core could not report a loss after a raid had ended.")
	TEST_ASSERT_NULL(SScampaign.chapter_outcome.raid_id, "A raid that had already been driven off was blamed for a later loss.")


/**
 * A scheduled raid grows with the colony and eases off after the colony has been hurt.
 *
 * The budget reuses the storyteller's recovery figure rather than inventing a second measure of how battered
 * the settlement is - two competing answers to that question is how pacing systems start fighting each other.
 */
/datum/unit_test/campaign_failure_path/rimstation_raid_budget_tracks_the_colony

/datum/unit_test/campaign_failure_path/rimstation_raid_budget_tracks_the_colony/Run()
	test_campaign_id = "unit-test-raid-budget"
	take_campaign()
	TEST_ASSERT(SScampaign.create_campaign(test_campaign_id, "admin-key"), "A campaign could not be created.")

	var/datum/colony_story_state/story = SScampaign.get_story_state()
	TEST_ASSERT_NOTNULL(story, "The campaign has no story state, so a raid budget cannot be derived from one.")

	story.campaign_age = 0
	story.recovery = 0
	var/first_chapter = SScampaign.get_raid_threat_budget()
	TEST_ASSERT(first_chapter > 0, "A first-chapter raid was worth nothing at all.")

	story.campaign_age = 6
	var/veteran = SScampaign.get_raid_threat_budget()
	TEST_ASSERT(veteran > first_chapter, "A colony that had survived six chapters was raided no harder than a new one.")

	// However old it gets, there is a ceiling.
	story.campaign_age = 500
	TEST_ASSERT_EQUAL(SScampaign.get_raid_threat_budget(), COLONY_RAID_MAX_BUDGET, "An old colony's raid budget ran away past its cap.")

	// A battered colony is hit more gently, but never by nothing.
	story.campaign_age = 6
	story.recovery = 100
	var/battered = SScampaign.get_raid_threat_budget()
	TEST_ASSERT(battered < veteran, "A colony still recovering was raided just as hard as one at full strength.")
	TEST_ASSERT(battered > 0, "A recovering colony's raid was reduced to nothing, which is a cancelled raid pretending to be one.")
