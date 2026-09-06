/**
 * Forming an expedition, and refusing to form a broken one.
 *
 * A party is the only thing in this campaign that takes colonists off the map, so the interesting cases are
 * all refusals: somebody who is dead, somebody who was never here, somebody signed on twice, or a plan that
 * changed after people agreed to it. These build a real campaign with real bodies rather than calling the
 * membership rules directly, because every one of those rules is about the state of somebody's body.
 */
/datum/unit_test/rimstation_colonist_chapter/overworld_party
	abstract_type = /datum/unit_test/rimstation_colonist_chapter/overworld_party
	/// The settlement's balance as this test found it. Departure can buy rations, so these move real money.
	var/saved_balance

/**
 * A campaign with a region, an expedition being assembled, and as much food as the test asked for.
 *
 * Stocked as real loaves in a real larder rather than by writing the ledger, because the larder is what the
 * colony actually counts - a test that set the number directly would be testing a figure that the next recount
 * throws away.
 */
/datum/unit_test/rimstation_colonist_chapter/overworld_party/proc/begin_expedition_campaign(food_units = 500, credits = 5000)
	RETURN_TYPE(/datum/overworld_party)
	begin_test_campaign()

	SScampaign.overworld = new(default_overworld_options())
	var/datum/overworld_region/region = get_active_overworld_region()
	SScampaign.overworld.reveal_initial(region)

	SScampaign.ledger = new

	// A caravan will not leave without somewhere to muster and everybody standing at it. Built on the same tile
	// settle_test_colonist() puts bodies on, so a colonist who signs on is gathered by virtue of existing - what
	// these tests are about is membership and money, not where people are standing.
	allocate(/obj/structure/caravan_hitching_post, run_loc_floor_bottom_left)

	// The budget is the fallback an unstocked colony travels on, so it has to be a known quantity too.
	var/datum/bank_account/account = get_settlement_account()
	if(account)
		saved_balance = account.account_balance
		account.account_balance = credits

	if(food_units > 0)
		var/obj/structure/closet/crate/freezer/colony_larder/larder = allocate(/obj/structure/closet/crate/freezer/colony_larder, run_loc_floor_bottom_left)
		// A loaf is five units, so this rounds up to at least what was asked for.
		for(var/index in 1 to CEILING(food_units / 5, 1))
			var/obj/item/food/bread/plain/loaf = allocate(/obj/item/food/bread/plain)
			loaf.forceMove(larder)
		sync_colony_food_to_ledger()

	return SScampaign.form_party()

/datum/unit_test/rimstation_colonist_chapter/overworld_party/Destroy()
	var/datum/bank_account/account = get_settlement_account()
	if(account && !isnull(saved_balance))
		account.account_balance = saved_balance
	return ..()

/// Puts a playable, locker-owning colonist in the colony and returns their record.
/datum/unit_test/rimstation_colonist_chapter/overworld_party/proc/settle_test_colonist(ckey, name)
	RETURN_TYPE(/datum/colonist_record)
	var/datum/colonist_record/record = SScampaign.roster.find_or_create(ckey, name, generation_number = 1, chapter = 1)
	var/mob/living/carbon/human/body = allocate(/mob/living/carbon/human/consistent, run_loc_floor_bottom_left)
	SScampaign.bind_colonist(body, record)

	var/obj/structure/closet/colonist_storage/locker/personal = allocate(/obj/structure/closet/colonist_storage/locker, run_loc_floor_top_right)
	claim_colonist_locker(body, personal)
	return record


/// There is one expedition at a time, and its identifier is its own forever.
/datum/unit_test/rimstation_colonist_chapter/overworld_party/one_at_a_time

