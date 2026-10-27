/**
 * The quarian helmet, which ships bare and takes two modules.
 *
 * A welding mask fits behind the faceplate and a torch clips to the side. Neither is present out of the
 * box, so a fresh helmet cannot lower its visor and has no light. The icon state carries both as
 * "<base>-<visor down>-<light on>", which is why base_icon_state is set on every colour.
 */
/obj/item/clothing/head/helmet/space/quarian
	name = "quarian helmet"
	desc = "The standard quarian helmet, sealed against the bacteria and viruses of the outside world. \
		There is a bracket for a welding mask behind the faceplate and a clip for a torch on the side."
	icon = 'modular_rimstation/icons/obj/clothing/quarian_helmets.dmi'
	worn_icon = 'modular_rimstation/icons/mob/clothing/quarian_helmets.dmi'
	icon_state = "helmet-0-0"
	// No quarian in-hand art exists, so naming a state here only picks the generic fallback. Subtypes
	// inherit the null rather than naming their own colour.
	inhand_icon_state = null
	base_icon_state = "helmet"
	// No HEADINTERNALS: a quarian still needs a breath mask under this, the same as in the source build.
	clothing_flags = STOPSPRESSUREDAMAGE | THICKMATERIAL | SNUG_FIT | STACKABLE_HELMET_EXEMPT
	armor_type = /datum/armor/quarian_envirosuit
	// These are what the welding visor grants. Initialize() raises the visor, which zeroes them.
	flash_protect = FLASH_PROTECTION_WELDER
	tint = 2
	visor_flags = NONE
	visor_flags_inv = NONE
	visor_flags_cover = NONE
	visor_vars_to_toggle = VISOR_FLASHPROTECT | VISOR_TINT
	light_system = OVERLAY_LIGHT_DIRECTIONAL
	light_range = 4
	light_power = 0.8
	light_on = FALSE
	actions_types = list(/datum/action/item_action/toggle_helmet_light, /datum/action/item_action/toggle_welding_screen)
	/// The welding mask fitted behind the faceplate, if any. Without it the visor will not come down.
	var/obj/item/clothing/mask/gas/welding/welding_mask
	/// The torch clipped to the side, if any.
	var/obj/item/flashlight/torch

/obj/item/clothing/head/helmet/space/quarian/Initialize(mapload)
	. = ..()
	// Starts with the visor up, so the welding tint and flash protection are off until one is fitted.
	visor_toggling()
	update_appearance()
	register_context()

/obj/item/clothing/head/helmet/space/quarian/Destroy()
	QDEL_NULL(welding_mask)
	QDEL_NULL(torch)
	return ..()

/obj/item/clothing/head/helmet/space/quarian/examine(mob/user)
	. = ..()
	. += span_notice(welding_mask ? "A welding mask is fitted behind the faceplate. A crowbar would lever it out." : "The welding mask bracket is empty.")
	. += span_notice(torch ? "[torch] is clipped to the side. A screwdriver would free it." : "The torch clip is empty.")

/obj/item/clothing/head/helmet/space/quarian/add_context(atom/source, list/context, obj/item/held_item, mob/living/user)
	context[SCREENTIP_CONTEXT_ALT_LMB] = "Toggle welding screen"
	return CONTEXTUAL_SCREENTIP_SET

/obj/item/clothing/head/helmet/space/quarian/click_alt(mob/user)
	adjust_visor(user)
	return CLICK_ACTION_SUCCESS

/obj/item/clothing/head/helmet/space/quarian/ui_action_click(mob/user, action)
	if(istype(action, /datum/action/item_action/toggle_welding_screen))
		adjust_visor(user)
		return
	if(istype(action, /datum/action/item_action/toggle_helmet_light))
		toggle_torch(user)
		return
	return ..()

/obj/item/clothing/head/helmet/space/quarian/adjust_visor(mob/living/user)
	if(!welding_mask)
		balloon_alert(user, "no welding mask fitted!")
		return FALSE

	. = ..()
	if(!.)
		return

	// The torch sits outside the visor, so lowering it blocks the beam.
	if(!up && light_on)
		set_light_on(FALSE)
		balloon_alert(user, "torch blocked")
	playsound(src, up ? SFX_VISOR_UP : SFX_VISOR_DOWN, 50, TRUE)
	update_appearance()

