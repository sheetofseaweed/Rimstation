/**
 * A concrete incident that exists only to exercise the contract.
 *
 * Real incidents arrive with Task 5. Until then this is the only non-abstract type, which is deliberate: the
 * contract can be tested without pretending content exists, and the storyteller controls stay unbuyable
 * because no *production* incident is eligible yet.
 */
/datum/colony_incident/unit_test_stub
	name = "test incident"
	category = COLONY_INCIDENT_CATEGORY_NEUTRAL
	warning_duration = 10 SECONDS
	/// Set when execute() runs, so a test can tell an incident that arrived from one that only announced.
	var/executed = FALSE

/datum/colony_incident/unit_test_stub/announce_warning()
	// Silent: a test should not shout at the whole server.
	return TRUE

/datum/colony_incident/unit_test_stub/execute()
	executed = TRUE
	return TRUE

/datum/colony_incident/unit_test_stub/build_result(datum/colony_incident_result/building)
	building.add_consequence("the test incident happened")
	building.add_reward("test reward")
	building.record_telemetry("executed", executed)
	return TRUE


/**
 * No incident is destroyed before the round begins.
 *
 * The tag index builds one of every incident type and throws them away, and it used to do that while the
 * global lists were still being built. The garbage collector stamps a queue entry with the `world.time` it was
 * made at, and `create_and_destroy` waits for the queue to drain past its own start time - so an entry stamped
 * with almost nothing is one it can never wait out. Seven of them cost that test its whole 50 minute budget.
 */
/datum/unit_test/rimstation_incidents_not_destroyed_before_roundstart

/datum/unit_test/rimstation_incidents_not_destroyed_before_roundstart/Run()
	// Nothing reaches the garbage collector this early unless it was destroyed during global variable init.
	var/before_the_round_began = 5 SECONDS

	for(var/list/queue as anything in SSgarbage.queues)
		for(var/list/packet as anything in queue)
			if(length(packet) < GC_QUEUE_ITEM_INDEX_COUNT)
				continue
			var/queued_at = packet[GC_QUEUE_ITEM_QUEUE_TIME]
			if(queued_at > before_the_round_began)
				continue
			var/datum/queued = packet[GC_QUEUE_ITEM_REF]
			if(!istype(queued, /datum/colony_incident))
				continue
			TEST_FAIL("[queued.type] was destroyed at world.time [queued_at], before the round started. It will sit at the head of the garbage queue all round and stall create_and_destroy.")


/**
 * An incident goes through its states in order, and cannot skip the warning.
 *
 * The warning window is the colony's chance to prepare, so an incident that could jump straight to active
 * would turn a story into a punishment. The order is enforced rather than trusted.
 */
/datum/unit_test/campaign_failure_path/rimstation_colony_incident_lifecycle
	test_campaign_id = "unit-test-incident"