/datum/unit_test/rimstation_colonist_chapter/overworld_party/one_at_a_time/Run()
	var/datum/overworld_party/party = begin_expedition_campaign()
	TEST_ASSERT_NOTNULL(party, "An expedition could not be formed.")
	TEST_ASSERT_EQUAL(party.party_id, "party-1", "The first expedition was not numbered from one.")
	TEST_ASSERT_EQUAL(party.state, OVERWORLD_PARTY_FORMING, "A new expedition did not begin by being assembled.")

	// A second one would be a second group of colonists nobody is tracking.
	TEST_ASSERT_NULL(SScampaign.form_party(), "A second expedition was formed while one already existed.")
	TEST_ASSERT_EQUAL(SScampaign.get_active_party(), party, "Forming a refused expedition replaced the one that existed.")

	// The slot only frees when the journey has actually ended, and the next id never reuses the last.
	TEST_ASSERT(!SScampaign.overworld.clear_party("test"), "An expedition still being assembled was cleared away.")
	party.set_state(OVERWORLD_PARTY_LOST, "the test lost them")
	TEST_ASSERT(SScampaign.overworld.clear_party("test"), "A finished expedition could not be cleared.")

	var/datum/overworld_party/second = SScampaign.form_party()
	TEST_ASSERT_NOTNULL(second, "A second expedition could not be formed after the first ended.")
	TEST_ASSERT_EQUAL(second.party_id, "party-2", "A new expedition reused the previous one's identifier.")


/// Only living colonists of this colony, who have somewhere to leave their things, and only once each.
/datum/unit_test/rimstation_colonist_chapter/overworld_party/guards_membership

/datum/unit_test/rimstation_colonist_chapter/overworld_party/guards_membership/Run()
	var/datum/overworld_party/party = begin_expedition_campaign()
	var/datum/colonist_record/vera = settle_test_colonist("playerone", "Vera Holt")

	TEST_ASSERT(party.add_member(vera.colonist_id), "A living colonist with a locker could not sign on.")
	TEST_ASSERT_EQUAL(length(party.member_ids), 1, "Signing on did not add anybody.")

	// Twice is once. A duplicate would be counted twice for food and left behind once on the way home.
	TEST_ASSERT(!party.add_member(vera.colonist_id), "A colonist signed on to the same expedition twice.")
	TEST_ASSERT_EQUAL(length(party.member_ids), 1, "A duplicate signing changed the party.")

	// Nobody who is not on this colony's roster.
	TEST_ASSERT(!party.add_member("colonist-does-not-exist"), "Somebody who is not on the roster signed on.")
	TEST_ASSERT(!party.add_member(null), "A null colonist id signed on.")
	TEST_ASSERT(!party.add_member(""), "An empty colonist id signed on.")

	// Somebody on the roster who nobody is playing this chapter has no body to send.
	var/datum/colonist_record/absent = SScampaign.roster.find_or_create("playertwo", "Absent Fellow", generation_number = 1, chapter = 1)
	absent.status = COLONIST_STATUS_AWAY
	TEST_ASSERT(!party.add_member(absent.colonist_id), "A colonist who is not in the colony this chapter signed on.")

	// And somebody with no locker has nowhere for their belongings to wait.
	var/datum/colonist_record/homeless = SScampaign.roster.find_or_create("playerthree", "No Locker", generation_number = 1, chapter = 1)
	var/mob/living/carbon/human/homeless_body = allocate(/mob/living/carbon/human/consistent, run_loc_floor_bottom_left)
	SScampaign.bind_colonist(homeless_body, homeless)
	TEST_ASSERT(!party.add_member(homeless.colonist_id), "A colonist with no personal locker signed on.")
	TEST_ASSERT_NOTNULL(party.joining_problem(homeless.colonist_id), "A refusal was given with no reason to show the player.")

	// Leaving is allowed while the party is still at home.
	TEST_ASSERT(party.remove_member(vera.colonist_id), "A colonist could not withdraw from an expedition being assembled.")
	TEST_ASSERT_EQUAL(length(party.member_ids), 0, "Withdrawing did not remove anybody.")
	TEST_ASSERT(!party.remove_member(vera.colonist_id), "Somebody who had already withdrawn withdrew again.")


/// Saying you are ready is about one specific plan, and stops meaning anything when that plan changes.
/datum/unit_test/rimstation_colonist_chapter/overworld_party/readiness_follows_the_plan

