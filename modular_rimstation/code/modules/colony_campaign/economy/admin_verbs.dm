/**
 * Moves the settlement's money or materials, and says in the ledger that an admin did it.
 *
 * Goes through the ordinary mutators rather than writing the balance directly, so the bank account stays the
 * authority on what the colony can afford and the movement leaves the same audit trail as any other. An
 * adjustment nobody can find afterwards is worse than no adjustment: the ledger is what a later chapter reads
 * to explain where the money went.
 */
ADMIN_VERB(rimstation_adjust_colony_ledger, R_ADMIN, "Adjust Colony Ledger", "Credits or debits the settlement's money or materials, with an audit entry.", ADMIN_CATEGORY_COLONY)
	var/datum/settlement_ledger/ledger = SScampaign.get_ledger()
	if(!ledger)
		to_chat(user, span_warning("No campaign is loaded, so there is no settlement ledger."))
		return

	to_chat(user, boxed_message(span_notice(build_colony_ledger_summary(ledger))))

	var/list/what = list("Credits" = "credits", "A material" = "resource")
	var/kind = tgui_input_list(user, "What is being adjusted?", "Colony Ledger", what)
	if(isnull(kind))
		return
	kind = what[kind]

	var/resource_id
	if(kind == "resource")
		resource_id = tgui_input_text(user, "Which material? Use the id the ledger already lists, or a new one.", "Colony Ledger", max_length = MAX_NAME_LEN)
		if(!resource_id)
			return

	var/amount = tgui_input_number(user, "How much? Negative takes it away.", "Colony Ledger", default = 0, max_value = 1000000, min_value = -1000000, round_value = TRUE)
	if(isnull(amount) || !amount)
		return

	var/reason = tgui_input_text(user, "Why? This is written into the ledger.", "Colony Ledger", max_length = MAX_MESSAGE_LEN)
	if(!reason)
		return

	var/worked = FALSE
	if(kind == "credits")
		worked = amount > 0 \
			? SScampaign.credit(amount, LEDGER_CATEGORY_ADMIN, reason, key_name(user)) \
			: SScampaign.try_debit(-amount, LEDGER_CATEGORY_ADMIN, reason, key_name(user))
		if(!worked && amount < 0)
			to_chat(user, span_warning("The settlement could not cover that. Its account refused the debit."))
			return
	else
		worked = SScampaign.adjust_resource(resource_id, amount, LEDGER_CATEGORY_ADMIN, reason, key_name(user))
		if(!worked)
			to_chat(user, span_warning("That adjustment was refused. The settlement may not hold that much of '[resource_id]'."))
			return

	if(!worked)
		to_chat(user, span_warning("The adjustment was refused. Check the game log."))
		return

	var/what_moved = (kind == "credits") ? "[amount] credits" : "[amount] of '[resource_id]'"
	message_admins("[key_name_admin(user)] adjusted the colony ledger by [what_moved]: [reason]")
	log_admin("[key_name(user)] adjusted the colony ledger by [what_moved]: [reason]")
	to_chat(user, span_notice("Ledger adjusted by [what_moved]."))


/**
 * Throws away the ledger's history, keeping the balances it describes.
 *
 * The ledger is append-only by design, and that is worth defending: it is how a colony three chapters later
 * explains where its money went. This exists for the case the design does not cover - a log polluted by
 * testing, or by a bug that wrote a thousand entries - where the history is not worth keeping and scrolling
 * past it costs more than it is worth.
 *
 * Balances are deliberately untouched. Clearing the account of what it owns is a different act, and one the
 * adjust verb above already does with an entry to show for it.
 */
ADMIN_VERB(rimstation_clear_colony_ledger, R_ADMIN, "Clear Colony Ledger History", "Deletes the ledger's audit entries. Balances and materials are kept.", ADMIN_CATEGORY_COLONY)
	var/datum/settlement_ledger/ledger = SScampaign.get_ledger()
	if(!ledger)
		to_chat(user, span_warning("No campaign is loaded, so there is no settlement ledger."))
		return

	var/count = length(ledger.entries)
	if(!count)
		to_chat(user, span_notice("The ledger has no entries to clear."))
		return

	if(tgui_alert(user, "Delete all [count] ledger entries? Balances are kept. This cannot be undone, and the campaign loses its record of how it got here.", "Colony Ledger", list("Delete", "Cancel")) != "Delete")
		return

	ledger.entries = list()
	// The counter is not rewound. Entry ids stay unique for the life of the campaign, so an id quoted in a log
	// or in an old incident record still means the one thing it always meant.
	SScampaign.sync_ledger()

	message_admins(span_boldwarning("[key_name_admin(user)] cleared [count] entries from the colony ledger. Balances were kept."))
	log_admin("[key_name(user)] cleared [count] entries from the colony ledger.")
	to_chat(user, span_notice("Cleared [count] ledger entries."))


/// Reports what the settlement is holding and what it has been doing, without changing any of it.
ADMIN_VERB(rimstation_inspect_colony_ledger, R_ADMIN, "Inspect Colony Ledger", "Reports the settlement's balance, materials and recent entries.", ADMIN_CATEGORY_COLONY_DEBUG)
	var/datum/settlement_ledger/ledger = SScampaign.get_ledger()
	if(!ledger)
		to_chat(user, span_warning("No campaign is loaded, so there is no settlement ledger."))
		return

	to_chat(user, boxed_message(span_notice(build_colony_ledger_summary(ledger, show_entries = 12))))


/// Shared readout for the verbs above. Newest entries first, because that is what anybody is looking for.
/proc/build_colony_ledger_summary(datum/settlement_ledger/ledger, show_entries = 0)
	var/datum/bank_account/account = get_settlement_account()
	var/list/lines = list()
	lines += "Balance: [account ? account.account_balance : ledger.credits] credits. Debt: [ledger.debt]."
	lines += "Entries recorded: [length(ledger.entries)]. Next entry id: [ledger.next_entry_number]."

	if(length(ledger.resources))
		var/list/held = list()
		for(var/resource_id in ledger.resources)
			held += "[resource_id]: [ledger.resources[resource_id]]"
		lines += "Materials: [held.Join(", ")]"
	else
		lines += "Materials: none held."

	if(show_entries)
		lines += "---"
		var/shown = 0
		for(var/index = length(ledger.entries) to 1 step -1)
			if(shown >= show_entries)
				break
			var/list/entry = ledger.entries[index]
			var/moved = entry["resource_id"] ? "[entry["amount"]] [entry["resource_id"]]" : "[entry["amount"]] cr"
			lines += "#[entry["id"]] [entry["category"]]/[entry["reason_code"]] [moved][entry["actor_id"] ? " by [entry["actor_id"]]" : ""]"
			shown++

	return lines.Join("\n")
