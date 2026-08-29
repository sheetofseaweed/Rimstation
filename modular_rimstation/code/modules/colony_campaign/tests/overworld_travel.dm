/**
 * Moving a caravan along its route.
 *
 * These drive `SSoverworld.fire()` rather than calling the transition procs, because the interesting failures
 * are all about *when* a transition happens: twice in one tick, once too early, or during a checkpoint write.
 * Calling `complete_leg()` directly would prove none of that.
 *
 * Campaign time is moved by rewinding the chapter's world-time origin, the same trick the clock tests use. The
 * clock is derived from that origin, so rewinding it is indistinguishable from having waited.
 */
/datum/unit_test/rimstation_colonist_chapter/overworld_travel
	abstract_type = /datum/unit_test/rimstation_colonist_chapter/overworld_travel
	/// The settlement's balance as this test found it. A journey ending refunds rations, which can be money.
	var/saved_balance

/// A campaign with a region, a stocked larder, and one colonist ready to travel.
/datum/unit_test/rimstation_colonist_chapter/overworld_travel/proc/begin_travel_campaign()
	RETURN_TYPE(/datum/overworld_party)
	begin_test_campaign()
	SScampaign.overworld = new(default_overworld_options())
	SScampaign.ledger = new
	SScampaign.start_campaign_time()

	var/datum/bank_account/account = get_settlement_account()
	if(account)
		saved_balance = account.account_balance

	var/datum/overworld_region/region = get_active_overworld_region()
	SScampaign.overworld.reveal_initial(region)
	return SScampaign.form_party()

/datum/unit_test/rimstation_colonist_chapter/overworld_travel/Destroy()
	var/datum/bank_account/account = get_settlement_account()
	if(account && !isnull(saved_balance))
		account.account_balance = saved_balance
	return ..()

/**
 * Puts a party on the road without going through the async departure.
 *
 * Departure brings up a map template, which is a different thing to test and an expensive one to do here. This
 * hands the party the state that a finished departure would have left it in.
 */
/datum/unit_test/rimstation_colonist_chapter/overworld_travel/proc/put_on_the_road(datum/overworld_party/party, list/route, supplies = 50)
	party.route = route.Copy()
	party.current_cell = route[1]
	party.next_leg_index = 2
	party.supplies = supplies
	party.set_state(OVERWORLD_PARTY_DEPARTING, "test")
	party.set_state(OVERWORLD_PARTY_OUTBOUND, "test")
	// schedule_or_ask rather than schedule_leg, because that is what a real departure calls. Going straight to
	// schedule_leg would skip the very first boundary's check for an interruption - and the first boundary is
	// exactly where some parties are interrupted.
	SSoverworld.schedule_or_ask(party, get_active_overworld_region())
	return party

/// Moves campaign time forward far enough that the party's current leg is due.
/datum/unit_test/rimstation_colonist_chapter/overworld_travel/proc/skip_to_arrival(datum/overworld_party/party)
	var/remaining = party.leg_arrives_at - SScampaign.get_campaign_time()
	if(remaining > 0)
		SScampaign.chapter_world_time_origin -= (remaining + 1)


/// A leg arrives when it is due, once, and not before.
/datum/unit_test/rimstation_colonist_chapter/overworld_travel/one_boundary_at_a_time

/datum/unit_test/rimstation_colonist_chapter/overworld_travel/one_boundary_at_a_time/Run()
	var/datum/overworld_party/party = begin_travel_campaign()
	TEST_ASSERT_NOTNULL(party, "An expedition could not be formed.")

	var/datum/overworld_region/region = get_active_overworld_region()
	var/list/route = region.plan_route("0,0", "3,0", OVERWORLD_ROUTE_FASTEST)
	TEST_ASSERT(length(route) >= 3, "The test could not plan a route long enough to walk.")

	put_on_the_road(party, route, supplies = 50)
	TEST_ASSERT_EQUAL(party.state, OVERWORLD_PARTY_OUTBOUND, "A party put on the road is not travelling.")
	TEST_ASSERT(party.leg_arrives_at > party.leg_started_at, "A scheduled leg arrives no later than it began.")
	TEST_ASSERT_EQUAL(party.current_cell, route[1], "A departing party did not start from the first cell of its route.")

	// Not due yet: firing changes nothing at all.
	var/supplies_before = party.supplies
	SSoverworld.fire()
	TEST_ASSERT_EQUAL(party.current_cell, route[1], "A party moved before its leg was due.")
	TEST_ASSERT_EQUAL(party.supplies, supplies_before, "A party ate its rations before arriving anywhere.")

	// Due: it crosses exactly one boundary.
	skip_to_arrival(party)
	SSoverworld.fire()
	TEST_ASSERT_EQUAL(party.current_cell, route[2], "A due leg did not move the party.")
	TEST_ASSERT_EQUAL(party.supplies, supplies_before - party.living_member_count(), "Crossing one boundary did not cost exactly one ration per head.")

	// Firing again immediately must not walk the next leg early. This is the one that would let a party cross
	// the whole region in a tick if the due check were wrong.
	var/after_one = party.supplies
	SSoverworld.fire()
	SSoverworld.fire()
	TEST_ASSERT_EQUAL(party.current_cell, route[2], "Repeated fires walked the party on before its next leg was due.")
	TEST_ASSERT_EQUAL(party.supplies, after_one, "Repeated fires ate rations for boundaries that were not crossed.")


