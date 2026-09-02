/**
 * The content table behind journey decisions.
 *
 * These validate *instantiated* datums, never `initial(typepath.list_var)` - that returns nothing for list vars
 * in DM, so a test written the obvious way would read every archetype as declaring no choices at all and pass
 * for the worst possible reason.
 *
 * The rule each archetype has to keep is the one that stops travel deadlocking: whatever the party's state,
 * however poor or short-handed, at least one choice must remain takeable. A decision with no affordable answer
 * is a caravan that stands in a field forever.
 */
/datum/unit_test/rimstation_overworld_decisions
	abstract_type = /datum/unit_test/rimstation_overworld_decisions


/// Every archetype declares what an interface needs to draw it and what an answer needs to match.
/datum/unit_test/rimstation_overworld_decisions/table_is_complete

/datum/unit_test/rimstation_overworld_decisions/table_is_complete/Run()
	var/list/table = GLOB.overworld_decisions
	TEST_ASSERT(length(table) >= 3, "The decision table did not build. Travel would have nothing to offer.")

	var/list/seen_ids = list()
	for(var/decision_id in table)
		var/datum/overworld_decision/archetype = table[decision_id]
		TEST_ASSERT_NOTNULL(archetype, "The decision table holds an entry with nothing behind it.")

		// Identity, and that it is filed under the id it thinks it has.
		TEST_ASSERT(istext(archetype.id) && archetype.id, "A decision archetype has no id, so no answer could ever match it.")
		TEST_ASSERT_EQUAL(archetype.id, decision_id, "A decision archetype is filed under an id that is not its own.")
		TEST_ASSERT(!(archetype.id in seen_ids), "Two decision archetypes share an id.")
		seen_ids += archetype.id

		// What a player reads before deciding.
		TEST_ASSERT(istext(archetype.name) && archetype.name, "A decision archetype has no name to show.")
		TEST_ASSERT(istext(archetype.reveal_text) && archetype.reveal_text, "A decision archetype says nothing about what the party is looking at.")

		// Choices, and copy for every one of them. A choice with no label is a blank button.
		TEST_ASSERT(length(archetype.choice_ids) >= 2, "A decision archetype offers fewer than two choices, which is not a decision.")
		for(var/choice_id in archetype.choice_ids)
			TEST_ASSERT(istext(choice_id) && choice_id, "A decision archetype declares a choice with no id.")
			var/list/copy = archetype.choice_copy[choice_id]
			TEST_ASSERT(islist(copy) && length(copy) >= 2, "Choice '[choice_id]' of '[archetype.id]' has no label and detail.")
			TEST_ASSERT(istext(copy[1]) && copy[1], "Choice '[choice_id]' of '[archetype.id]' has no label.")
			TEST_ASSERT(istext(copy[2]) && copy[2], "Choice '[choice_id]' of '[archetype.id]' does not say what it costs.")

		// Nothing in the copy table that is not an actual choice, which would show a button nothing accepts.
		for(var/choice_id in archetype.choice_copy)
			TEST_ASSERT(choice_id in archetype.choice_ids, "'[archetype.id]' has copy for '[choice_id]', which is not one of its choices.")

	// The three the campaign ships. A missing one is content that silently stopped existing.
	TEST_ASSERT_NOTNULL(get_overworld_decision(OVERWORLD_DECISION_WEATHER), "The weather archetype is missing.")
	TEST_ASSERT_NOTNULL(get_overworld_decision(OVERWORLD_DECISION_SPOOR), "The predator archetype is missing.")
	TEST_ASSERT_NOTNULL(get_overworld_decision(OVERWORLD_DECISION_SMOKE), "The smoke archetype is missing.")


/**
 * Whatever the party's situation, there is always something it can do.
 *
 * The deadlock this prevents is specific: a party with no rations, nobody online and nothing left to discover
 * meets a decision, every choice is filtered out as unaffordable, and the caravan stands there forever with an
 * unanswerable question. Each archetype keeps one choice that costs nothing but time.
 */
/datum/unit_test/rimstation_colonist_chapter/overworld_decisions_always_answerable

