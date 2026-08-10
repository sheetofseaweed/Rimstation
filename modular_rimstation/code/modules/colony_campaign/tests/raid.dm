/**
 * A raid is a budget, not a difficulty number.
 *
 * The colony has to be able to lose a fight it was outmatched in and survive one it prepared for, which only
 * works if the threat that arrives is bounded and knowable. These assertions cover the boundary rather than
 * the flavour: a composition that quietly overspends is a raid nobody could have prepared for.
 */
/datum/unit_test/rimstation_raid_budget

/datum/unit_test/rimstation_raid_budget/Run()
	var/datum/colony_raid/raid = new
	allocated += raid

	var/list/datum/colony_raid_unit/roster = list(
		new /datum/colony_raid_unit(/mob/living/basic/rabbit, 10, 0, 5, "grunt", 5),
		new /datum/colony_raid_unit(/mob/living/basic/chicken, 25, 0, 3, "heavy", 2),
	)
	for(var/datum/colony_raid_unit/unit as anything in roster)
		allocated += unit

	// Run repeatedly: selection is weighted, so a single pass could miss an overspend.
	for(var/attempt in 1 to 40)
		var/list/composition = raid.build_composition(100, roster, 20)
		var/cost = raid.composition_cost(composition, roster)
		TEST_ASSERT(cost <= 100, "A raid composition cost [cost] against a budget of 100 on attempt [attempt].")
		var/head_count = 0
		for(var/mob_type in composition)
			head_count += composition[mob_type]
		TEST_ASSERT(head_count <= 20, "A raid composition fielded [head_count] units against a live cap of 20.")

	// The live cap has to bind even when the budget is effectively unlimited.
	var/list/capped = raid.build_composition(100000, roster, 4)
	var/capped_heads = 0
	for(var/mob_type in capped)
		capped_heads += capped[mob_type]
	TEST_ASSERT_EQUAL(capped_heads, 4, "A rich raid ignored its live cap and fielded [capped_heads] units.")

	// Per-unit maximums cap composition even with budget and headroom to spare.
	for(var/mob_type in capped)
		var/datum/colony_raid_unit/matching
		for(var/datum/colony_raid_unit/unit as anything in roster)
			if(unit.mob_type == mob_type)
				matching = unit
				break
		TEST_ASSERT(capped[mob_type] <= matching.maximum_count, "A raid fielded more [mob_type] than its maximum allows.")

	// Leftover points that cannot buy the cheapest unit must end selection rather than loop.
	var/list/starved = raid.build_composition(9, roster, 20)
	TEST_ASSERT(!length(starved), "A raid that could not afford its cheapest unit still fielded something.")

	// Minimums are honoured when affordable, so a raid never arrives as an empty threat.
	var/datum/colony_raid_unit/mandatory = new /datum/colony_raid_unit(/mob/living/basic/deer, 10, 2, 4, "leader", 1)
	allocated += mandatory
	var/list/with_minimum = raid.build_composition(100, list(mandatory), 20)
	TEST_ASSERT(with_minimum[/mob/living/basic/deer] >= 2, "A raid did not field the minimum count of a required unit.")


/**
 * The lifecycle exists so a raid cannot skip its own telegraph.
 *
 * Warning then assembling then arriving is the preparation window the colony is promised. A raid that could
 * jump straight to assaulting would be exactly the unfair surprise this phase is meant to rule out.
 */
/datum/unit_test/rimstation_raid_states