/// Nothing moves while the colony is being written to disk.
/datum/unit_test/rimstation_colonist_chapter/overworld_travel/holds_still_for_a_checkpoint

/datum/unit_test/rimstation_colonist_chapter/overworld_travel/holds_still_for_a_checkpoint/Run()
	var/datum/overworld_party/party = begin_travel_campaign()
	var/datum/overworld_region/region = get_active_overworld_region()
	var/list/route = region.plan_route("0,0", "3,0", OVERWORLD_ROUTE_FASTEST)
	put_on_the_road(party, route, supplies = 50)
	skip_to_arrival(party)

	// A checkpoint is being staged: the world has to look the same all the way through it.
	SScampaign.world_quiesced = TRUE
	SSoverworld.fire()
	TEST_ASSERT_EQUAL(party.current_cell, route[1], "A party moved while the colony was being written to disk.")

	// The leg is not lost, only deferred - it is due at a clock reading, and that reading has still passed.
	SScampaign.world_quiesced = FALSE
	SSoverworld.fire()
	TEST_ASSERT_EQUAL(party.current_cell, route[2], "A leg that came due during a checkpoint never arrived afterwards.")


/// A party that is not travelling is not moved by anything.
/datum/unit_test/rimstation_colonist_chapter/overworld_travel/ignores_parties_not_travelling

/datum/unit_test/rimstation_colonist_chapter/overworld_travel/ignores_parties_not_travelling/Run()
	var/datum/overworld_party/party = begin_travel_campaign()
	var/datum/overworld_region/region = get_active_overworld_region()
	var/list/route = region.plan_route("0,0", "3,0", OVERWORLD_ROUTE_FASTEST)

	// Still being assembled: no route, no clock, nothing to advance.
	SSoverworld.fire()
	TEST_ASSERT_EQUAL(party.state, OVERWORLD_PARTY_FORMING, "Firing moved an expedition that was still being assembled.")

	put_on_the_road(party, route, supplies = 50)
	skip_to_arrival(party)

	// Lost is terminal. A lost party still has a due leg on it, and must not walk anyway.
	party.set_state(OVERWORLD_PARTY_LOST, "test")
	var/where_they_fell = party.current_cell
	SSoverworld.fire()
	TEST_ASSERT_EQUAL(party.current_cell, where_they_fell, "A lost expedition kept walking.")


/// The way home is the road walked backwards, and arriving on it ends the journey.
/datum/unit_test/rimstation_colonist_chapter/overworld_travel/returns_and_completes