/obj/item/clothing/head/helmet/space/quarian/proc/toggle_torch(mob/living/user)
	if(!torch)
		balloon_alert(user, "no torch fitted!")
		return
	if(!up)
		balloon_alert(user, "visor is down!")
		return

	set_light_on(!light_on)
	playsound(user, light_on ? 'sound/items/weapons/magin.ogg' : 'sound/items/weapons/magout.ogg', 40, TRUE)
	update_appearance()

/obj/item/clothing/head/helmet/space/quarian/item_interaction(mob/living/user, obj/item/tool, list/modifiers)
	if(istype(tool, /obj/item/clothing/mask/gas/welding))
		if(welding_mask)
			balloon_alert(user, "bracket already full!")
			return ITEM_INTERACT_BLOCKING
		if(!user.transferItemToLoc(tool, src))
			return ITEM_INTERACT_BLOCKING
		welding_mask = tool
		balloon_alert(user, "welding mask fitted")
		return ITEM_INTERACT_SUCCESS

	if(istype(tool, /obj/item/flashlight))
		if(torch)
			balloon_alert(user, "clip already full!")
			return ITEM_INTERACT_BLOCKING
		if(!user.transferItemToLoc(tool, src))
			return ITEM_INTERACT_BLOCKING
		torch = tool
		balloon_alert(user, "torch clipped on")
		return ITEM_INTERACT_SUCCESS

	return NONE

/obj/item/clothing/head/helmet/space/quarian/crowbar_act(mob/living/user, obj/item/tool)
	if(!welding_mask)
		return NONE

	// Raise the visor first, or the helmet keeps the tint with no mask left to justify it.
	if(!up)
		visor_toggling()
	var/obj/item/removed = welding_mask
	welding_mask = null
	user.put_in_hands(removed)
	tool.play_tool_sound(src)
	balloon_alert(user, "welding mask removed")
	update_appearance()
	return ITEM_INTERACT_SUCCESS

/obj/item/clothing/head/helmet/space/quarian/screwdriver_act(mob/living/user, obj/item/tool)
	if(!torch)
		return NONE

	set_light_on(FALSE)
	var/obj/item/removed = torch
	torch = null
	user.put_in_hands(removed)
	tool.play_tool_sound(src)
	balloon_alert(user, "torch removed")
	update_appearance()
	return ITEM_INTERACT_SUCCESS

/obj/item/clothing/head/helmet/space/quarian/update_icon_state()
	// Parent first: /helmet/space sets icon_state itself, so setting ours before it would be undone.
	. = ..()
	icon_state = "[base_icon_state]-[up ? 0 : 1]-[light_on ? 1 : 0]"

/obj/item/clothing/head/helmet/space/quarian/white
	name = "white quarian helmet"
	icon_state = "helmet-white-0-0"
	base_icon_state = "helmet-white"

/obj/item/clothing/head/helmet/space/quarian/black
	name = "black quarian helmet"
	icon_state = "helmet-black-0-0"
	base_icon_state = "helmet-black"

/obj/item/clothing/head/helmet/space/quarian/red
	name = "red quarian helmet"
	icon_state = "helmet-red-0-0"
	base_icon_state = "helmet-red"

/obj/item/clothing/head/helmet/space/quarian/orange
	name = "orange quarian helmet"
	icon_state = "helmet-orange-0-0"
	base_icon_state = "helmet-orange"

/obj/item/clothing/head/helmet/space/quarian/yellow
	name = "yellow quarian helmet"
	icon_state = "helmet-yellow-0-0"
	base_icon_state = "helmet-yellow"

/obj/item/clothing/head/helmet/space/quarian/green
	name = "green quarian helmet"
	icon_state = "helmet-green-0-0"
	base_icon_state = "helmet-green"

/obj/item/clothing/head/helmet/space/quarian/blue
	name = "blue quarian helmet"
	icon_state = "helmet-blue-0-0"
	base_icon_state = "helmet-blue"

/obj/item/clothing/head/helmet/space/quarian/violet
	name = "violet quarian helmet"
	icon_state = "helmet-violet-0-0"
	base_icon_state = "helmet-violet"
