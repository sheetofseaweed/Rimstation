/**
 * The settlement's money is the game's money, and the ledger is the account of what happened to it.
 *
 * The ledger deliberately does not implement balances - `/datum/bank_account` already refuses a debit it
 * cannot cover, and every console and vendor speaks it. So these assertions are about the two things the
 * ledger is actually for: that it never records a payment the account refused, and that what it records
 * survives the round.
 */
/datum/unit_test/rimstation_settlement_ledger_spending

/datum/unit_test/rimstation_settlement_ledger_spending/Run()
	var/datum/settlement_ledger/ledger = new
	allocated += ledger
	var/datum/bank_account/account = new("Settlement Test", null, 1, FALSE)
	account.account_balance = 1000

	// Spending what the settlement has.
	TEST_ASSERT(ledger.try_debit(account, 400, LEDGER_CATEGORY_TRADE, "bought seed stock", "actor-1", "trade-1", 50), "A debit the settlement could afford was refused.")
	TEST_ASSERT_EQUAL(account.account_balance, 600, "The debit did not come out of the settlement's account.")
	TEST_ASSERT_EQUAL(ledger.credits, 600, "The ledger did not follow the account's balance.")
	TEST_ASSERT_EQUAL(length(ledger.entries), 1, "A completed debit was not recorded.")

	// Spending what it does not have changes nothing, and records nothing.
	TEST_ASSERT(!ledger.try_debit(account, 5000, LEDGER_CATEGORY_TRADE, "bought a shuttle", "actor-1", "trade-2", 60), "The settlement spent money it did not have.")
	TEST_ASSERT_EQUAL(account.account_balance, 600, "A refused debit still moved money.")
	TEST_ASSERT_EQUAL(length(ledger.entries), 1, "A refused debit was written into the ledger anyway.")

	// Balances are whole numbers, so they cannot drift by rounding.
	TEST_ASSERT(!ledger.try_debit(account, 10.5, LEDGER_CATEGORY_TRADE, "fractional", null, null, 60), "A fractional debit was accepted.")
	TEST_ASSERT(!ledger.try_debit(account, -100, LEDGER_CATEGORY_TRADE, "negative", null, null, 60), "A negative debit was accepted, which would be a credit in disguise.")
	TEST_ASSERT(!ledger.credit(account, 0, LEDGER_CATEGORY_TRADE, "nothing", null, null, 60), "A credit of nothing was recorded.")
	TEST_ASSERT_EQUAL(length(ledger.entries), 1, "A refused amount was written into the ledger.")

	// Income.
	TEST_ASSERT(ledger.credit(account, 250, LEDGER_CATEGORY_SALVAGE, "sold scrap", "actor-2", null, 70), "A credit was refused.")
	TEST_ASSERT_EQUAL(account.account_balance, 850, "The credit did not reach the settlement's account.")
	TEST_ASSERT_EQUAL(length(ledger.entries), 2, "The credit was not recorded.")

	// Every entry carries who, when, under what heading, and against what.
	var/list/entry = ledger.entries[1]
	TEST_ASSERT_EQUAL(entry["id"], 1, "Ledger entries are not numbered from one.")
	TEST_ASSERT_EQUAL(entry["category"], LEDGER_CATEGORY_TRADE, "A ledger entry did not record its category.")
	TEST_ASSERT_EQUAL(entry["reason_code"], "bought seed stock", "A ledger entry did not record its reason.")
	TEST_ASSERT_EQUAL(entry["amount"], -400, "A debit was not recorded as a negative amount.")
	TEST_ASSERT_EQUAL(entry["actor_id"], "actor-1", "A ledger entry did not record who acted.")
	TEST_ASSERT_EQUAL(entry["related_id"], "trade-1", "A ledger entry did not record what it related to.")
	TEST_ASSERT_EQUAL(entry["campaign_clock"], 50, "A ledger entry did not record when in the campaign it happened.")

	// Entry ids keep climbing; an entry is never renumbered or overwritten.
	var/list/second = ledger.entries[2]
	TEST_ASSERT_EQUAL(second["id"], 2, "Ledger entry ids do not increase.")


/// Resources are counted in whole units and can never go negative.
/datum/unit_test/rimstation_settlement_ledger_resources