/datum/unit_test/rimstation_colonist_chapter/overworld_travel/returns_and_completes/Run()
	var/datum/overworld_party/party = begin_travel_campaign()
	var/datum/overworld_region/region = get_active_overworld_region()
	var/list/route = region.plan_route("0,0", "2,0", OVERWORLD_ROUTE_FASTEST)
	TEST_ASSERT(length(route) >= 2, "The test could not plan a route to walk back along.")

	// Standing at the far end, as a party that had finished at a site would be.
	put_on_the_road(party, route, supplies = 40)
	party.current_cell = route[length(route)]
	party.set_state(OVERWORLD_PARTY_AT_SITE, "test")

	TEST_ASSERT(party.begin_return("test"), "A party at a site could not turn for home.")
	TEST_ASSERT_EQUAL(party.state, OVERWORLD_PARTY_RETURNING, "A party that turned for home is not returning.")
	TEST_ASSERT_EQUAL(party.next_leg_index, length(route) - 1, "A returning party did not aim at the cell before it.")

	TEST_ASSERT(SSoverworld.schedule_leg(party, region), "A returning party could not be given a leg to walk.")

	var/balance_before = get_settlement_account()?.account_balance || 0

	// Walk it home. Bounded well above the route length so a failure here is a failed assertion rather than a
	// test that hangs.
	var/guard = 0
	while(party.state == OVERWORLD_PARTY_RETURNING && guard < 20)
		guard++
		skip_to_arrival(party)
		SSoverworld.fire()

	TEST_ASSERT_EQUAL(party.state, OVERWORLD_PARTY_COMPLETE, "A party walking home never arrived.")
	TEST_ASSERT_EQUAL(party.current_cell, route[1], "A completed journey did not end at the colony.")

	// Whatever was not eaten goes back to the colony. It was an allocation of the colony's food, so the
	// leftovers are the colony's, not a reward.
	//
	// This colony has no larder, so they come back as the money the rations would have been bought for rather
	// than as bread. Which of the two it is does not matter here; what must not happen is the leftovers
	// quietly evaporating, which is exactly what crediting the ledger's food figure used to do.
	TEST_ASSERT_EQUAL(party.supplies, 0, "A finished expedition was still carrying rations.")
	TEST_ASSERT_NULL(get_colony_larder(), "This test assumes a colony with no larder and found one.")
	TEST_ASSERT(get_settlement_account().account_balance > balance_before, "A finished expedition returned none of its unspent rations.")


/**
 * The road interrupts exactly once, and an answer costs exactly once.
 *
 * The interesting failure is the second one: two members answering at the same moment, or one clicking twice,
 * paying the price twice or restarting a journey that had already resumed.
 */
/datum/unit_test/rimstation_colonist_chapter/overworld_travel/decides_once

/datum/unit_test/rimstation_colonist_chapter/overworld_travel/decides_once/Run()
	var/datum/overworld_party/party = begin_travel_campaign()
	var/datum/overworld_region/region = get_active_overworld_region()
	var/list/route = region.plan_route("0,0", "4,0", OVERWORLD_ROUTE_FASTEST)
	TEST_ASSERT(length(route) >= 4, "The test could not plan a route long enough to be interrupted.")

	put_on_the_road(party, route, supplies = 80)

	// Derived rather than rolled, so it is the same answer every time it is asked - which is what lets a party
	// reload mid-journey and find the same interruption waiting.
	var/boundary = party.decision_boundary_index()
	TEST_ASSERT(boundary >= 2 && boundary <= length(route), "The interruption was placed off the route.")
	TEST_ASSERT_EQUAL(boundary, party.decision_boundary_index(), "Asking where the interruption is twice gave two answers.")

	// Walk until the road stops them.
	var/guard = 0
	while(party.state == OVERWORLD_PARTY_OUTBOUND && guard < 20)
		guard++
		skip_to_arrival(party)
		SSoverworld.fire()

	TEST_ASSERT_EQUAL(party.state, OVERWORLD_PARTY_DECISION, "The expedition was never stopped by the road.")
	TEST_ASSERT_NOTNULL(party.pending_decision, "A halted expedition was given nothing to decide.")
	TEST_ASSERT(length(party.pending_decision["choices"]), "A decision offered no choices at all.")
	TEST_ASSERT(OVERWORLD_DECISION_FORCE in party.pending_decision["choices"], "Forcing through was not offered, so a broke party could be stranded.")
	TEST_ASSERT_EQUAL(party.leg_arrives_at, 0, "A halted expedition was still walking.")

	var/decision_id = party.pending_decision["id"]
	var/supplies_before = party.supplies

	// An answer to a question that was not asked, and a choice that was not offered, are both forgeries.
	TEST_ASSERT_NOTNULL(SSoverworld.answer_decision(party, "decision-not-real", OVERWORLD_DECISION_FORCE), "An answer to a different question was accepted.")
	TEST_ASSERT_NOTNULL(SSoverworld.answer_decision(party, decision_id, "eat-the-map"), "A choice that was never offered was accepted.")
	TEST_ASSERT_EQUAL(party.state, OVERWORLD_PARTY_DECISION, "A refused answer moved the expedition on anyway.")

	// Forcing through costs no rations, which is what makes it the answer nobody can be priced out of.
	TEST_ASSERT_NULL(SSoverworld.answer_decision(party, decision_id, OVERWORLD_DECISION_FORCE), "A valid answer was refused.")
	TEST_ASSERT_EQUAL(party.state, OVERWORLD_PARTY_OUTBOUND, "Answering did not put the expedition back on the road.")
	TEST_ASSERT_EQUAL(party.supplies, supplies_before, "Forcing through ate the party's rations.")
	TEST_ASSERT_NULL(party.pending_decision, "An answered question was still pending.")
	TEST_ASSERT_EQUAL(party.decisions_taken, 1, "Answering was not recorded.")

	// The same answer again finds nothing to answer. This is the one that would otherwise pay twice.
	TEST_ASSERT_NOTNULL(SSoverworld.answer_decision(party, decision_id, OVERWORLD_DECISION_FORCE), "The same decision was answered twice.")
	TEST_ASSERT_EQUAL(party.decisions_taken, 1, "A repeated answer was counted again.")

	// And the road does not ask again on this journey.
	guard = 0
	while(party.state == OVERWORLD_PARTY_OUTBOUND && guard < 20)
		guard++
		skip_to_arrival(party)
		SSoverworld.fire()
	TEST_ASSERT(party.state != OVERWORLD_PARTY_DECISION, "The road interrupted the same journey twice.")


