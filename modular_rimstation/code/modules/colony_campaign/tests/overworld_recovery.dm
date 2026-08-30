/**
 * What survives a chapter ending, and what a death does to a journey.
 *
 * The whole of Task 5 is one promise: a caravan that was somewhere when the chapter ended is in the same
 * somewhere when the next one starts. The failure it guards against is not a crash - it is the quiet kind,
 * where a party halfway across the region comes back as nothing and four colonists are simply gone.
 *
 * So these assert on the record rather than on the runtime: what reaches the manifest is what the next boot
 * reads, and anything held only in memory is a thing that has already been lost.
 */
/datum/unit_test/rimstation_colonist_chapter/overworld_recovery
	abstract_type = /datum/unit_test/rimstation_colonist_chapter/overworld_recovery

/// A campaign with a region and an expedition, ready to be interrupted.
/datum/unit_test/rimstation_colonist_chapter/overworld_recovery/proc/begin_recovery_campaign()
	RETURN_TYPE(/datum/overworld_party)
	begin_test_campaign()
	SScampaign.overworld = new(default_overworld_options())
	SScampaign.ledger = new
	SScampaign.start_campaign_time()
	SScampaign.overworld.reveal_initial(get_active_overworld_region())
	return SScampaign.form_party()

/// A colonist who can travel, standing on the test floor.
/datum/unit_test/rimstation_colonist_chapter/overworld_recovery/proc/settle_traveller(ckey, name)
	RETURN_TYPE(/datum/colonist_record)
	var/datum/colonist_record/record = SScampaign.roster.find_or_create(ckey, name, generation_number = 1, chapter = 1)
	var/mob/living/carbon/human/body = allocate(/mob/living/carbon/human/consistent, run_loc_floor_bottom_left)
	SScampaign.bind_colonist(body, record)
	var/obj/structure/closet/colonist_storage/locker/personal = allocate(/obj/structure/closet/colonist_storage/locker, run_loc_floor_top_right)
	claim_colonist_locker(body, personal)
	return record

/**
 * Puts a party on the road, the way a finished departure would have left it.
 *
 * Goes through `schedule_or_ask()` rather than `schedule_leg()`, because that is what departure calls and the
 * very first boundary is one the road can interrupt. A test that skipped that check would be walking a route
 * no real party walks.
 *
 * Interruptions are suppressed unless a test asks for one. The boundary is derived from the party id and the
 * route, so which tests get stopped is otherwise an accident of hashing - and a test about persistence should
 * not pass or fail on that.
 */
/datum/unit_test/rimstation_colonist_chapter/overworld_recovery/proc/send_out(datum/overworld_party/party, list/route, supplies = 40, allow_decisions = FALSE)
	party.route = route.Copy()
	party.current_cell = route[1]
	party.next_leg_index = 2
	party.supplies = supplies
	if(!allow_decisions)
		party.decisions_taken = 1
	party.set_state(OVERWORLD_PARTY_DEPARTING, "test")
	party.set_state(OVERWORLD_PARTY_OUTBOUND, "test")
	SSoverworld.schedule_or_ask(party, get_active_overworld_region())
	return party


/**
 * A journey in progress reaches the manifest, not just memory.
 *
 * Asserted by reading the record back into a fresh state, which is exactly what the next boot does. A party
 * that only exists on the live datum is a party that ends when the round does.
 */
/datum/unit_test/rimstation_colonist_chapter/overworld_recovery/travel_reaches_the_record