/datum/unit_test/campaign_failure_path/rimstation_colony_incident_lifecycle/Run()
	take_campaign()
	TEST_ASSERT(SScampaign.create_campaign(test_campaign_id, "admin-key"), "A campaign could not be created.")

	var/datum/colony_incident/unit_test_stub/incident = new
	allocated += incident
	TEST_ASSERT_EQUAL(incident.state, COLONY_INCIDENT_QUEUED, "A new incident did not start queued.")
	TEST_ASSERT_NOTNULL(incident.id, "An incident has no id to record against.")

	// The warning cannot be skipped.
	TEST_ASSERT(!incident.set_state(COLONY_INCIDENT_ACTIVE), "An incident jumped straight to active, skipping the colony's warning.")
	TEST_ASSERT(!incident.set_state(COLONY_INCIDENT_RESOLVED), "An incident jumped straight to resolved.")
	TEST_ASSERT_EQUAL(incident.state, COLONY_INCIDENT_QUEUED, "A refused transition still moved the incident.")

	TEST_ASSERT(incident.begin_warning(), "An incident refused to begin its warning.")
	TEST_ASSERT_EQUAL(incident.state, COLONY_INCIDENT_WARNING, "Beginning the warning did not enter the warning state.")
	TEST_ASSERT(!incident.executed, "An incident acted during its warning window.")

	TEST_ASSERT(incident.begin_active(), "An incident refused to begin.")
	TEST_ASSERT_EQUAL(incident.state, COLONY_INCIDENT_ACTIVE, "Beginning did not enter the active state.")
	TEST_ASSERT(incident.executed, "An active incident never did anything.")

	TEST_ASSERT(incident.begin_resolving(), "An incident refused to begin resolving.")
	TEST_ASSERT(incident.resolve(COLONY_INCIDENT_OUTCOME_SUCCEEDED, 2), "An incident refused to resolve.")
	TEST_ASSERT_EQUAL(incident.state, COLONY_INCIDENT_RESOLVED, "A resolved incident is not in the resolved state.")
	TEST_ASSERT(incident.is_finished(), "A resolved incident does not report itself finished.")

	// Resolving twice would pay the rewards twice.
	TEST_ASSERT(!incident.resolve(COLONY_INCIDENT_OUTCOME_FAILED, 5), "An incident resolved a second time.")
	TEST_ASSERT_EQUAL(incident.result.outcome, COLONY_INCIDENT_OUTCOME_SUCCEEDED, "A second resolution overwrote the first.")
	TEST_ASSERT_EQUAL(incident.result.pressure_change, 2, "A second resolution overwrote the recorded pressure.")

	// And a finished incident cannot be cancelled out from under its own result.
	TEST_ASSERT(!incident.cancel("too late"), "A resolved incident was cancelled afterwards.")

	// The result carries what the pacing state will read later.
	TEST_ASSERT_NOTNULL(incident.result, "A resolved incident produced no result.")
	TEST_ASSERT_EQUAL(incident.result.incident_id, incident.id, "A result does not name the incident that produced it.")
	TEST_ASSERT(length(incident.result.consequences), "A result recorded no consequences.")
	TEST_ASSERT(length(incident.result.rewards), "A result recorded no rewards.")
	TEST_ASSERT(incident.result.telemetry["executed"], "A result recorded no telemetry.")

	// An unknown outcome is refused rather than stored.
	var/datum/colony_incident/unit_test_stub/nonsense = new
	allocated += nonsense
	TEST_ASSERT(!nonsense.resolve("went sideways"), "An incident accepted an outcome outside its vocabulary.")
	TEST_ASSERT_NULL(nonsense.result, "A refused resolution still produced a result.")


/**
 * Cancelling an incident gives back everything it was holding.
 *
 * Reservations are the reason cancellation has to be explicit: an incident interrupted halfway would otherwise
 * leave the colony's money held against something that never happened, with nothing left to release it.
 */
/datum/unit_test/campaign_failure_path/rimstation_colony_incident_cancellation
	test_campaign_id = "unit-test-incident-cancel"