/datum/unit_test/rimstation_settlement_ledger_resources/Run()
	var/datum/settlement_ledger/ledger = new
	allocated += ledger

	TEST_ASSERT(ledger.adjust_resource("iron", 50, LEDGER_CATEGORY_SALVAGE, "recovered from a wreck", null, null, 10), "A resource gain was refused.")
	TEST_ASSERT_EQUAL(ledger.get_resource("iron"), 50, "A resource gain was not recorded.")

	TEST_ASSERT(ledger.adjust_resource("iron", -20, LEDGER_CATEGORY_UPKEEP, "repairs", null, null, 20), "Spending a resource the settlement held was refused.")
	TEST_ASSERT_EQUAL(ledger.get_resource("iron"), 30, "Spending a resource did not reduce the holding.")

	// A colony cannot owe iron the way it can owe money.
	TEST_ASSERT(!ledger.adjust_resource("iron", -500, LEDGER_CATEGORY_UPKEEP, "overspend", null, null, 30), "The settlement spent more of a resource than it held.")
	TEST_ASSERT_EQUAL(ledger.get_resource("iron"), 30, "A refused resource spend still changed the holding.")
	TEST_ASSERT_EQUAL(length(ledger.entries), 2, "A refused resource spend was recorded.")

	TEST_ASSERT(!ledger.adjust_resource("iron", 2.5, LEDGER_CATEGORY_SALVAGE, "fractional", null, null, 40), "A fractional resource quantity was accepted.")
	TEST_ASSERT_EQUAL(ledger.get_resource("glass"), 0, "A resource the settlement has never held did not report as zero.")

	// Something worth remembering that moved nothing.
	TEST_ASSERT(ledger.record_nonfinancial(LEDGER_CATEGORY_INCIDENT, "refugees turned away", "actor-3", "incident-7", 50), "A non-financial event could not be recorded.")
	var/list/entry = ledger.entries[length(ledger.entries)]
	TEST_ASSERT_EQUAL(entry["amount"], 0, "A non-financial entry recorded an amount.")
	TEST_ASSERT_EQUAL(entry["related_id"], "incident-7", "A non-financial entry lost what it related to.")


/// What the settlement owns has to survive the round that earned it.
/datum/unit_test/rimstation_settlement_ledger_persistence

/datum/unit_test/rimstation_settlement_ledger_persistence/Run()
	var/datum/settlement_ledger/original = new
	allocated += original
	var/datum/bank_account/account = new("Settlement Test", null, 1, FALSE)
	account.account_balance = 900

	original.try_debit(account, 300, LEDGER_CATEGORY_TRADE, "bought tools", "actor-1", "trade-1", 100)
	original.adjust_resource("iron", 40, LEDGER_CATEGORY_SALVAGE, "salvage", null, null, 110)

	var/datum/settlement_ledger/restored = new
	allocated += restored
	TEST_ASSERT(restored.deserialize(json_decode(json_encode(original.serialize()))), "A ledger did not survive a JSON round trip.")
	TEST_ASSERT_EQUAL(restored.credits, original.credits, "Restoring the settlement lost its balance.")
	TEST_ASSERT_EQUAL(restored.get_resource("iron"), 40, "Restoring the settlement lost its materials.")
	TEST_ASSERT_EQUAL(length(restored.entries), length(original.entries), "Restoring the settlement lost its history.")
	TEST_ASSERT_EQUAL(restored.next_entry_number, original.next_entry_number, "A restored ledger would reuse entry ids already spent.")
	TEST_ASSERT_EQUAL(restored.get_hash(), original.get_hash(), "A ledger that survived a round trip did not hash the same, so a checkpoint could not verify it.")

	// Restoring puts the money back into a fresh round's account rather than adding to it.
	var/datum/bank_account/next_chapter = new("Settlement Test", null, 1, FALSE)
	next_chapter.account_balance = 5000
	TEST_ASSERT(restored.restore_into(next_chapter), "A settlement's balance could not be restored into a new round's account.")
	TEST_ASSERT_EQUAL(next_chapter.account_balance, 600, "Restoring added the settlement's savings to a fresh budget instead of replacing it.")

	// Records come off disk, so nonsense is refused rather than made real.
	var/datum/settlement_ledger/guarded = new
	allocated += guarded
	TEST_ASSERT(!guarded.deserialize(null), "A null ledger record was accepted.")
	var/list/from_the_future = original.serialize()
	from_the_future["schema_version"] = COLONY_LEDGER_SCHEMA_VERSION + 1
	TEST_ASSERT(!guarded.deserialize(from_the_future), "A ledger from an unknown schema was accepted.")
	var/list/in_the_red = original.serialize()
	in_the_red["credits"] = -100000
	TEST_ASSERT(!guarded.deserialize(in_the_red), "A ledger claiming a negative balance was accepted.")
	var/list/bad_resources = original.serialize()
	bad_resources["resources"] = list("iron" = -50, "glass" = "lots")
	TEST_ASSERT(guarded.deserialize(bad_resources), "A ledger with an unusable resource pile was refused outright.")
	TEST_ASSERT_EQUAL(guarded.get_resource("iron"), 0, "A negative resource holding was restored.")
	TEST_ASSERT_EQUAL(guarded.get_resource("glass"), 0, "A non-numeric resource holding was restored.")


