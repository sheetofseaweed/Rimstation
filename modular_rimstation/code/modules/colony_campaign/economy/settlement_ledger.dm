/**
 * What the settlement owns, and an account of how it came to own it.
 *
 * Deliberately not a second economy. Credits, debt and the refusal to spend money you do not have are already
 * `/datum/bank_account`, and every console, vendor and payment component in the game speaks that. So the
 * ledger drives the real account and adds the two things a campaign needs that a shift does not:
 *
 * - **It survives.** Bank accounts are rebuilt every round, so a colony that ends a chapter with 4000 credits
 *   would start the next one with whatever a fresh shift is granted.
 * - **It remembers why.** `transaction_history` keeps the last twenty entries as amount-and-reason, which is
 *   fine for a shift and useless for arguing about what happened three chapters ago. Ledger entries are
 *   append-only and carry who, when, under what category and against which incident or trade.
 *
 * Resources are tracked here rather than read from a silo because the map save does not carry them: object
 * serialization stores a whitelist of vars, and a material container is a component, so a silo returns empty.
 */
/datum/settlement_ledger
	var/schema_version = COLONY_LEDGER_SCHEMA_VERSION
	/// Credits, in whole units. Mirrors the settlement's bank account between chapters.
	var/credits = 0
	/// Outstanding debt, in whole units.
	var/debt = 0
	/// Material id to whole units held by the settlement.
	var/list/resources
	/// Append-only account of every change. Never rewritten, never truncated.
	var/list/entries
	/// Number the next entry will take. Entry ids are stable within a campaign.
	var/next_entry_number = 1

/datum/settlement_ledger/New()
	. = ..()
	resources = list()
	entries = list()

/**
 * Appends one audit entry. Returns the entry, or null if it was refused.
 *
 * Private by convention: entries are written by the mutators below *after* the thing they describe has
 * actually happened, so the ledger can never claim a payment that was refused.
 */
/datum/settlement_ledger/proc/record_entry(category, reason_code, amount, resource_id, actor_id, related_id, campaign_clock)
	if(!category || !reason_code)
		return null

	var/list/entry = list(
		"id" = next_entry_number,
		"campaign_clock" = isnum(campaign_clock) ? campaign_clock : 0,
		"category" = category,
		"reason_code" = reason_code,
		"amount" = isnum(amount) ? amount : 0,
		"resource_id" = resource_id,
		"actor_id" = actor_id,
		"related_id" = related_id,
		"recorded_at" = "[world.realtime]",
	)
	next_entry_number++
	entries += list(entry)
	return entry

/// TRUE when `amount` is a usable whole quantity. Balances are integers so they cannot drift by rounding.
/datum/settlement_ledger/proc/is_whole_amount(amount)
	return isnum(amount) && amount > 0 && amount == round(amount)

/**
 * Spends credits. Returns TRUE only if the settlement had them.
 *
 * The account decides, not the ledger: `adjust_money()` refuses a debit it cannot cover, and only once it has
 * agreed does an entry get written.
 */
/datum/settlement_ledger/proc/try_debit(datum/bank_account/account, amount, category, reason_code, actor_id, related_id, campaign_clock)
	if(!is_whole_amount(amount))
		return FALSE
	if(!istype(account))
		return FALSE
	if(!account.adjust_money(-amount, "[category]: [reason_code]"))
		return FALSE

	credits = account.account_balance
	debt = account.account_debt
	record_entry(category, reason_code, -amount, null, actor_id, related_id, campaign_clock)
	return TRUE

/// Adds credits. Debt collection is the account's business, so the balance is read back rather than assumed.
/datum/settlement_ledger/proc/credit(datum/bank_account/account, amount, category, reason_code, actor_id, related_id, campaign_clock)
	if(!is_whole_amount(amount))
		return FALSE
	if(!istype(account))
		return FALSE
	if(!account.adjust_money(amount, "[category]: [reason_code]"))
		return FALSE

	credits = account.account_balance
	debt = account.account_debt
	record_entry(category, reason_code, amount, null, actor_id, related_id, campaign_clock)
	return TRUE

/**
 * Moves a resource quantity. Returns TRUE if the change was applied.
 *
 * Refuses to take more than the settlement holds, so a resource can never go negative - a colony cannot owe
 * iron the way it can owe money, and a negative pile would silently become free material on the next credit.
 */
/datum/settlement_ledger/proc/adjust_resource(resource_id, amount, category, reason_code, actor_id, related_id, campaign_clock)
	if(!resource_id || !isnum(amount) || !amount || amount != round(amount))
		return FALSE

	var/held = resources[resource_id] || 0
	if(held + amount < 0)
		return FALSE

	resources[resource_id] = held + amount
	record_entry(category, reason_code, amount, resource_id, actor_id, related_id, campaign_clock)
	return TRUE

/// Records something that changed nothing financial but belongs in the account of the chapter.
/datum/settlement_ledger/proc/record_nonfinancial(category, reason_code, actor_id, related_id, campaign_clock)
	return !isnull(record_entry(category, reason_code, 0, null, actor_id, related_id, campaign_clock))