/// Waiting it out costs a meal each and puts the arrival back.
/datum/unit_test/rimstation_colonist_chapter/overworld_travel/waiting_costs_time_and_food

/datum/unit_test/rimstation_colonist_chapter/overworld_travel/waiting_costs_time_and_food/Run()
	var/datum/overworld_party/party = begin_travel_campaign()
	var/datum/overworld_region/region = get_active_overworld_region()
	var/list/route = region.plan_route("0,0", "4,0", OVERWORLD_ROUTE_FASTEST)
	put_on_the_road(party, route, supplies = 80)

	var/guard = 0
	while(party.state == OVERWORLD_PARTY_OUTBOUND && guard < 20)
		guard++
		skip_to_arrival(party)
		SSoverworld.fire()
	TEST_ASSERT_EQUAL(party.state, OVERWORLD_PARTY_DECISION, "The expedition was never stopped by the road.")

	// Well fed, so sitting it out is affordable and therefore offered.
	TEST_ASSERT(OVERWORLD_DECISION_WAIT in party.pending_decision["choices"], "A well-provisioned party was not offered the chance to wait.")

	var/supplies_before = party.supplies
	var/mouths = party.living_member_count()
	TEST_ASSERT_NULL(SSoverworld.answer_decision(party, party.pending_decision["id"], OVERWORLD_DECISION_WAIT), "Waiting it out was refused.")

	TEST_ASSERT_EQUAL(party.supplies, supplies_before - mouths, "Waiting did not cost one meal per head.")
	TEST_ASSERT_EQUAL(party.state, OVERWORLD_PARTY_OUTBOUND, "A party that waited never set off again.")

	// The wait is added on top of the crossing rather than replacing it, so the leg is longer than the ground.
	var/leg_length = party.leg_arrives_at - party.leg_started_at
	TEST_ASSERT(leg_length > (OVERWORLD_DECISION_WAIT_SECONDS SECONDS), "Waiting did not add to the time the leg takes.")


/// A party too poor to do anything but push on is still offered the push.
/datum/unit_test/rimstation_colonist_chapter/overworld_travel/poverty_still_offers_a_way_on

/datum/unit_test/rimstation_colonist_chapter/overworld_travel/poverty_still_offers_a_way_on/Run()
	var/datum/overworld_party/party = begin_travel_campaign()
	var/datum/overworld_region/region = get_active_overworld_region()
	var/list/route = region.plan_route("0,0", "4,0", OVERWORLD_ROUTE_FASTEST)
	put_on_the_road(party, route, supplies = 80)

	var/guard = 0
	while(party.state == OVERWORLD_PARTY_OUTBOUND && guard < 20)
		guard++
		skip_to_arrival(party)
		SSoverworld.fire()
	TEST_ASSERT_EQUAL(party.state, OVERWORLD_PARTY_DECISION, "The expedition was never stopped by the road.")

	// Down to the last scrap. Anything that costs rations has to drop off the list, or the party is offered a
	// choice that strands it.
	party.supplies = 1
	var/list/choices = party.available_decision_choices(region)
	TEST_ASSERT(OVERWORLD_DECISION_FORCE in choices, "A destitute party was not offered the one free way on.")
	TEST_ASSERT(!(OVERWORLD_DECISION_WAIT in choices), "A party with one ration left was offered a wait it could not pay for.")
