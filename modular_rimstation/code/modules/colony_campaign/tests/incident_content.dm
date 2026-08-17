/**
 * Each incident's decision is answerable where it makes sense and nowhere else.
 *
 * This is the rule the whole decision layer exists for. A caravan hailing the settlement by radio must not be
 * answerable by touching a monument in the middle of the colony, while the settlement's own business should be
 * decidable without having built a console first.
 */
/datum/unit_test/rimstation_incident_answer_sources

/datum/unit_test/rimstation_incident_answer_sources/Run()
	// A trader is a call from outside. Console only.
	TEST_ASSERT(initial(/datum/colony_incident/trader::answer_sources) & INCIDENT_ANSWER_CONSOLE, "A trade caravan cannot be answered on a communications console.")
	TEST_ASSERT(!(initial(/datum/colony_incident/trader::answer_sources) & INCIDENT_ANSWER_COLONY_CORE), "A trade caravan can be answered by touching the colony core, which is absurd.")

	// The settlement's own business can be decided at its own heart.
	var/list/core_answerable = list(
		/datum/colony_incident/refugee,
		/datum/colony_incident/dispute,
		/datum/colony_incident/blight,
	)
	for(var/datum/colony_incident/incident_type as anything in core_answerable)
		TEST_ASSERT(initial(incident_type.answer_sources) & INCIDENT_ANSWER_COLONY_CORE, "[incident_type] cannot be answered at the colony core, so a settlement without a console could never decide it.")
		TEST_ASSERT(initial(incident_type.answer_sources) & INCIDENT_ANSWER_CONSOLE, "[incident_type] cannot be answered on a console.")

	// A storm asks nothing; it is answered by moving, not by choosing.
	TEST_ASSERT(!initial(/datum/colony_incident/storm::answer_sources), "A storm asks the colony a question, when the only answer it wants is people getting indoors.")


/**
 * The five incidents exist, one per category, and none of them is abstract.
 *
 * The storyteller buys categories, so a category with no incident behind it is an event that fires and does
 * nothing. This asserts the set is complete rather than trusting that it is.
 */
/datum/unit_test/campaign_failure_path/rimstation_incident_set_covers_categories
	test_campaign_id = "unit-test-incident-set"

/datum/unit_test/campaign_failure_path/rimstation_incident_set_covers_categories/Run()
	take_campaign()
	TEST_ASSERT(SScampaign.create_campaign(test_campaign_id, "admin-key"), "A campaign could not be created.")

	var/list/categories = COLONY_INCIDENT_CATEGORIES
	for(var/incident_category in categories)
		var/list/eligible = SScampaign.get_eligible_incident_types(incident_category)
		TEST_ASSERT(length(eligible), "No incident exists for the '[incident_category]' category, so the storyteller could buy an event that does nothing.")

	// Every incident names a real category and carries tags, so pacing can tell them apart later.
	for(var/datum/colony_incident/incident_type as anything in subtypesof(/datum/colony_incident))
		if(initial(incident_type.abstract_incident))
			continue
		var/incident_category = initial(incident_type.category)
		TEST_ASSERT(incident_category in categories, "[incident_type] is in category '[incident_category]', which is not one of the five.")
		TEST_ASSERT(initial(incident_type.warning_duration) > 0, "[incident_type] gives the colony no warning at all.")


/**
 * A trade the colony accepts is paid for, and one it declines costs nothing.
 *
 * The money moves through the ledger either way, so the account of the chapter shows what was spent and on
 * what - and a caravan that cannot be paid does not hand over goods on credit.
 */
/datum/unit_test/campaign_failure_path/rimstation_incident_trader
	test_campaign_id = "unit-test-incident-trader"

