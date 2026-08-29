/**
 * Gathering at the post, and what the road pays out.
 *
 * The muster exists so a caravan is seen to leave from somewhere rather than blinking out of the colony, so
 * what matters here is that being signed on and being present are two different things and the departure
 * checks both.
 */
/datum/unit_test/rimstation_colonist_chapter/overworld_muster
	abstract_type = /datum/unit_test/rimstation_colonist_chapter/overworld_muster

/// A campaign with a region, a post, a stocked larder and an expedition being assembled.
/datum/unit_test/rimstation_colonist_chapter/overworld_muster/proc/begin_muster_campaign()
	RETURN_TYPE(/datum/overworld_party)
	begin_test_campaign()
	SScampaign.overworld = new(default_overworld_options())
	SScampaign.ledger = new
	SScampaign.overworld.reveal_initial(get_active_overworld_region())
	return SScampaign.form_party()

/// A colonist with a locker, standing wherever the test puts them.
/datum/unit_test/rimstation_colonist_chapter/overworld_muster/proc/settle_at(ckey, name, turf/where)
	RETURN_TYPE(/datum/colonist_record)
	var/datum/colonist_record/record = SScampaign.roster.find_or_create(ckey, name, generation_number = 1, chapter = 1)
	var/mob/living/carbon/human/body = allocate(/mob/living/carbon/human/consistent, where)
	SScampaign.bind_colonist(body, record)
	var/obj/structure/closet/colonist_storage/locker/personal = allocate(/obj/structure/closet/colonist_storage/locker, run_loc_floor_top_right)
	claim_colonist_locker(body, personal)
	return record


/// Somebody who signed on but wandered off is not gathered, and the caravan says so by name.
/datum/unit_test/rimstation_colonist_chapter/overworld_muster/counts_who_is_present

/datum/unit_test/rimstation_colonist_chapter/overworld_muster/counts_who_is_present/Run()
	var/datum/overworld_party/party = begin_muster_campaign()
	TEST_ASSERT_NOTNULL(party, "An expedition could not be formed.")

	// No post at all is its own refusal, and a distinguishable one.
	var/datum/colonist_record/vera = settle_at("playerone", "Vera Holt", run_loc_floor_bottom_left)
	TEST_ASSERT(party.add_member(vera.colonist_id), "A colonist could not sign on.")
	TEST_ASSERT_NOTNULL(party.gathering_problem(), "A party mustered with no hitching post to muster at.")

	var/obj/structure/caravan_hitching_post/post = allocate(/obj/structure/caravan_hitching_post, run_loc_floor_bottom_left)
	TEST_ASSERT_EQUAL(get_caravan_hitching_post(), post, "The colony could not find the post that was just built.")

	// Standing on it counts, obviously.
	TEST_ASSERT(vera.colonist_id in party_members_at_post(party), "A colonist standing on the post was not counted as gathered.")
	TEST_ASSERT_NULL(party.gathering_problem(), "A fully gathered party was told it had not gathered.")

	// Somebody the far side of the test floor is signed on but not present, and is named rather than counted.
	var/datum/colonist_record/otto = settle_at("playertwo", "Otto Vance", run_loc_floor_top_right)
	TEST_ASSERT(party.add_member(otto.colonist_id), "A second colonist could not sign on.")
	TEST_ASSERT(!(otto.colonist_id in party_members_at_post(party)), "A colonist across the room was counted as gathered.")

	var/problem = party.gathering_problem()
	TEST_ASSERT_NOTNULL(problem, "A party with somebody missing was allowed to consider itself gathered.")
	TEST_ASSERT(findtext(problem, "Otto Vance"), "The refusal did not name who was missing, so nobody could act on it.")

	// Walking over fixes it. The radius is generous on purpose, so beside the post counts.
	var/mob/living/otto_body = SScampaign.get_colonist_body(otto.colonist_id)
	otto_body.forceMove(get_step(post, EAST))
	TEST_ASSERT(otto.colonist_id in party_members_at_post(party), "A colonist standing beside the post was not counted as gathered.")
	TEST_ASSERT_NULL(party.gathering_problem(), "A party standing together was still refused.")


/// An expedition will not leave people behind, however ready and well fed it is.
/datum/unit_test/rimstation_colonist_chapter/overworld_muster/departure_waits_for_everyone