/datum/unit_test/rimstation_colonist_chapter/overworld_recovery/travel_reaches_the_record/Run()
	var/datum/overworld_party/party = begin_recovery_campaign()
	var/datum/overworld_region/region = get_active_overworld_region()
	var/datum/colonist_record/vera = settle_traveller("playerone", "Vera Holt")
	TEST_ASSERT(party.add_member(vera.colonist_id), "A colonist could not sign on.")

	var/list/route = region.plan_route("0,0", "3,0", OVERWORLD_ROUTE_FASTEST)
	send_out(party, route, supplies = 40)

	// Mid-leg, which is the state a chapter is most likely to end in.
	TEST_ASSERT_EQUAL(party.state, OVERWORLD_PARTY_OUTBOUND, "The test party is not travelling.")
	TEST_ASSERT(party.leg_arrives_at > 0, "The test party has no leg in progress to be interrupted.")

	// This is what a commit writes. Everything below is read out of it rather than off the live party.
	SScampaign.sync_overworld()
	var/list/stored = SScampaign.manifest.overworld_record
	TEST_ASSERT(islist(stored), "The overworld record was not written into the manifest.")

	var/datum/overworld_state/reloaded = new(default_overworld_options())
	allocated += reloaded
	TEST_ASSERT(reloaded.deserialize(stored), "The stored overworld record could not be read back.")

	var/datum/overworld_party/resumed = reloaded.active_party
	TEST_ASSERT_NOTNULL(resumed, "A party mid-journey did not survive being written out. Everybody on it would be gone.")
	TEST_ASSERT_EQUAL(resumed.state, OVERWORLD_PARTY_OUTBOUND, "A travelling party came back as something else.")
	TEST_ASSERT_EQUAL(resumed.current_cell, party.current_cell, "A resumed party is standing somewhere else.")
	TEST_ASSERT_EQUAL(resumed.next_leg_index, party.next_leg_index, "A resumed party is walking towards a different cell.")
	TEST_ASSERT_EQUAL(resumed.leg_arrives_at, party.leg_arrives_at, "A resumed leg would arrive at a different time.")
	TEST_ASSERT_EQUAL(resumed.supplies, party.supplies, "A resumed party is carrying a different amount of food.")
	TEST_ASSERT_EQUAL(json_encode(resumed.member_ids), json_encode(party.member_ids), "A resumed party lost its members.")
	TEST_ASSERT_EQUAL(json_encode(resumed.route), json_encode(party.route), "A resumed party lost the road it was walking.")


/// A question the road asked is still the same question after a reload, and is not asked twice.
/datum/unit_test/rimstation_colonist_chapter/overworld_recovery/a_decision_never_rerolls

/datum/unit_test/rimstation_colonist_chapter/overworld_recovery/a_decision_never_rerolls/Run()
	var/datum/overworld_party/party = begin_recovery_campaign()
	var/datum/overworld_region/region = get_active_overworld_region()
	var/datum/colonist_record/vera = settle_traveller("playerone", "Vera Holt")
	party.add_member(vera.colonist_id)

	var/list/route = region.plan_route("0,0", "4,0", OVERWORLD_ROUTE_FASTEST)
	send_out(party, route, supplies = 40, allow_decisions = TRUE)

	// Walk until the road stops them, or until the route runs out. It may already have stopped them at the
	// first boundary, in which case this loop does nothing and the assertion below is already true.
	var/guard = 0
	while(party.state == OVERWORLD_PARTY_OUTBOUND && guard < 20)
		guard++
		var/remaining = party.leg_arrives_at - SScampaign.get_campaign_time()
		if(remaining > 0)
			SScampaign.chapter_world_time_origin -= (remaining + 1)
		SSoverworld.fire()

	TEST_ASSERT_EQUAL(party.state, OVERWORLD_PARTY_DECISION, "The road never stopped the expedition.")
	TEST_ASSERT_NOTNULL(party.pending_decision, "A halted expedition has no question to answer.")
	var/asked_id = party.pending_decision["id"]
	var/asked_cell = party.pending_decision["cell"]

	SScampaign.sync_overworld()
	var/datum/overworld_state/reloaded = new(default_overworld_options())
	allocated += reloaded
	TEST_ASSERT(reloaded.deserialize(SScampaign.manifest.overworld_record), "The stored record could not be read back.")

	var/datum/overworld_party/resumed = reloaded.active_party
	TEST_ASSERT_NOTNULL(resumed, "A halted party did not survive being written out.")
	TEST_ASSERT_EQUAL(resumed.state, OVERWORLD_PARTY_DECISION, "A halted party came back moving again.")
	TEST_ASSERT_NOTNULL(resumed.pending_decision, "A resumed party lost the question it was answering.")

	// The same question, not a fresh one. A reroll would let a party reload until it liked the options.
	TEST_ASSERT_EQUAL(resumed.pending_decision["id"], asked_id, "A pending decision was reissued with a new identity.")
	TEST_ASSERT_EQUAL(resumed.pending_decision["cell"], asked_cell, "A pending decision came back about different ground.")

	// And once answered it is not asked again, however many times somebody clicks.
	var/first = SSoverworld.answer_decision(party, asked_id, OVERWORLD_DECISION_FORCE, null)
	TEST_ASSERT_NULL(first, "A valid answer to the road was refused.")
	TEST_ASSERT_NULL(party.pending_decision, "Answering did not clear the question.")

	var/second = SSoverworld.answer_decision(party, asked_id, OVERWORLD_DECISION_FORCE, null)
	TEST_ASSERT_NOTNULL(second, "The same answer was accepted twice.")
	TEST_ASSERT_EQUAL(party.decisions_taken, 1, "One question was recorded as having been answered more than once.")


