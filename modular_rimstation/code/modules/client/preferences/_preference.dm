/datum/preference/is_accessible(datum/preferences/preferences)
	. = ..()
	if(.)
		return
	if(!is_interaction_menu_preference())
		return
	for(var/datum/tgui/ui in preferences.parent?.mob?.tgui_open_uis)
		if(ui.interface == "InteractionPanel")
			return TRUE

/datum/preference/proc/is_interaction_menu_preference()
	return type == /datum/preference/toggle/master_erp_preferences \
		|| ispath(type, /datum/preference/toggle/erp) \
		|| type == /datum/preference/blob/favorite_interactions \
		|| type == /datum/preference/choiced/erp_status \
		|| type == /datum/preference/choiced/erp_status_nc \
		|| type == /datum/preference/choiced/erp_status_v \
		|| type == /datum/preference/choiced/erp_status_extm \
		|| type == /datum/preference/choiced/erp_status_extmharm \
		|| type == /datum/preference/choiced/erp_status_unholy \
		|| type == /datum/preference/toggle/erp/vore_enable \
		|| type == /datum/preference/toggle/erp/vore_overlays \
		|| type == /datum/preference/toggle/erp/vore_overlay_options
