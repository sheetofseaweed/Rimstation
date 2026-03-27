/obj/item/holochip/get_save_vars(save_flags=ALL)
	. = ..()
	. += NAMEOF(src, credits)
	return .

/obj/item/stack/spacecash/get_save_vars(save_flags=ALL)
	. = ..()
	. += NAMEOF(src, amount)
	. += NAMEOF(src, value)
	return .

/obj/item/stack/spacecash/PersistentInitialize()
	. = ..()
	update_appearance()

/obj/machinery/computer/bank_machine/on_object_saved(map_string, turf/current_loc)
	var/total_credits = synced_bank_account?.account_balance || 0
	if(total_credits < 0)
		return

	var/obj/item/holochip/typepath = /obj/item/holochip
	var/list/variables = list()
	TGM_ADD_TYPEPATH_VAR(variables, typepath, credits, total_credits)
	TGM_MAP_BLOCK(map_string, typepath, generate_tgm_typepath_metadata(variables))

/obj/machinery/computer/bank_machine/PersistentInitialize()
	. = ..()
	if(!synced_bank_account)
		return

	var/total_credits = 0
	for(var/obj/item/holochip/holochip in loc)
		total_credits += holochip.credits
		qdel(holochip)

	if(total_credits > 0)
		synced_bank_account.adjust_money(total_credits)