/datum/unit_test/campaign_failure_path/rimstation_incident_trader/Run()
	take_campaign()
	TEST_ASSERT(SScampaign.create_campaign(test_campaign_id, "admin-key"), "A campaign could not be created.")

	var/datum/bank_account/account = get_settlement_account()
	account.account_balance = 5000
	SScampaign.get_ledger().capture_from(account)

	var/datum/colony_incident/trader/trader = new
	allocated += trader
	trader.select_target()
	TEST_ASSERT(trader.asking_price > 0, "The caravan is asking nothing for its goods.")
	TEST_ASSERT(trader.asking_price <= 5000, "The caravan is asking more than the settlement could ever pay.")

	// Declining costs nothing and is not a failure - the colony is allowed to say no.
	trader.set_state(COLONY_INCIDENT_WARNING)
	trader.set_state(COLONY_INCIDENT_ACTIVE)
	trader.on_answered(2)
	TEST_ASSERT_EQUAL(account.account_balance, 5000, "Declining a trade still cost the settlement money.")
	TEST_ASSERT_EQUAL(trader.result?.outcome, COLONY_INCIDENT_OUTCOME_IGNORED, "Declining a trade was recorded as something other than declining it.")

	// Accepting pays for it.
	var/datum/colony_incident/trader/buyer = new
	allocated += buyer
	buyer.select_target()
	buyer.set_state(COLONY_INCIDENT_WARNING)
	buyer.set_state(COLONY_INCIDENT_ACTIVE)
	var/price = buyer.asking_price
	buyer.on_answered(1)
	TEST_ASSERT_EQUAL(account.account_balance, 5000 - price, "Accepting a trade did not take the price out of the settlement's account.")
	TEST_ASSERT_EQUAL(buyer.result?.outcome, COLONY_INCIDENT_OUTCOME_SUCCEEDED, "A completed trade was not recorded as a success.")

	// A colony that cannot pay is refused rather than given goods on credit.
	account.account_balance = 0
	SScampaign.get_ledger().capture_from(account)
	var/datum/colony_incident/trader/broke = new
	allocated += broke
	broke.asking_price = 400
	broke.offered_goods = list(/obj/item/stack/sheet/iron/fifty = 1)
	broke.set_state(COLONY_INCIDENT_WARNING)
	broke.set_state(COLONY_INCIDENT_ACTIVE)
	broke.on_answered(1)
	TEST_ASSERT_EQUAL(broke.result?.outcome, COLONY_INCIDENT_OUTCOME_FAILED, "A settlement that could not pay still completed the trade.")
	TEST_ASSERT(!broke.deal_struck, "A trade was struck with no money to pay for it.")


/// A blight the colony pays to treat is treated; one it ignores is not, and neither is a silent failure.
/datum/unit_test/campaign_failure_path/rimstation_incident_blight
	test_campaign_id = "unit-test-incident-blight"

/datum/unit_test/campaign_failure_path/rimstation_incident_blight/Run()
	take_campaign()
	TEST_ASSERT(SScampaign.create_campaign(test_campaign_id, "admin-key"), "A campaign could not be created.")

	var/datum/bank_account/account = get_settlement_account()
	account.account_balance = 1000
	SScampaign.get_ledger().capture_from(account)

	var/datum/colony_incident/blight/ignored = new
	allocated += ignored
	ignored.set_state(COLONY_INCIDENT_WARNING)
	ignored.set_state(COLONY_INCIDENT_ACTIVE)
	ignored.on_answered(2)
	TEST_ASSERT_EQUAL(account.account_balance, 1000, "Letting a blight run still cost the settlement money.")
	TEST_ASSERT_EQUAL(ignored.result?.outcome, COLONY_INCIDENT_OUTCOME_FAILED, "A crop left to a blight was not recorded as a loss.")
	TEST_ASSERT(ignored.result.pressure_change > 0, "Losing a crop did not add any pressure.")

	var/datum/colony_incident/blight/treated = new
	allocated += treated
	treated.set_state(COLONY_INCIDENT_WARNING)
	treated.set_state(COLONY_INCIDENT_ACTIVE)
	var/cost = treated.treatment_cost
	treated.on_answered(1)
	TEST_ASSERT_EQUAL(account.account_balance, 1000 - cost, "Treating a blight did not cost what it said it would.")
	TEST_ASSERT_EQUAL(treated.result?.outcome, COLONY_INCIDENT_OUTCOME_SUCCEEDED, "Saving the crop was not recorded as a success.")
	TEST_ASSERT(treated.result.pressure_change < 0, "Saving the crop gave the colony no relief.")


/**
 * A refugee costs food, and a colony with none cannot take anyone in.
 *
 * The cost is what makes this a decision rather than a gift, so it is asserted rather than assumed - an
 * incident in the positive category that only ever gives is not a choice.
 */
/datum/unit_test/campaign_failure_path/rimstation_incident_refugee
	test_campaign_id = "unit-test-incident-refugee"