/// A death thins a party; it does not end the journey until nobody is left.
/datum/unit_test/rimstation_colonist_chapter/overworld_recovery/death_thins_then_ends

/datum/unit_test/rimstation_colonist_chapter/overworld_recovery/death_thins_then_ends/Run()
	var/datum/overworld_party/party = begin_recovery_campaign()
	var/datum/overworld_region/region = get_active_overworld_region()
	var/datum/colonist_record/vera = settle_traveller("playerone", "Vera Holt")
	var/datum/colonist_record/otto = settle_traveller("playertwo", "Otto Vance")
	party.add_member(vera.colonist_id)
	party.add_member(otto.colonist_id)

	var/list/route = region.plan_route("0,0", "3,0", OVERWORLD_ROUTE_FASTEST)
	send_out(party, route, supplies = 40)
	var/cell_when_it_started = party.current_cell

	// One of two dying leaves a journey in progress. The survivor keeps walking.
	var/mob/living/vera_body = SScampaign.get_colonist_body(vera.colonist_id)
	vera_body.death()
	TEST_ASSERT_EQUAL(SScampaign.roster.get_record(vera.colonist_id).status, COLONIST_STATUS_DEAD, "A death was not recorded on the roster.")
	TEST_ASSERT_EQUAL(party.state, OVERWORLD_PARTY_OUTBOUND, "One death out of two ended the whole expedition.")
	TEST_ASSERT_EQUAL(party.living_member_count(), 1, "The survivor was not counted.")
	TEST_ASSERT(!(vera.colonist_id in party.ready_member_ids), "A dead colonist was still counted as ready to travel.")

	// The last one dying ends it, and what they were carrying is forfeit rather than refunded.
	var/carried = party.supplies
	TEST_ASSERT(carried > 0, "The test party set out with no rations, so forfeiting them proves nothing.")
	var/food_before = SScampaign.ledger.get_resource(OVERWORLD_SUPPLY_RESOURCE)

	var/mob/living/otto_body = SScampaign.get_colonist_body(otto.colonist_id)
	otto_body.death()
	TEST_ASSERT_EQUAL(party.state, OVERWORLD_PARTY_LOST, "An expedition with nobody alive on it was still travelling.")
	TEST_ASSERT_EQUAL(party.supplies, 0, "A lost expedition was still carrying rations.")
	TEST_ASSERT_EQUAL(SScampaign.ledger.get_resource(OVERWORLD_SUPPLY_RESOURCE), food_before, "Rations that went out with a lost expedition were refunded to the colony.")

	// What it walked stays walked. Losing the party is one loss, not two.
	TEST_ASSERT(SScampaign.overworld.is_discovered(cell_when_it_started), "Losing an expedition unexplored the ground it had already walked.")


/// A party that has left is not defending the colony it walked out of.
/datum/unit_test/rimstation_colonist_chapter/overworld_recovery/counts_who_is_left_at_home

/datum/unit_test/rimstation_colonist_chapter/overworld_recovery/counts_who_is_left_at_home/Run()
	var/datum/overworld_party/party = begin_recovery_campaign()
	var/datum/overworld_region/region = get_active_overworld_region()
	var/datum/colonist_record/vera = settle_traveller("playerone", "Vera Holt")
	var/datum/colonist_record/otto = settle_traveller("playertwo", "Otto Vance")

	TEST_ASSERT_EQUAL(length(get_colonists_physically_at_colony()), 2, "The colony did not count the people standing in it.")

	// Signing on changes nothing while they are still here.
	party.add_member(vera.colonist_id)
	TEST_ASSERT_EQUAL(length(get_colonists_physically_at_colony()), 2, "Somebody who had only signed on was already counted as away.")

	// Leaving does.
	var/list/route = region.plan_route("0,0", "3,0", OVERWORLD_ROUTE_FASTEST)
	send_out(party, route, supplies = 40)
	var/list/at_home = get_colonists_physically_at_colony()
	TEST_ASSERT_EQUAL(length(at_home), 1, "A departed expedition was still counted as defending the colony.")
	TEST_ASSERT(otto.colonist_id in at_home, "The colonist who stayed behind was not counted.")
	TEST_ASSERT(!(vera.colonist_id in at_home), "A colonist out on the road was counted as being at home.")