/// How much of a resource the settlement holds.
/datum/settlement_ledger/proc/get_resource(resource_id)
	return resources[resource_id] || 0

/// Reads the settlement's balance and debt out of its live account.
/datum/settlement_ledger/proc/capture_from(datum/bank_account/account)
	if(!istype(account))
		return FALSE
	credits = round(account.account_balance)
	debt = round(account.account_debt)
	return TRUE

/**
 * Puts the settlement's balance and debt back into a fresh account.
 *
 * Set rather than added: a new round grants an account its standard starting budget, and the colony's money is
 * what it actually had, not that budget plus its savings.
 */
/datum/settlement_ledger/proc/restore_into(datum/bank_account/account)
	if(!istype(account))
		return FALSE
	account.account_balance = credits
	account.account_debt = debt
	return TRUE

/datum/settlement_ledger/proc/serialize()
	RETURN_TYPE(/list)
	return list(
		"schema_version" = schema_version,
		"credits" = credits,
		"debt" = debt,
		"resources" = resources.Copy(),
		"entries" = entries.Copy(),
		"next_entry_number" = next_entry_number,
	)

/**
 * Loads a ledger record. Returns TRUE on success.
 *
 * Balances come off disk, so they are validated rather than trusted: a hand-edited or corrupted record must
 * not hand the settlement a fortune, and a negative balance would be a debt the account system cannot express.
 */
/datum/settlement_ledger/proc/deserialize(list/data)
	if(!islist(data))
		return FALSE

	var/incoming_version = data["schema_version"]
	if(!isnum(incoming_version) || incoming_version != COLONY_LEDGER_SCHEMA_VERSION)
		log_game("Settlement ledger rejected: unsupported schema version '[incoming_version]'.")
		return FALSE

	var/incoming_credits = data["credits"]
	var/incoming_debt = data["debt"]
	if(!isnum(incoming_credits) || incoming_credits < 0 || !isnum(incoming_debt) || incoming_debt < 0)
		log_game("Settlement ledger rejected: balance '[incoming_credits]' or debt '[incoming_debt]' is unusable.")
		return FALSE

	var/list/incoming_resources = list()
	if(islist(data["resources"]))
		for(var/resource_id in data["resources"])
			var/held = data["resources"][resource_id]
			if(isnum(held) && held >= 0)
				incoming_resources[resource_id] = round(held)

	credits = round(incoming_credits)
	debt = round(incoming_debt)
	resources = incoming_resources
	entries = islist(data["entries"]) ? data["entries"] : list()
	next_entry_number = isnum(data["next_entry_number"]) ? data["next_entry_number"] : (length(entries) + 1)
	return TRUE

/// A stable fingerprint of this ledger, so a checkpoint can prove the copy it holds is the one it wrote.
/datum/settlement_ledger/proc/get_hash()
	return hash_campaign_ledger_record(serialize())

/**
 * Fingerprint of a serialized ledger record.
 *
 * Taken over the record rather than the datum so it can be computed against a copy read back off disk, which
 * is the whole point: the same accounts must hash the same whether they are in memory or in a file.
 */
/proc/hash_campaign_ledger_record(list/record)
	return rustg_hash_string(RUSTG_HASH_SHA256, json_encode(islist(record) ? record : list()))


/// The account the settlement's money lives in. The cargo budget, because that is what buys things already.
/proc/get_settlement_account()
	RETURN_TYPE(/datum/bank_account)
	return SSeconomy.get_dep_account(CAMPAIGN_LEDGER_ACCOUNT)


/**
 * The ledger as a console shows it.
 *
 * Entries newest first and capped, because the list is append-only for the life of a campaign and nobody wants
 * to scroll through three chapters of upkeep to find out what the last expedition brought back. The total is
 * sent alongside so the interface can say how much it is not showing rather than pretending that is all of it.
 *
 * The live balance comes from the account rather than the stored figure: between chapter start and commit the
 * account is what people are actually spending, so the stored number is only correct at the moments either
 * side of that.
 */
/datum/settlement_ledger/proc/build_readout(max_entries = 24)
	RETURN_TYPE(/list)
	var/datum/bank_account/account = get_settlement_account()

	var/list/recent = list()
	var/shown = 0
	for(var/index = length(entries) to 1 step -1)
		if(shown >= max_entries)
			break
		var/list/entry = entries[index]
		UNTYPED_LIST_ADD(recent, list(
			"id" = entry["id"],
			"clock" = entry["campaign_clock"],
			"category" = entry["category"],
			"reason" = entry["reason_code"],
			"amount" = entry["amount"],
			"resource" = entry["resource_id"],
			"actor" = entry["actor_id"],
			"related" = entry["related_id"],
		))
		shown++

	var/list/held = list()
	for(var/resource_id in resources)
		if(resources[resource_id])
			held[resource_id] = resources[resource_id]

	return list(
		"credits" = account ? round(account.account_balance) : credits,
		"debt" = account ? round(account.account_debt) : debt,
		"stored_credits" = credits,
		"resources" = held,
		"entries" = recent,
		"entry_count" = length(entries),
	)