/datum/unit_test/campaign_failure_path/rimstation_incident_refugee/Run()
	take_campaign()
	TEST_ASSERT(SScampaign.create_campaign(test_campaign_id, "admin-key"), "A campaign could not be created.")

	// Turning them away costs nothing but is not free of consequence.
	var/datum/colony_incident/refugee/turned_away = new
	allocated += turned_away
	turned_away.set_state(COLONY_INCIDENT_WARNING)
	turned_away.set_state(COLONY_INCIDENT_ACTIVE)
	turned_away.on_answered(2)
	TEST_ASSERT_EQUAL(turned_away.result?.outcome, COLONY_INCIDENT_OUTCOME_IGNORED, "Turning a refugee away was recorded as a failure rather than a choice.")
	TEST_ASSERT(turned_away.result.pressure_change > 0, "Turning someone away cost the settlement nothing at all.")

	// With neither food nor money, the colony cannot take anyone in however much it wants to.
	var/datum/bank_account/account = get_settlement_account()
	account.account_balance = 0
	SScampaign.get_ledger().capture_from(account)
	var/datum/colony_incident/refugee/starving = new
	allocated += starving
	starving.set_state(COLONY_INCIDENT_WARNING)
	starving.set_state(COLONY_INCIDENT_ACTIVE)
	starving.on_answered(1)
	TEST_ASSERT_EQUAL(starving.result?.outcome, COLONY_INCIDENT_OUTCOME_FAILED, "A settlement with nothing to give still took in a refugee.")
	TEST_ASSERT(!starving.admitted, "Someone was admitted with nothing to feed them.")

	// Stored food is the price when the settlement tracks any.
	SScampaign.adjust_resource("food", 100, LEDGER_CATEGORY_SALVAGE, "stores", null, null)
	var/datum/settlement_ledger/settlement = SScampaign.get_ledger()
	var/food_before = settlement.get_resource("food")
	var/datum/colony_incident/refugee/fed = new
	allocated += fed
	fed.set_state(COLONY_INCIDENT_WARNING)
	fed.set_state(COLONY_INCIDENT_ACTIVE)
	fed.on_answered(1)
	TEST_ASSERT_EQUAL(settlement.get_resource("food"), food_before - fed.food_price, "Taking in a refugee did not cost the settlement any food.")

	// With no tracked stores it is paid for in credits instead - nothing produces stores yet, so without this
	// the incident could never succeed at all.
	SScampaign.adjust_resource("food", -settlement.get_resource("food"), LEDGER_CATEGORY_UPKEEP, "emptied", null, null)
	account.account_balance = 5000
	settlement.capture_from(account)
	var/datum/colony_incident/refugee/bought_in = new
	allocated += bought_in
	bought_in.set_state(COLONY_INCIDENT_WARNING)
	bought_in.set_state(COLONY_INCIDENT_ACTIVE)
	bought_in.on_answered(1)
	TEST_ASSERT_EQUAL(account.account_balance, 5000 - bought_in.credit_price, "A settlement with no stores did not buy food in for the refugee.")
	TEST_ASSERT_NOTNULL(bought_in.paid_in, "The settlement paid for a refugee without recording what it paid in.")


/**
 * The same story does not land twice running, and no category ever runs dry.
 *
 * Repetition is dulled rather than forbidden. Forbidding it would mean a category whose incidents have all
 * run recently becomes unbuyable - so the storyteller would silently lose a whole kind of event at exactly the
 * point the colony has been through the most, which is the opposite of what pacing is for.
 */
/datum/unit_test/campaign_failure_path/rimstation_incident_repetition
	test_campaign_id = "unit-test-incident-repetition"