/**
 * Somebody rejoining mid-journey is still on the journey, and still owns their things.
 *
 * The failure this guards is quiet and expensive: a colonist logs back in, the game puts them in the colony
 * because that is where colonists go, and the expedition they were on is now one person short forever with no
 * error anywhere. Equipment is the second half - their locker is in a colony they cannot walk to, so if it is
 * not handed back here it is not handed back at all.
 */
/datum/unit_test/rimstation_colonist_chapter/overworld_recovery/rejoining_stays_on_the_journey

/datum/unit_test/rimstation_colonist_chapter/overworld_recovery/rejoining_stays_on_the_journey/Run()
	var/datum/overworld_party/party = begin_recovery_campaign()
	var/datum/overworld_region/region = get_active_overworld_region()
	var/datum/colonist_record/vera = settle_traveller("playerone", "Vera Holt")
	var/datum/colonist_record/otto = settle_traveller("playertwo", "Otto Vance")
	party.add_member(vera.colonist_id)

	var/list/route = region.plan_route("0,0", "3,0", OVERWORLD_ROUTE_FASTEST)
	send_out(party, route, supplies = 40)

	// On the road, so rejoining must not put her back in the colony.
	TEST_ASSERT(is_travelling_member(vera.colonist_id), "A departed colonist was not counted as travelling.")
	// Somebody who stayed behind is not, and neither is somebody who never signed on.
	TEST_ASSERT(!is_travelling_member(otto.colonist_id), "A colonist who stayed home was counted as travelling.")
	TEST_ASSERT(!is_travelling_member("colonist-who-does-not-exist"), "A stranger was counted as travelling.")

	// A party still gathering has not gone anywhere, so its members rejoin normally.
	var/datum/overworld_party/second = null
	party.set_state(OVERWORLD_PARTY_LOST, "test")
	SScampaign.overworld.clear_party("test")
	second = SScampaign.form_party()
	TEST_ASSERT(second.add_member(otto.colonist_id), "A colonist could not sign on to the second expedition.")
	TEST_ASSERT(!is_travelling_member(otto.colonist_id), "Somebody who had only signed on was treated as being out on the road.")

	// And a finished journey puts everybody back into ordinary arrivals.
	second.set_state(OVERWORLD_PARTY_DEPARTING, "test")
	second.set_state(OVERWORLD_PARTY_OUTBOUND, "test")
	TEST_ASSERT(is_travelling_member(otto.colonist_id), "A departed colonist was not counted as travelling.")
	second.set_state(OVERWORLD_PARTY_LOST, "test")
	TEST_ASSERT(!is_travelling_member(otto.colonist_id), "Somebody on a finished expedition was still treated as travelling.")


/// A traveller's own belongings come back to them, and nobody else's do.
/datum/unit_test/rimstation_colonist_chapter/overworld_recovery/rejoining_returns_your_own_kit

/datum/unit_test/rimstation_colonist_chapter/overworld_recovery/rejoining_returns_your_own_kit/Run()
	begin_recovery_campaign()
	var/datum/colonist_record/vera = settle_traveller("playerone", "Vera Holt")
	var/mob/living/vera_body = SScampaign.get_colonist_body(vera.colonist_id)

	var/obj/structure/closet/colonist_storage/locker/personal = get_personal_colonist_locker(vera.colonist_id)
	TEST_ASSERT_NOTNULL(personal, "The test colonist has no personal locker.")

	// A packed backpack waiting in the locker, exactly as a commit mid-journey would have left it.
	var/obj/item/storage/backpack/pack = allocate(/obj/item/storage/backpack)
	pack.forceMove(personal)
	TEST_ASSERT_EQUAL(pack.loc, personal, "The test could not put a backpack in the locker.")

	TEST_ASSERT(restore_traveller_belongings(vera_body, vera), "A traveller's belongings were not handed back.")
	TEST_ASSERT(!QDELETED(pack), "A returned backpack was destroyed rather than handed over.")
	TEST_ASSERT(pack.loc != personal, "A traveller's belongings were left in a locker they cannot walk to.")

	// An empty locker is not an error, and does not strip the outfit the job just issued.
	var/datum/colonist_record/otto = settle_traveller("playertwo", "Otto Vance")
	var/mob/living/otto_body = SScampaign.get_colonist_body(otto.colonist_id)
	TEST_ASSERT(!restore_traveller_belongings(otto_body, otto), "An empty locker reported that it had handed something back.")

	// And somebody with no locker at all keeps what they were issued rather than arriving naked.
	var/datum/colonist_record/stranger = SScampaign.roster.find_or_create("playerthree", "No Locker", generation_number = 1, chapter = 1)
	var/mob/living/carbon/human/stranger_body = allocate(/mob/living/carbon/human/consistent, run_loc_floor_bottom_left)
	SScampaign.bind_colonist(stranger_body, stranger)
	TEST_ASSERT(!restore_traveller_belongings(stranger_body, stranger), "A colonist with no locker was handed somebody's belongings.")