/datum/unit_test/rimstation_raid_states/Run()
	var/datum/colony_raid/raid = new
	allocated += raid
	TEST_ASSERT_EQUAL(raid.state, COLONY_RAID_QUEUED, "A new raid did not start queued.")

	// The legal forward path, one step at a time.
	var/list/forward_path = list(
		COLONY_RAID_WARNING,
		COLONY_RAID_ASSEMBLING,
		COLONY_RAID_ARRIVING,
		COLONY_RAID_ASSAULTING,
		COLONY_RAID_RETREATING,
		COLONY_RAID_RESOLVED,
	)
	for(var/next_state in forward_path)
		TEST_ASSERT(raid.set_state(next_state), "The raid refused the legal transition to [next_state].")
		TEST_ASSERT_EQUAL(raid.state, next_state, "The raid did not record its transition to [next_state].")

	// Resolved is terminal.
	TEST_ASSERT(!raid.set_state(COLONY_RAID_ASSAULTING), "A resolved raid allowed itself to be restarted.")

	// Skipping the telegraph is the transition that matters most.
	var/datum/colony_raid/skipper = new
	allocated += skipper
	TEST_ASSERT(!skipper.set_state(COLONY_RAID_ASSAULTING), "A queued raid jumped straight to assaulting, skipping its warning.")
	TEST_ASSERT_EQUAL(skipper.state, COLONY_RAID_QUEUED, "A rejected transition still mutated the raid state.")

	// Going backwards is not a thing a raid does.
	var/datum/colony_raid/backslider = new
	allocated += backslider
	backslider.set_state(COLONY_RAID_WARNING)
	backslider.set_state(COLONY_RAID_ASSEMBLING)
	TEST_ASSERT(!backslider.set_state(COLONY_RAID_WARNING), "A raid transitioned backwards to an earlier state.")

	// Cancellation from any state must still be able to reach resolved, or a cancelled raid leaks.
	var/datum/colony_raid/cancelled = new
	allocated += cancelled
	TEST_ASSERT(cancelled.set_state(COLONY_RAID_RESOLVED), "A queued raid could not be cancelled to resolved.")

	// Nonsense states are refused rather than stored.
	var/datum/colony_raid/nonsense = new
	allocated += nonsense
	TEST_ASSERT(!nonsense.set_state("rampaging"), "The raid accepted a state outside its own vocabulary.")


/// A raid with nowhere valid to arrive must cancel, never fall back to spawning inside the settlement.
/datum/unit_test/rimstation_raid_insertion

/datum/unit_test/rimstation_raid_insertion/Run()
	var/datum/colony_raid/raid = new
	allocated += raid

	// The unit test map has no colony landmarks at all, which is exactly the "nowhere valid" case.
	var/list/turf/found = raid.find_insertion_turfs()
	TEST_ASSERT(!length(found), "The raid invented insertion points on a map with no colony landmarks.")

	TEST_ASSERT(!raid.begin_warning(), "A raid with no validated insertion points started anyway.")
	TEST_ASSERT_EQUAL(raid.state, COLONY_RAID_RESOLVED, "A raid that could not deploy did not resolve itself.")
	TEST_ASSERT_EQUAL(raid.outcome, COLONY_RAID_OUTCOME_CANCELLED, "A raid that could not deploy did not record itself as cancelled.")


/// Resolution has to clean up after itself, or a finished raid keeps ticking.
/datum/unit_test/rimstation_raid_resolution

/datum/unit_test/rimstation_raid_resolution/Run()
	var/datum/colony_raid/raid = new
	allocated += raid
	raid.set_state(COLONY_RAID_WARNING)
	raid.assault_timer_id = addtimer(CALLBACK(raid, TYPE_PROC_REF(/datum/colony_raid, begin_assault)), 10 MINUTES, TIMER_STOPPABLE)
	var/lingering_timer = raid.assault_timer_id

	raid.resolve_raid(COLONY_RAID_OUTCOME_REPELLED, "the attackers were killed")
	TEST_ASSERT_EQUAL(raid.state, COLONY_RAID_RESOLVED, "Resolving the raid did not move it to resolved.")
	TEST_ASSERT_EQUAL(raid.outcome, COLONY_RAID_OUTCOME_REPELLED, "Resolving the raid did not record its outcome.")
	TEST_ASSERT(!timeleft(lingering_timer), "A resolved raid left its assault timer running.")

	// First outcome wins, so a late cleanup cannot rewrite how the fight actually went.
	raid.resolve_raid(COLONY_RAID_OUTCOME_CANCELLED, "cleanup")
	TEST_ASSERT_EQUAL(raid.outcome, COLONY_RAID_OUTCOME_REPELLED, "A second resolution overwrote the recorded raid outcome.")