/datum/unit_test/campaign_failure_path/rimstation_incident_repetition/Run()
	take_campaign()
	TEST_ASSERT(SScampaign.create_campaign(test_campaign_id, "admin-key"), "A campaign could not be created.")
	SScampaign.incident_history = null

	// With no history, nothing is penalised.
	var/fresh_weight = SScampaign.get_incident_selection_weight(/datum/colony_incident/blight)
	TEST_ASSERT_EQUAL(fresh_weight, COLONY_INCIDENT_BASE_WEIGHT, "An incident was penalised before anything had happened.")

	// Having just run makes the same incident much less likely.
	SScampaign.incident_history = list(list(
		"incident_id" = "incident-earlier",
		"incident_type" = "/datum/colony_incident/blight",
		"tags" = list(INCIDENT_TAG_HARVEST),
		"outcome" = COLONY_INCIDENT_OUTCOME_FAILED,
	))
	var/repeat_weight = SScampaign.get_incident_selection_weight(/datum/colony_incident/blight)
	TEST_ASSERT(repeat_weight < fresh_weight, "An incident that just ran is no less likely than one that has not.")
	TEST_ASSERT(repeat_weight >= COLONY_INCIDENT_MINIMUM_WEIGHT, "A recent incident was penalised below the floor, so its category could empty out.")

	// Sharing a flavour is penalised too, but less than being the same thing.
	TEST_ASSERT(length(get_colony_incident_tags(/datum/colony_incident/refugee)), "The refugee incident reports no tags, so flavour cannot be compared.")
	var/tag_share_weight = SScampaign.get_incident_selection_weight(/datum/colony_incident/refugee)
	SScampaign.incident_history = list(list(
		"incident_id" = "incident-earlier",
		"incident_type" = "/datum/colony_incident/trader",
		"tags" = list(INCIDENT_TAG_ARRIVAL, INCIDENT_TAG_TRADE),
		"outcome" = COLONY_INCIDENT_OUTCOME_SUCCEEDED,
	))
	var/shared_flavour_weight = SScampaign.get_incident_selection_weight(/datum/colony_incident/refugee)
	TEST_ASSERT(shared_flavour_weight < tag_share_weight, "An incident sharing a flavour with the last one was not made less likely.")
	TEST_ASSERT(shared_flavour_weight > repeat_weight, "Sharing a flavour was penalised as hard as being the same incident.")

	// However much has happened, every category still has something it can offer.
	var/list/saturated = list()
	for(var/i in 1 to COLONY_INCIDENT_HISTORY_WINDOW * 2)
		saturated += list(list(
			"incident_id" = "incident-[i]",
			"incident_type" = "/datum/colony_incident/refugee",
			"tags" = list(INCIDENT_TAG_ARRIVAL, INCIDENT_TAG_WEATHER, INCIDENT_TAG_HARVEST, INCIDENT_TAG_TRADE, INCIDENT_TAG_UNREST),
			"outcome" = COLONY_INCIDENT_OUTCOME_FAILED,
		))
	SScampaign.incident_history = saturated

	for(var/incident_category in COLONY_INCIDENT_CATEGORIES)
		var/list/eligible = SScampaign.get_eligible_incident_types(incident_category)
		TEST_ASSERT(length(eligible), "The '[incident_category]' category ran dry after a run of incidents.")
		for(var/incident_type in eligible)
			TEST_ASSERT(SScampaign.get_incident_selection_weight(incident_type) > 0, "[incident_type] fell to a weight of nothing, so it could never be picked again.")

	// And the storyteller can still buy the gentler categories when the colony has had a hard time of it.
	for(var/gentle_category in list(COLONY_INCIDENT_CATEGORY_POSITIVE, COLONY_INCIDENT_CATEGORY_NEUTRAL))
		TEST_ASSERT(length(SScampaign.get_eligible_incident_types(gentle_category)), "No [gentle_category] incident remained available after a hard run, which is when one is most needed.")


/// The controls speak the storyteller's own tag vocabulary, so its existing multipliers apply to them.
/datum/unit_test/rimstation_incident_control_tags

/datum/unit_test/rimstation_incident_control_tags/Run()
	// Instantiated rather than read off the type: initial() yields nothing for a list variable, which is the
	// same trap that silently disabled the shared-flavour penalty.
	for(var/datum/round_event_control/colony_incident/control_type as anything in subtypesof(/datum/round_event_control/colony_incident))
		var/datum/round_event_control/colony_incident/control = new control_type
		allocated += control
		TEST_ASSERT(length(control.tags), "Incident control [control_type] carries no tags, so no storyteller can weight it.")


/**
 * A storm reads the planet it is happening on.
 *
 * The planet record has carried a `weather_set` since Phase 1 and nothing read it. An arid world should not be
 * throwing snow at the colony, and the fact that it does not is a property worth holding onto.
 */
/datum/unit_test/campaign_failure_path/rimstation_incident_storm_climate
	test_campaign_id = "unit-test-incident-storm"
	var/datum/planet_definition/saved_planet

/datum/unit_test/campaign_failure_path/rimstation_incident_storm_climate/Run()
	take_campaign()
	TEST_ASSERT(SScampaign.create_campaign(test_campaign_id, "admin-key"), "A campaign could not be created.")
	saved_planet = GLOB.rimstation_active_planet

	var/list/climates = list(
		"arid" = /datum/weather/sand_storm,
		"frozen" = /datum/weather/snow_storm,
		"temperate" = /datum/weather/particle/rain_storm,
	)

	for(var/climate in climates)
		var/datum/planet_definition/planet = new("seed-[climate]", "test-[climate]")
		planet.weather_set = climate
		GLOB.rimstation_active_planet = planet

		var/datum/colony_incident/storm/storm = new
		allocated += storm
		storm.select_target()
		TEST_ASSERT_EQUAL(storm.storm_type, climates[climate], "A '[climate]' world produced the wrong weather.")

	// An unknown climate still produces a survivable storm rather than none at all.
	var/datum/planet_definition/strange = new("seed-strange", "test-strange")
	strange.weather_set = "something nobody has written yet"
	GLOB.rimstation_active_planet = strange
	var/datum/colony_incident/storm/fallback = new
	allocated += fallback
	fallback.select_target()
	TEST_ASSERT_NOTNULL(fallback.storm_type, "An unrecognised climate produced no weather at all.")

/datum/unit_test/campaign_failure_path/rimstation_incident_storm_climate/Destroy()
	GLOB.rimstation_active_planet = saved_planet
	saved_planet = null
	return ..()
