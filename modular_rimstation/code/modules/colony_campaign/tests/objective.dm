/**
 * The core is the colony's legible win condition, so its state machine is the thing a player argues with.
 *
 * Capture has to cost attackers uninterrupted time on the objective. If progress survived them being pushed
 * off, defending would be pointless; if it never accumulated, attacking would be.
 */
/datum/unit_test/rimstation_colony_core_capture

/datum/unit_test/rimstation_colony_core_capture/Run()
	var/obj/structure/colony_core/core = allocate(/obj/structure/colony_core)
	var/capture_duration = core.capture_duration

	TEST_ASSERT_EQUAL(core.state, COLONY_CORE_SECURE, "A fresh colony core did not start secure.")
	TEST_ASSERT_EQUAL(core.capture_progress, 0, "A fresh colony core started with capture progress.")

	// Hostiles present but not yet long enough.
	core.advance_contest(TRUE, capture_duration * 0.5)
	TEST_ASSERT_EQUAL(core.state, COLONY_CORE_CONTESTED, "Hostiles on the core did not contest it.")
	TEST_ASSERT_EQUAL(core.capture_progress, capture_duration * 0.5, "Contest progress did not accumulate.")

	// Pushed off: progress must not bank.
	core.advance_contest(FALSE, capture_duration * 0.5)
	TEST_ASSERT_EQUAL(core.state, COLONY_CORE_SECURE, "Clearing the attackers did not return the core to secure.")
	TEST_ASSERT_EQUAL(core.capture_progress, 0, "Clearing the attackers did not reset capture progress.")

	// A fresh, uninterrupted hold must still take the full duration.
	core.advance_contest(TRUE, capture_duration * 0.9)
	TEST_ASSERT_EQUAL(core.state, COLONY_CORE_CONTESTED, "The core was captured before the full hold elapsed.")
	core.advance_contest(TRUE, capture_duration * 0.1)
	TEST_ASSERT_EQUAL(core.state, COLONY_CORE_CAPTURED, "An uninterrupted hold for the full duration did not capture the core.")

	// Capture is terminal: it must not flicker back to secure when attackers wander off.
	core.advance_contest(FALSE, capture_duration)
	TEST_ASSERT_EQUAL(core.state, COLONY_CORE_CAPTURED, "A captured core reverted once the attackers left.")


/// Losing the core is an explicit event. Nothing about an ordinary round ending may imply it.
/datum/unit_test/rimstation_colony_outcome

/datum/unit_test/rimstation_colony_outcome/Run()
	var/datum/colony_chapter_outcome/outcome = new
	allocated += outcome

	TEST_ASSERT_EQUAL(outcome.result, COLONY_OUTCOME_PENDING, "A chapter outcome did not start pending.")
	TEST_ASSERT(!outcome.is_resolved(), "A pending outcome reported itself as resolved.")

	TEST_ASSERT(outcome.resolve(COLONY_OUTCOME_SUCCESS, "the raid was repelled"), "A pending outcome refused a valid resolution.")
	TEST_ASSERT_EQUAL(outcome.result, COLONY_OUTCOME_SUCCESS, "Resolving the outcome did not record the result.")
	TEST_ASSERT_NOTNULL(outcome.reason, "Resolving the outcome recorded no reason.")
	TEST_ASSERT(outcome.resolved_at > 0, "Resolving the outcome recorded no timestamp.")
	TEST_ASSERT(outcome.is_resolved(), "A resolved outcome still reported itself pending.")

	// First writer wins, so a late round-end cannot overwrite a real result.
	TEST_ASSERT(!outcome.resolve(COLONY_OUTCOME_FAILURE, "round ended"), "A resolved outcome allowed itself to be overwritten.")
	TEST_ASSERT_EQUAL(outcome.result, COLONY_OUTCOME_SUCCESS, "A second resolution changed an already-resolved outcome.")

	var/datum/colony_chapter_outcome/rejected = new
	allocated += rejected
	TEST_ASSERT(!rejected.resolve("nonsense", "bad input"), "An outcome accepted a result outside its own vocabulary.")
	TEST_ASSERT_EQUAL(rejected.result, COLONY_OUTCOME_PENDING, "A rejected resolution still mutated the outcome.")


/// Phase 1 is explicitly non-destructive: a lost chapter must not touch persistence.
/datum/unit_test/rimstation_colony_outcome_non_destructive

/datum/unit_test/rimstation_colony_outcome_non_destructive/Run()
	var/obj/structure/colony_core/core = allocate(/obj/structure/colony_core)
	var/datum/colony_chapter_outcome/outcome = new
	allocated += outcome
	core.chapter_outcome = outcome

	core.advance_contest(TRUE, core.capture_duration)
	TEST_ASSERT_EQUAL(core.state, COLONY_CORE_CAPTURED, "The core did not capture, so the loss path is untested.")
	TEST_ASSERT_EQUAL(outcome.result, COLONY_OUTCOME_FAILURE, "Capturing the core did not record a chapter failure.")

	// The whole point of the phase gate: recording a loss is not the same as enacting one.
	TEST_ASSERT(!outcome.touched_persistence, "A Phase 1 chapter loss reported touching persistent campaign state.")


/// Timers outlive their object unless something cancels them, and a stray capture callback is a phantom loss.
/datum/unit_test/rimstation_colony_core_teardown

/datum/unit_test/rimstation_colony_core_teardown/Run()
	var/obj/structure/colony_core/core = new(run_loc_floor_bottom_left)
	core.advance_contest(TRUE, core.capture_duration * 0.5)
	TEST_ASSERT_EQUAL(core.state, COLONY_CORE_CONTESTED, "The core did not enter its contested state before teardown.")
	TEST_ASSERT(core.alert_timer_id, "A contested core registered no progress alert timer to clean up.")

	var/lingering_timer = core.alert_timer_id
	qdel(core)
	TEST_ASSERT(!timeleft(lingering_timer), "The colony core left a live timer behind after being destroyed.")