/datum/unit_test/rimstation_colonist_chapter/overworld_muster/departure_waits_for_everyone/Run()
	var/datum/overworld_party/party = begin_muster_campaign()
	var/datum/overworld_region/region = get_active_overworld_region()
	var/obj/structure/caravan_hitching_post/post = allocate(/obj/structure/caravan_hitching_post, run_loc_floor_bottom_left)

	// Money rather than a larder, so food cannot be what refuses this.
	var/datum/bank_account/account = get_settlement_account()
	var/saved_balance = account?.account_balance
	if(account)
		account.account_balance = 9000

	var/datum/colonist_record/vera = settle_at("playerone", "Vera Holt", get_turf(post))
	var/datum/colonist_record/otto = settle_at("playertwo", "Otto Vance", run_loc_floor_top_right)
	TEST_ASSERT(party.add_member(vera.colonist_id), "A colonist could not sign on.")
	TEST_ASSERT(party.add_member(otto.colonist_id), "A second colonist could not sign on.")

	var/datum/overworld_site/target = pick_any_reachable_site(region, party)
	TEST_ASSERT_NOTNULL(target, "The test region offered no site to walk to.")
	TEST_ASSERT(party.set_destination(region, target.site_id(), OVERWORLD_ROUTE_FASTEST, get_discovered_cell_ids(region)), "A destination could not be chosen.")
	TEST_ASSERT(party.set_ready(vera.colonist_id), "A colonist could not say they were ready.")
	TEST_ASSERT(party.set_ready(otto.colonist_id), "A second colonist could not say they were ready.")
	TEST_ASSERT(party.everyone_ready(), "Both members said yes and the party was still not ready.")

	// Everything agreed and paid for, and it still will not go without Otto. Driven through the post rather
	// than through depart_party(), because clicking the post is the only way anybody can actually leave.
	var/mob/living/vera_body = SScampaign.get_colonist_body(vera.colonist_id)
	post.set_out(vera_body)
	TEST_ASSERT_EQUAL(party.state, OVERWORLD_PARTY_FORMING, "An expedition left with one of its members across the colony.")

	// Somebody who is not going cannot send other people out of the colony.
	var/datum/colonist_record/bystander = settle_at("playerthree", "Idle Bystander", get_turf(post))
	var/mob/living/bystander_body = SScampaign.get_colonist_body(bystander.colonist_id)
	var/mob/living/otto_body = SScampaign.get_colonist_body(otto.colonist_id)
	otto_body.forceMove(get_turf(post))
	post.set_out(bystander_body)
	TEST_ASSERT_EQUAL(party.state, OVERWORLD_PARTY_FORMING, "Somebody not signed on sent the expedition out.")

	// A member giving the word, with everybody gathered, is what actually sends it.
	post.set_out(vera_body)
	TEST_ASSERT(party.state != OVERWORLD_PARTY_FORMING, "A gathered expedition did not leave when a member gave the word.")

	if(account && !isnull(saved_balance))
		account.account_balance = saved_balance


/// Signing on hangs a reminder on you, and it goes away when you do.
/datum/unit_test/rimstation_colonist_chapter/overworld_muster/reminds_who_signed_on

/datum/unit_test/rimstation_colonist_chapter/overworld_muster/reminds_who_signed_on/Run()
	var/datum/overworld_party/party = begin_muster_campaign()
	allocate(/obj/structure/caravan_hitching_post, run_loc_floor_bottom_left)
	var/datum/colonist_record/vera = settle_at("playerone", "Vera Holt", run_loc_floor_bottom_left)
	var/mob/living/vera_body = SScampaign.get_colonist_body(vera.colonist_id)

	TEST_ASSERT(!vera_body.has_status_effect(/datum/status_effect/caravan_signed_on), "A colonist was reminded of an expedition before joining one.")

	TEST_ASSERT(party.add_member(vera.colonist_id), "A colonist could not sign on.")
	SScampaign.commit_party_change()
	TEST_ASSERT(vera_body.has_status_effect(/datum/status_effect/caravan_signed_on), "Signing on did not remind the colonist they had.")

	// Withdrawing takes it back off, so nobody is left being told to gather for a walk they are not on.
	TEST_ASSERT(party.remove_member(vera.colonist_id), "A colonist could not withdraw.")
	SScampaign.commit_party_change()
	TEST_ASSERT(!vera_body.has_status_effect(/datum/status_effect/caravan_signed_on), "A colonist who withdrew was still being reminded to gather.")

	// And calling the whole thing off clears everybody at once.
	TEST_ASSERT(party.add_member(vera.colonist_id), "A colonist could not sign on again.")
	SScampaign.commit_party_change()
	party.set_state(OVERWORLD_PARTY_LOST, "test called it off")
	SScampaign.overworld.clear_party("test")
	SScampaign.commit_party_change()
	TEST_ASSERT(!vera_body.has_status_effect(/datum/status_effect/caravan_signed_on), "Calling the muster off left people still being reminded.")


/// Working a deposit puts ore on the ground, because a number in a ledger is not a reward.
/datum/unit_test/rimstation_colonist_chapter/overworld_muster/deposits_drop_real_ore

/datum/unit_test/rimstation_colonist_chapter/overworld_muster/deposits_drop_real_ore/Run()
	begin_muster_campaign()

	var/turf/where = run_loc_floor_bottom_left
	var/dropped = drop_deposit_ore(where, 60)
	TEST_ASSERT_EQUAL(dropped, 60, "A deposit did not put down everything it was worth.")

	// Counted across the neighbouring tiles too: a yield larger than one stack is spread rather than lost.
	var/found = 0
	for(var/turf/spot as anything in (list(where) + get_adjacent_open_turfs(where)))
		for(var/obj/item/stack/ore/iron/ore in spot)
			found += ore.amount
	TEST_ASSERT_EQUAL(found, 60, "The ore a deposit dropped could not be found on the ground.")

	// Nothing at all is a legitimate answer rather than a runtime.
	TEST_ASSERT_EQUAL(drop_deposit_ore(where, 0), 0, "A worthless deposit dropped something anyway.")
	TEST_ASSERT_EQUAL(drop_deposit_ore(null, 30), 0, "Ore was dropped onto nowhere.")