/datum/unit_test/rimstation_colonist_chapter/overworld_party/readiness_follows_the_plan/Run()
	var/datum/overworld_party/party = begin_expedition_campaign()
	var/datum/overworld_region/region = get_active_overworld_region()
	var/datum/colonist_record/vera = settle_test_colonist("playerone", "Vera Holt")
	var/datum/colonist_record/otto = settle_test_colonist("playertwo", "Otto Vance")

	TEST_ASSERT(party.add_member(vera.colonist_id), "A colonist could not sign on.")

	// Readiness is meaningless before there is anywhere to go.
	TEST_ASSERT(!party.set_ready(vera.colonist_id), "A colonist said they were ready for an expedition with no destination.")

	var/datum/overworld_site/target = pick_any_reachable_site(region, party)
	TEST_ASSERT_NOTNULL(target, "The test region offered no site to walk to.")
	TEST_ASSERT(party.set_destination(region, target.site_id(), OVERWORLD_ROUTE_FASTEST, get_discovered_cell_ids(region)), "A destination could not be chosen.")
	TEST_ASSERT(length(party.route) >= 2, "Choosing a destination produced no route.")
	TEST_ASSERT(region.is_valid_route(party.route), "The planner set a route its own validator rejects.")

	TEST_ASSERT(party.set_ready(vera.colonist_id), "A colonist could not say they were ready.")
	TEST_ASSERT(party.everyone_ready(), "Everybody signed on had said yes and the party was still not ready.")

	// Somebody else joining changes what was agreed to, so the agreement lapses.
	TEST_ASSERT(party.add_member(otto.colonist_id), "A second colonist could not sign on.")
	TEST_ASSERT_EQUAL(length(party.ready_member_ids), 0, "Adding a member left the others still marked ready for a different party.")

	TEST_ASSERT(party.set_ready(vera.colonist_id), "A colonist could not say they were ready again.")
	TEST_ASSERT(party.set_ready(otto.colonist_id), "The second colonist could not say they were ready.")
	TEST_ASSERT(party.everyone_ready(), "Both members had said yes and the party was still not ready.")

	// So does changing the route out from under them.
	TEST_ASSERT(party.set_destination(region, target.site_id(), OVERWORLD_ROUTE_SAFER, get_discovered_cell_ids(region)), "The route could not be changed.")
	TEST_ASSERT_EQUAL(party.route_kind, OVERWORLD_ROUTE_SAFER, "Changing the route did not record which offer was taken.")
	TEST_ASSERT_EQUAL(length(party.ready_member_ids), 0, "Changing the route left people marked ready for the old one.")

	// Somebody who is not on the party has nothing to be ready about.
	TEST_ASSERT(!party.set_ready("colonist-does-not-exist"), "A stranger marked themselves ready for the colony's expedition.")


/// A party leaves once, having been paid for, and only when everything is still true.
/datum/unit_test/rimstation_colonist_chapter/overworld_party/departure_is_atomic