/datum/unit_test/campaign_failure_path/rimstation_colony_incident_cancellation/Run()
	take_campaign()
	TEST_ASSERT(SScampaign.create_campaign(test_campaign_id, "admin-key"), "A campaign could not be created.")

	var/datum/bank_account/account = get_settlement_account()
	TEST_ASSERT_NOTNULL(account, "The settlement has no account to reserve against.")
	account.account_balance = 1000
	SScampaign.get_ledger().capture_from(account)
	SScampaign.adjust_resource("iron", 100, LEDGER_CATEGORY_SALVAGE, "starting stock", null, null)

	var/datum/colony_incident/unit_test_stub/incident = new
	allocated += incident
	TEST_ASSERT(incident.begin_warning(), "An incident refused to begin its warning.")

	TEST_ASSERT(incident.reserve_credits(300, "held for a trade"), "An incident could not reserve credits the colony had.")
	TEST_ASSERT_EQUAL(account.account_balance, 700, "Reserving credits did not take them out of the account.")
	TEST_ASSERT(incident.reserve_resource("iron", 40, "held for a trade"), "An incident could not reserve materials the colony had.")
	TEST_ASSERT_EQUAL(SScampaign.get_ledger().get_resource("iron"), 60, "Reserving materials did not take them out of the store.")

	// Reserving what the colony does not have changes nothing.
	TEST_ASSERT(!incident.reserve_credits(99999, "held for a moon"), "An incident reserved credits the colony did not have.")
	TEST_ASSERT(!incident.reserve_resource("iron", 9999, "held for a mountain"), "An incident reserved materials the colony did not have.")
	TEST_ASSERT_EQUAL(account.account_balance, 700, "A refused reservation still moved money.")

	TEST_ASSERT(incident.cancel("the test cancelled it"), "An incident refused to cancel.")
	TEST_ASSERT_EQUAL(incident.state, COLONY_INCIDENT_CANCELLED, "A cancelled incident is not in the cancelled state.")
	TEST_ASSERT_EQUAL(account.account_balance, 1000, "Cancelling did not give back the credits it was holding.")
	TEST_ASSERT_EQUAL(SScampaign.get_ledger().get_resource("iron"), 100, "Cancelling did not give back the materials it was holding.")

	// Cancellation is not a result: nothing happened, so there is nothing for pacing to learn from.
	TEST_ASSERT_NULL(incident.result, "A cancelled incident produced a result.")
	TEST_ASSERT(!incident.cancel("again"), "A cancelled incident was cancelled twice.")

	// Every movement, in and back out, is in the ledger.
	var/datum/settlement_ledger/settlement = SScampaign.get_ledger()
	var/incident_entries = 0
	for(var/list/entry as anything in settlement.entries)
		if(entry["related_id"] == incident.id)
			incident_entries++
	TEST_ASSERT_EQUAL(incident_entries, 4, "The ledger holds [incident_entries] entries for the incident's two reservations and their return.")


/**
 * The storyteller only buys an incident category the campaign can actually deliver.
 *
 * An incident control that could be bought while no incident of its category exists would spend the
 * storyteller's points on an event that does nothing, which is the failure this whole bridge exists to avoid.
 */
/datum/unit_test/campaign_failure_path/rimstation_colony_incident_storyteller_bridge
	test_campaign_id = "unit-test-incident-bridge"