/// The campaign is the only thing that moves the settlement's money, and it writes down every move.
/datum/unit_test/campaign_failure_path/rimstation_settlement_ledger_through_campaign
	test_campaign_id = "unit-test-ledger"

/datum/unit_test/campaign_failure_path/rimstation_settlement_ledger_through_campaign/Run()
	take_campaign()
	TEST_ASSERT(SScampaign.create_campaign(test_campaign_id, "admin-key"), "A campaign could not be created.")

	var/datum/bank_account/account = get_settlement_account()
	TEST_ASSERT_NOTNULL(account, "The settlement has no bank account, so it has nowhere to keep its money.")
	account.account_balance = 2000

	var/datum/settlement_ledger/settlement = SScampaign.get_ledger()
	TEST_ASSERT_NOTNULL(settlement, "A running campaign has no ledger.")
	settlement.capture_from(account)

	TEST_ASSERT(SScampaign.try_debit(500, LEDGER_CATEGORY_TRADE, "bought supplies", "actor-1", "trade-1"), "The campaign could not spend money the settlement had.")
	TEST_ASSERT_EQUAL(account.account_balance, 1500, "Spending through the campaign did not move the real account.")
	TEST_ASSERT(!SScampaign.try_debit(999999, LEDGER_CATEGORY_TRADE, "bought a moon", "actor-1", "trade-2"), "The campaign spent money the settlement did not have.")

	TEST_ASSERT(SScampaign.credit(250, LEDGER_CATEGORY_SALVAGE, "sold salvage", "actor-2", null), "The campaign could not credit the settlement.")
	TEST_ASSERT(SScampaign.adjust_resource("iron", 30, LEDGER_CATEGORY_SALVAGE, "recovered iron", "actor-2", null), "The campaign could not record a resource gain.")
	TEST_ASSERT(SScampaign.record_nonfinancial(LEDGER_CATEGORY_INCIDENT, "storm weathered", null, "incident-1"), "The campaign could not record a non-financial event.")

	// Every one of those reached the record that survives the round.
	TEST_ASSERT(length(SScampaign.manifest.ledger_record), "The manifest holds no ledger after the settlement spent money.")
	var/datum/settlement_ledger/from_manifest = new
	allocated += from_manifest
	TEST_ASSERT(from_manifest.deserialize(SScampaign.manifest.ledger_record), "The ledger in the manifest could not be read back.")
	TEST_ASSERT_EQUAL(length(from_manifest.entries), 4, "The manifest's ledger does not hold every recorded change.")
	TEST_ASSERT_EQUAL(from_manifest.get_resource("iron"), 30, "The manifest's ledger lost the settlement's materials.")

	// And a commit carries it into the checkpoint.
	TEST_ASSERT(SScampaign.resolve_chapter_at_round_end(), "The chapter could not be resolved.")
	TEST_ASSERT_EQUAL(SScampaign.campaign_state, CAMPAIGN_STATE_INTERMISSION, "The chapter did not commit.")

	var/datum/campaign_manifest/committed = load_active_campaign_manifest(test_campaign_id)
	allocated += committed
	var/datum/settlement_ledger/after_commit = new
	allocated += after_commit
	TEST_ASSERT(after_commit.deserialize(committed.ledger_record), "The committed campaign carries no readable ledger.")
	TEST_ASSERT_EQUAL(after_commit.credits, account.account_balance, "The committed ledger does not match the settlement's closing balance.")
	// Entries are assoc lists nested in a plain one, which is the shape a careless deep copy flattens on load.
	TEST_ASSERT_EQUAL(length(after_commit.entries), 4, "The committed ledger holds [length(after_commit.entries)] of the chapter's 4 entries.")