/datum/unit_test/rimstation_colonist_chapter/overworld_party/departure_is_atomic/Run()
	var/datum/overworld_party/party = begin_expedition_campaign(food_units = 500)
	var/datum/overworld_region/region = get_active_overworld_region()
	var/datum/colonist_record/vera = settle_test_colonist("playerone", "Vera Holt")

	// Nobody, nowhere, nothing agreed: each refusal names itself rather than failing silently.
	TEST_ASSERT_NOTNULL(SScampaign.depart_party(), "An empty expedition was sent out.")
	TEST_ASSERT(party.add_member(vera.colonist_id), "A colonist could not sign on.")
	TEST_ASSERT_NOTNULL(SScampaign.depart_party(), "An expedition with no destination was sent out.")

	var/datum/overworld_site/target = pick_any_reachable_site(region, party)
	TEST_ASSERT_NOTNULL(target, "The test region offered no site to walk to.")
	TEST_ASSERT(party.set_destination(region, target.site_id(), OVERWORLD_ROUTE_FASTEST, get_discovered_cell_ids(region)), "A destination could not be chosen.")
	TEST_ASSERT_NOTNULL(SScampaign.depart_party(), "An expedition nobody had agreed to was sent out.")

	// Priced from the route and the headcount, both ways, plus a reserve.
	var/expected = ((OVERWORLD_SUPPLY_PER_EDGE * party.outbound_edges()) + OVERWORLD_SUPPLY_RESERVE) * length(party.member_ids)
	TEST_ASSERT_EQUAL(party.supply_cost(), expected, "The food a journey needs was not its crossings and its heads.")
	TEST_ASSERT(party.supply_cost() > 0, "A real journey was priced at nothing.")

	TEST_ASSERT(party.set_ready(vera.colonist_id), "A colonist could not say they were ready.")

	var/before = count_colony_food()
	TEST_ASSERT(before >= expected, "The test did not stock enough food to prove anything.")
	TEST_ASSERT_NULL(SScampaign.depart_party(), "A fully prepared expedition was refused.")
	// Departing hands off to an async step that brings the camp up, and that step can carry the party straight
	// on to the road and even into an interruption at the first boundary. Any of those mean it left; only
	// forming would mean it did not.
	TEST_ASSERT(party.state != OVERWORLD_PARTY_FORMING, "A departing expedition did not leave the assembly state.")
	TEST_ASSERT_EQUAL(party.supplies, expected, "A departing expedition did not carry the food it was charged for.")

	// Taken out of the larder, not merely deducted from a figure. Loaves do not divide, so it may have taken
	// slightly more than the bill - what matters is that it took at least it, and not nothing.
	var/eaten = before - count_colony_food()
	TEST_ASSERT(eaten >= expected, "The colony was not charged the food the journey cost.")
	TEST_ASSERT_EQUAL(SScampaign.ledger.get_resource(COLONY_FOOD_RESOURCE), count_colony_food(), "The ledger disagrees with the larder after a departure.")

	// Gone means gone: membership, plans and a second departure are all closed now.
	var/after_departure = count_colony_food()
	TEST_ASSERT(!party.is_planning(), "An expedition that had left was still being assembled.")
	TEST_ASSERT(!party.add_member(vera.colonist_id), "Somebody signed on to an expedition that had already left.")
	TEST_ASSERT_NOTNULL(SScampaign.depart_party(), "An expedition that had already left was sent out a second time.")
	TEST_ASSERT_EQUAL(count_colony_food(), after_departure, "A refused second departure ate the colony's food again.")


/**
 * A colony that cannot feed an expedition does not send one - but an empty larder alone does not stop it.
 *
 * Two different situations that would look the same from a bare "there is no food" check: a colony with no
 * stores but money in the bank buys rations in, and only a colony with neither is actually stuck.
 */
/datum/unit_test/rimstation_colonist_chapter/overworld_party/hunger_stops_departure