/**
 * A journey nobody is watching still happens, and still costs what it costs.
 *
 * The colony does not stop existing because everybody logged off. Legs come due on the campaign clock whether
 * there is anybody in the camp or not, so a party sent out on a quiet evening is somewhere different by
 * morning - which is the whole point of the clock being campaign time rather than session time.
 */
/datum/unit_test/rimstation_colonist_chapter/overworld_recovery/travel_continues_unwatched

/datum/unit_test/rimstation_colonist_chapter/overworld_recovery/travel_continues_unwatched/Run()
	var/datum/overworld_party/party = begin_recovery_campaign()
	var/datum/overworld_region/region = get_active_overworld_region()
	var/datum/colonist_record/vera = settle_traveller("playerone", "Vera Holt")
	party.add_member(vera.colonist_id)

	var/list/route = region.plan_route("0,0", "3,0", OVERWORLD_ROUTE_FASTEST)
	send_out(party, route, supplies = 40)

	// Everybody logs off: the roster still knows them, but there is no body anywhere.
	SScampaign.active_colonist_bodies = list()
	TEST_ASSERT_EQUAL(party.living_member_count(), 0, "The test could not empty the party of live bodies.")

	var/started_at = party.current_cell
	var/remaining = party.leg_arrives_at - SScampaign.get_campaign_time()
	if(remaining > 0)
		SScampaign.chapter_world_time_origin -= (remaining + 1)
	SSoverworld.fire()

	TEST_ASSERT(party.current_cell != started_at, "A leg that came due while nobody was online never arrived.")
	TEST_ASSERT_EQUAL(party.state, OVERWORLD_PARTY_OUTBOUND, "An unwatched party stopped travelling.")

	// Nobody eats, because nobody is there to eat. Rations are per living head, and there were none.
	TEST_ASSERT_EQUAL(party.supplies, 40, "An expedition with nobody on it ate its rations anyway.")


/**
 * Arriving somewhere with nobody online does not reserve the ground.
 *
 * A scene is brought up for people to stand in, and a reservation is never handed back. Loading one for a party
 * that has nobody in it spends turfs for the rest of the round on a room nobody will enter until they rejoin -
 * at which point rejoining brings it up anyway.
 */
/datum/unit_test/rimstation_colonist_chapter/overworld_recovery/an_empty_party_reserves_nothing

/datum/unit_test/rimstation_colonist_chapter/overworld_recovery/an_empty_party_reserves_nothing/Run()
	var/datum/overworld_party/party = begin_recovery_campaign()
	var/datum/overworld_region/region = get_active_overworld_region()
	var/datum/colonist_record/vera = settle_traveller("playerone", "Vera Holt")
	party.add_member(vera.colonist_id)

	// Standing one step short of a site, with nobody online to arrive at it.
	var/datum/overworld_site/target = pick_any_reachable_site(region, party)
	TEST_ASSERT_NOTNULL(target, "The test region offered no site to walk to.")
	var/site_cell = "[target.q],[target.r]"
	var/list/route = region.plan_route("0,0", site_cell, OVERWORLD_ROUTE_FASTEST)
	TEST_ASSERT(length(route) >= 2, "The test could not plan a route to a site.")

	send_out(party, route, supplies = 40)
	party.destination_site_id = target.site_id()
	party.next_leg_index = length(route)
	party.current_cell = route[length(route) - 1]
	SSoverworld.schedule_leg(party, region)

	SScampaign.active_colonist_bodies = list()
	TEST_ASSERT_NULL(get_loaded_destination(target.site_id()), "The site was already loaded before the party reached it.")

	var/remaining = party.leg_arrives_at - SScampaign.get_campaign_time()
	if(remaining > 0)
		SScampaign.chapter_world_time_origin -= (remaining + 1)
	SSoverworld.fire()

	// The record says they are there, which is what a rejoining player will be told.
	TEST_ASSERT_EQUAL(party.state, OVERWORLD_PARTY_AT_SITE, "A party that reached its destination is not at the site.")
	TEST_ASSERT_NULL(get_loaded_destination(target.site_id()), "A site was reserved for an expedition with nobody on it.")