/datum/unit_test/campaign_failure_path/rimstation_colony_incident_storyteller_bridge/Run()
	take_campaign()

	// Outside a campaign, nothing is eligible and nothing can be built.
	var/datum/round_event_control/colony_incident/neutral/control = new
	allocated += control
	TEST_ASSERT(!control.can_spawn_storyteller_event(50), "A colony incident was buyable with no campaign running.")
	TEST_ASSERT_EQUAL(control.preRunEvent(), EVENT_CANT_RUN, "A colony incident event agreed to run with no campaign.")
	TEST_ASSERT(!length(SScampaign.get_eligible_incident_types(COLONY_INCIDENT_CATEGORY_NEUTRAL)), "Incidents were eligible with no campaign running.")
	TEST_ASSERT_NULL(SScampaign.create_incident(COLONY_INCIDENT_CATEGORY_NEUTRAL), "An incident was created with no campaign running.")

	TEST_ASSERT(SScampaign.create_campaign(test_campaign_id, "admin-key"), "A campaign could not be created.")

	// With a campaign, the category carrying the test incident can be delivered.
	var/list/neutral_types = SScampaign.get_eligible_incident_types(COLONY_INCIDENT_CATEGORY_NEUTRAL)
	TEST_ASSERT(/datum/colony_incident/unit_test_stub in neutral_types, "The test incident was not eligible for its own category.")

	var/datum/colony_incident/built = SScampaign.create_incident(COLONY_INCIDENT_CATEGORY_NEUTRAL)
	TEST_ASSERT_NOTNULL(built, "The campaign could not build an incident for a category that has one.")
	TEST_ASSERT_EQUAL(built.category, COLONY_INCIDENT_CATEGORY_NEUTRAL, "The campaign built an incident of the wrong category.")
	TEST_ASSERT(built in SScampaign.active_incidents, "A running incident is not tracked as active.")
	built.cancel("test cleanup")
	TEST_ASSERT(!(built in SScampaign.active_incidents), "A cancelled incident is still tracked as active.")

	// A category with nothing behind it refuses rather than firing an empty event. Tested against a category
	// that does not exist, so this keeps holding as real categories gain content.
	TEST_ASSERT(!length(SScampaign.get_eligible_incident_types("a category nobody has written")), "An unknown category reported incidents as eligible.")
	var/datum/round_event_control/colony_incident/empty_control = new
	allocated += empty_control
	empty_control.incident_category = "a category nobody has written"
	TEST_ASSERT(!empty_control.can_spawn_storyteller_event(50), "A category with no incidents behind it was buyable.")
	TEST_ASSERT_EQUAL(empty_control.preRunEvent(), EVENT_CANT_RUN, "A category with no incidents agreed to run.")

	// There is one control per category, and each names a real one.
	var/list/categories = COLONY_INCIDENT_CATEGORIES
	var/list/seen = list()
	for(var/datum/round_event_control/colony_incident/control_type as anything in subtypesof(/datum/round_event_control/colony_incident))
		var/incident_category = initial(control_type.incident_category)
		TEST_ASSERT(incident_category in categories, "Incident control [control_type] schedules '[incident_category]', which is not a category.")
		TEST_ASSERT(!seen[incident_category], "Two incident controls schedule the '[incident_category]' category.")
		seen[incident_category] = TRUE
	TEST_ASSERT_EQUAL(length(seen), length(categories), "There is not one incident control for each of the [length(categories)] categories.")


/// An incident's result survives being written into the campaign's history.
/datum/unit_test/campaign_failure_path/rimstation_colony_incident_history
	test_campaign_id = "unit-test-incident-history"

/datum/unit_test/campaign_failure_path/rimstation_colony_incident_history/Run()
	take_campaign()
	TEST_ASSERT(SScampaign.create_campaign(test_campaign_id, "admin-key"), "A campaign could not be created.")
	SScampaign.incident_history = null

	var/datum/colony_incident/unit_test_stub/incident = new
	allocated += incident
	incident.begin_warning()
	incident.begin_active()
	incident.begin_resolving()
	TEST_ASSERT(incident.resolve(COLONY_INCIDENT_OUTCOME_SUCCEEDED, 3), "The incident refused to resolve.")

	TEST_ASSERT_EQUAL(length(SScampaign.incident_history), 1, "A resolved incident was not filed in the campaign's history.")
	var/list/filed = SScampaign.incident_history[1]
	TEST_ASSERT_EQUAL(filed["incident_id"], incident.id, "The filed result does not name its incident.")
	TEST_ASSERT_EQUAL(filed["outcome"], COLONY_INCIDENT_OUTCOME_SUCCEEDED, "The filed result lost its outcome.")
	TEST_ASSERT_EQUAL(filed["pressure_change"], 3, "The filed result lost how much pressure it added.")

	// It is plain values, so it survives being written down and read back.
	var/list/round_tripped = json_decode(json_encode(filed))
	TEST_ASSERT_EQUAL(round_tripped["outcome"], COLONY_INCIDENT_OUTCOME_SUCCEEDED, "An incident result did not survive a JSON round trip.")

	// A cancelled incident files nothing, because nothing happened.
	var/datum/colony_incident/unit_test_stub/abandoned = new
	allocated += abandoned
	abandoned.begin_warning()
	abandoned.cancel("nobody engaged")
	TEST_ASSERT_EQUAL(length(SScampaign.incident_history), 1, "A cancelled incident was filed as though it had happened.")