/datum/unit_test/rimstation_colonist_chapter/overworld_party/hunger_stops_departure/Run()
	// No larder at all, but a healthy budget.
	var/datum/overworld_party/party = begin_expedition_campaign(food_units = 0, credits = 5000)
	var/datum/overworld_region/region = get_active_overworld_region()
	var/datum/colonist_record/vera = settle_test_colonist("playerone", "Vera Holt")

	TEST_ASSERT(party.add_member(vera.colonist_id), "A colonist could not sign on.")
	var/datum/overworld_site/target = pick_any_reachable_site(region, party)
	TEST_ASSERT_NOTNULL(target, "The test region offered no site to walk to.")
	TEST_ASSERT(party.set_destination(region, target.site_id(), OVERWORLD_ROUTE_FASTEST, get_discovered_cell_ids(region)), "A destination could not be chosen.")
	TEST_ASSERT(party.set_ready(vera.colonist_id), "A colonist could not say they were ready.")
	TEST_ASSERT_EQUAL(count_colony_food(), 0, "The test began with food it did not mean to have.")

	// Unstocked but solvent: it goes, and pays merchant prices for the rations.
	var/datum/bank_account/account = get_settlement_account()
	var/balance_before = account.account_balance
	TEST_ASSERT_NULL(SScampaign.depart_party(), "An expedition with no stores but plenty of money was refused.")
	TEST_ASSERT(party.state != OVERWORLD_PARTY_FORMING, "An expedition that bought its rations in did not leave.")
	TEST_ASSERT(account.account_balance < balance_before, "Buying rations in cost the colony nothing.")

	// Now the case that is genuinely stuck: no stores and no money. The campaign is reused rather than rebuilt,
	// because starting a second one here would have the harness save this test's own state as the original.
	party.set_state(OVERWORLD_PARTY_LOST, "the test is done with them")
	TEST_ASSERT(SScampaign.overworld.clear_party("test"), "The departed expedition could not be cleared.")
	account.account_balance = 0

	var/datum/overworld_party/broke = SScampaign.form_party()
	TEST_ASSERT_NOTNULL(broke, "A second expedition could not be formed for the destitute case.")
	var/datum/colonist_record/otto = settle_test_colonist("playertwo", "Otto Vance")
	TEST_ASSERT(broke.add_member(otto.colonist_id), "A colonist could not sign on to the second expedition.")
	var/datum/overworld_site/second_target = pick_any_reachable_site(region, broke)
	TEST_ASSERT_NOTNULL(second_target, "The test region offered no site for the second expedition.")
	TEST_ASSERT(broke.set_destination(region, second_target.site_id(), OVERWORLD_ROUTE_FASTEST, get_discovered_cell_ids(region)), "A destination could not be chosen.")
	TEST_ASSERT(broke.set_ready(otto.colonist_id), "A colonist could not say they were ready.")

	TEST_ASSERT_NOTNULL(SScampaign.depart_party(), "An expedition left with no food and no money to buy any.")
	TEST_ASSERT_EQUAL(broke.state, OVERWORLD_PARTY_FORMING, "A refused departure moved the expedition anyway.")
	TEST_ASSERT_EQUAL(get_settlement_account().account_balance, 0, "A refused departure still spent money.")


/// A party record survives being written out and read back, and a broken one costs only itself.
/datum/unit_test/rimstation_colonist_chapter/overworld_party/survives_storage

/datum/unit_test/rimstation_colonist_chapter/overworld_party/survives_storage/Run()
	var/datum/overworld_party/party = begin_expedition_campaign()
	var/datum/overworld_region/region = get_active_overworld_region()
	var/datum/colonist_record/vera = settle_test_colonist("playerone", "Vera Holt")

	TEST_ASSERT(party.add_member(vera.colonist_id), "A colonist could not sign on.")
	var/datum/overworld_site/target = pick_any_reachable_site(region, party)
	TEST_ASSERT_NOTNULL(target, "The test region offered no site to walk to.")
	TEST_ASSERT(party.set_destination(region, target.site_id(), OVERWORLD_ROUTE_SAFER, get_discovered_cell_ids(region)), "A destination could not be chosen.")
	TEST_ASSERT(party.set_ready(vera.colonist_id), "A colonist could not say they were ready.")

	var/list/record = SScampaign.overworld.serialize()
	var/datum/overworld_state/reloaded = new(default_overworld_options())
	allocated += reloaded
	TEST_ASSERT(reloaded.deserialize(record), "A regional record carrying an expedition could not be read back.")

	var/datum/overworld_party/restored = reloaded.active_party
	TEST_ASSERT_NOTNULL(restored, "An expedition did not survive being written out.")
	TEST_ASSERT_EQUAL(restored.party_id, party.party_id, "A restored expedition changed identity.")
	TEST_ASSERT_EQUAL(json_encode(restored.member_ids), json_encode(party.member_ids), "A restored expedition lost its members.")
	TEST_ASSERT_EQUAL(json_encode(restored.route), json_encode(party.route), "A restored expedition lost its route.")
	TEST_ASSERT_EQUAL(restored.route_kind, party.route_kind, "A restored expedition forgot which offer was taken.")
	TEST_ASSERT_EQUAL(restored.destination_site_id, party.destination_site_id, "A restored expedition forgot where it was going.")

	// The counter never rewinds past a party that exists, or the next journey would take a live id.
	TEST_ASSERT(reloaded.next_party_number > 1, "A restored campaign would issue an identifier already in use.")

	// Readiness claimed for somebody who is not a member is dropped rather than believed.
	var/list/forged = SScampaign.overworld.serialize()
	forged["active_party"]["ready_member_ids"] = list("colonist-not-a-member")
	var/datum/overworld_state/tampered = new(default_overworld_options())
	allocated += tampered
	TEST_ASSERT(tampered.deserialize(forged), "A record with a forged ready list was refused outright.")
	TEST_ASSERT_EQUAL(length(tampered.active_party.ready_member_ids), 0, "Somebody who was not on the expedition was restored as ready to go.")

	// An unreadable expedition costs the caravan, not the discoveries beside it.
	var/list/broken = SScampaign.overworld.serialize()
	broken["active_party"]["state"] = "not-a-real-state"
	var/datum/overworld_state/salvaged = new(default_overworld_options())
	allocated += salvaged
	TEST_ASSERT(salvaged.deserialize(broken), "One bad expedition record threw away the whole regional record.")
	TEST_ASSERT_NULL(salvaged.active_party, "An expedition in an impossible state was restored anyway.")
	TEST_ASSERT(length(salvaged.discovered_cells), "Dropping a bad expedition also dropped what the colony had explored.")