/datum/unit_test/rimstation_colonist_chapter/overworld_decisions_always_answerable/Run()
	begin_test_campaign()
	SScampaign.overworld = new(default_overworld_options())
	SScampaign.ledger = new
	var/datum/overworld_region/region = get_active_overworld_region()
	SScampaign.overworld.reveal_initial(region)

	var/datum/overworld_party/party = SScampaign.form_party()
	TEST_ASSERT_NOTNULL(party, "An expedition could not be formed.")

	// The worst case the game can produce: on the road, out of food, and nobody online to act.
	party.route = region.plan_route("0,0", "2,0", OVERWORLD_ROUTE_FASTEST)
	party.current_cell = party.route[1]
	party.next_leg_index = 2
	party.supplies = 0
	party.set_state(OVERWORLD_PARTY_DEPARTING, "test")
	party.set_state(OVERWORLD_PARTY_OUTBOUND, "test")

	var/blocked = party.leg_target_cell()
	for(var/decision_id in GLOB.overworld_decisions)
		var/datum/overworld_decision/archetype = GLOB.overworld_decisions[decision_id]
		var/list/offered = archetype.available_choices(party, region, blocked)
		TEST_ASSERT(length(offered), "'[decision_id]' offered a destitute party nothing at all. The caravan would never move again.")

		// And everything offered is something the archetype actually declares.
		for(var/choice_id in offered)
			TEST_ASSERT(choice_id in archetype.choice_ids, "'[decision_id]' offered '[choice_id]', which it does not declare.")

	// A well-supplied party with people on it should see more than the bare minimum, or the extra choices are
	// unreachable content.
	var/datum/colonist_record/vera = SScampaign.roster.find_or_create("playerone", "Vera Holt", generation_number = 1, chapter = 1)
	var/mob/living/carbon/human/body = allocate(/mob/living/carbon/human/consistent, run_loc_floor_bottom_left)
	SScampaign.bind_colonist(body, vera)
	party.member_ids += vera.colonist_id
	party.supplies = 200

	var/datum/overworld_decision/spoor = get_overworld_decision(OVERWORLD_DECISION_SPOOR)
	TEST_ASSERT_EQUAL(length(spoor.available_choices(party, region, blocked)), 3, "A healthy party was not offered every way of dealing with an animal.")


/// Which problem a party meets is derived, so it is the same one after a reload.
/datum/unit_test/rimstation_colonist_chapter/overworld_decisions_are_derived

/datum/unit_test/rimstation_colonist_chapter/overworld_decisions_are_derived/Run()
	begin_test_campaign()
	SScampaign.overworld = new(default_overworld_options())
	SScampaign.ledger = new
	var/datum/overworld_region/region = get_active_overworld_region()

	var/datum/overworld_party/party = SScampaign.form_party()
	party.route = region.plan_route("0,0", "3,0", OVERWORLD_ROUTE_FASTEST)
	party.current_cell = party.route[1]
	party.next_leg_index = 2

	var/blocked = party.leg_target_cell()
	var/datum/overworld_decision/first = pick_overworld_decision(party, region, blocked)
	TEST_ASSERT_NOTNULL(first, "No archetype was chosen for a party on the road.")

	// Asking again is asking the same question. A party that could reroll by reloading would simply reload
	// until it liked what it found.
	for(var/attempt in 1 to 5)
		var/datum/overworld_decision/again = pick_overworld_decision(party, region, blocked)
		TEST_ASSERT_EQUAL(again, first, "The same party at the same place met a different problem on asking twice.")

	// Different ground is allowed to be a different problem; what matters is that each is stable.
	party.next_leg_index = 3
	var/other_cell = party.leg_target_cell()
	if(other_cell && other_cell != blocked)
		var/datum/overworld_decision/elsewhere = pick_overworld_decision(party, region, other_cell)
		TEST_ASSERT_NOTNULL(elsewhere, "No archetype was chosen for the next cell along.")
		TEST_ASSERT_EQUAL(elsewhere, pick_overworld_decision(party, region, other_cell), "A second cell's problem was not stable either.")