/// Forward only. A journey that has ended cannot start again and be paid out twice.
/datum/unit_test/rimstation_colonist_chapter/overworld_party/states_only_move_forward

/datum/unit_test/rimstation_colonist_chapter/overworld_party/states_only_move_forward/Run()
	var/datum/overworld_party/party = begin_expedition_campaign()

	TEST_ASSERT(!party.set_state("not-a-real-state", "test"), "An expedition entered a state that does not exist.")
	TEST_ASSERT(!party.set_state(OVERWORLD_PARTY_AT_SITE, "test"), "An expedition arrived somewhere without leaving home.")
	TEST_ASSERT(!party.set_state(OVERWORLD_PARTY_FORMING, "test"), "An expedition moved to the state it was already in.")

	TEST_ASSERT(party.set_state(OVERWORLD_PARTY_DEPARTING, "test"), "An assembled expedition could not set out.")
	TEST_ASSERT(party.set_state(OVERWORLD_PARTY_OUTBOUND, "test"), "A departing expedition could not get on the road.")
	TEST_ASSERT(!party.set_state(OVERWORLD_PARTY_FORMING, "test"), "An expedition on the road went back to being assembled.")

	TEST_ASSERT(party.set_state(OVERWORLD_PARTY_AT_SITE, "test"), "An expedition could not arrive.")
	TEST_ASSERT(party.set_state(OVERWORLD_PARTY_RETURNING, "test"), "An expedition could not head home.")
	TEST_ASSERT(party.set_state(OVERWORLD_PARTY_COMPLETE, "test"), "An expedition could not finish.")

	// Terminal means terminal, in both directions.
	TEST_ASSERT(!party.set_state(OVERWORLD_PARTY_RETURNING, "test"), "A finished expedition went back on the road.")
	TEST_ASSERT(!party.set_state(OVERWORLD_PARTY_LOST, "test"), "A finished expedition was lost afterwards.")


/**
 * The first site the colony can actually reach from home, or null. Keeps the party tests off region specifics.
 *
 * `skip_loaded` is for tests that assert about whether a scene has been brought up. Destinations are registered
 * globally for the whole round and their reservations are never handed back, so an earlier test that departed
 * somewhere leaves that site standing for every test after it. Regions are generated deterministically, so
 * without this the two tests pick the same site every run.
 */
/proc/pick_any_reachable_site(datum/overworld_region/region, datum/overworld_party/party, skip_loaded = FALSE)
	RETURN_TYPE(/datum/overworld_site)
	if(!region || !party)
		return null

	var/list/seen = get_discovered_cell_ids(region)
	for(var/site_id in region.sites)
		var/datum/overworld_site/site = region.sites[site_id]
		var/cell_id = "[site.q],[site.r]"
		if(!seen[cell_id])
			continue
		if(skip_loaded && get_loaded_destination(site_id))
			continue
		if(length(region.plan_route(party.current_cell, cell_id, OVERWORLD_ROUTE_FASTEST, seen)) >= 2)
			return site
	return null
