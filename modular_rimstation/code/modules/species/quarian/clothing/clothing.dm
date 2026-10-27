/// Shared by every piece of the quarian enviro-suit. Sealed against infection, not against bullets.
/datum/armor/quarian_envirosuit
	bio = 100
	fire = 50
	acid = 65

/// Same suit, but jumpsuit armor must descend from clothing_under. The numbers are duplicated rather than
/// inherited because gloves_and_shoes_armor rejects the wound value this parent adds.
/datum/armor/clothing_under/quarian_envirosuit
	bio = 100
	fire = 50
	acid = 65

/obj/item/clothing/under/quarian
	name = "quarian suit"
	desc = "The standard quarian enviro-suit, sealed against the bacteria and viruses of the outside world."
	icon = 'modular_rimstation/icons/obj/clothing/quarian_under.dmi'
	worn_icon = 'modular_rimstation/icons/mob/clothing/quarian_under.dmi'
	icon_state = "suit"
	// No quarian in-hand art exists, so naming a state here only picks the generic fallback. Subtypes
	// inherit the null rather than naming their own colour.
	inhand_icon_state = null
	can_adjust = FALSE
	female_sprite_flags = FEMALE_UNIFORM_NO_BREASTS
	// The sprite is drawn with backward-bent legs already, so it needs no separate digitigrade icon.
	supports_variations_flags = CLOTHING_DIGITIGRADE_VARIATION_NO_NEW_ICON
	clothing_flags = STOPSPRESSUREDAMAGE
	armor_type = /datum/armor/clothing_under/quarian_envirosuit

/obj/item/clothing/under/quarian/white
	name = "white quarian suit"
	icon_state = "suit-white"

/obj/item/clothing/under/quarian/black
	name = "black quarian suit"
	icon_state = "suit-black"

/obj/item/clothing/under/quarian/red
	name = "red quarian suit"
	icon_state = "suit-red"

/obj/item/clothing/under/quarian/orange
	name = "orange quarian suit"
	icon_state = "suit-orange"

/obj/item/clothing/under/quarian/yellow
	name = "yellow quarian suit"
	icon_state = "suit-yellow"

/obj/item/clothing/under/quarian/green
	name = "green quarian suit"
	icon_state = "suit-green"

/obj/item/clothing/under/quarian/blue
	name = "blue quarian suit"
	icon_state = "suit-blue"

/obj/item/clothing/under/quarian/violet
	name = "violet quarian suit"
	icon_state = "suit-violet"


/obj/item/clothing/shoes/quarian
	name = "quarian boots"
	desc = "The standard quarian boots, sealed against the bacteria and viruses of the outside world."
	icon = 'modular_rimstation/icons/obj/clothing/quarian_shoes.dmi'
	worn_icon = 'modular_rimstation/icons/mob/clothing/quarian_shoes.dmi'
	icon_state = "shoes"
	inhand_icon_state = null
	supports_variations_flags = CLOTHING_DIGITIGRADE_VARIATION_NO_NEW_ICON
	clothing_flags = STOPSPRESSUREDAMAGE
	armor_type = /datum/armor/quarian_envirosuit


/**
 * Quarian gloves take a pair of ordinary gloves as a module.
 *
 * Rather than hold a table of which glove grants what, the installed pair is read for its traits and
 * insulation. Anything upstream adds to a glove therefore works here without this file being touched.
 */
/obj/item/clothing/gloves/quarian
	name = "quarian gloves"
	desc = "The standard quarian gloves, sealed against the bacteria and viruses of the outside world. \
		A slot in the back takes a pair of ordinary gloves as a module."
	icon = 'modular_rimstation/icons/obj/clothing/quarian_gloves.dmi'
	worn_icon = 'modular_rimstation/icons/mob/clothing/quarian_gloves.dmi'
	icon_state = "gloves"
	inhand_icon_state = null
	base_icon_state = "gloves"
	clothing_flags = STOPSPRESSUREDAMAGE
	armor_type = /datum/armor/quarian_envirosuit
	/// The gloves currently fitted as a module, held inside us until they are unscrewed.
	var/obj/item/clothing/gloves/module

/obj/item/clothing/gloves/quarian/Initialize(mapload)
	. = ..()
	AddElement(/datum/element/update_icon_updates_onmob)

/obj/item/clothing/gloves/quarian/Destroy()
	QDEL_NULL(module)
	return ..()

/obj/item/clothing/gloves/quarian/examine(mob/user)
	. = ..()
	if(module)
		. += span_notice("[module] is fitted into the back. A screwdriver would pry them out.")
	else
		. += span_notice("The module slot in the back is empty.")

/obj/item/clothing/gloves/quarian/item_interaction(mob/living/user, obj/item/tool, list/modifiers)
	if(!istype(tool, /obj/item/clothing/gloves) || istype(tool, /obj/item/clothing/gloves/quarian))
		return NONE
	if(module)
		balloon_alert(user, "slot already full!")
		return ITEM_INTERACT_BLOCKING
	if(!user.transferItemToLoc(tool, src))
		return ITEM_INTERACT_BLOCKING

	module = tool
	apply_module()
	balloon_alert(user, "module fitted")
	return ITEM_INTERACT_SUCCESS

/obj/item/clothing/gloves/quarian/screwdriver_act(mob/living/user, obj/item/tool)
	if(!module)
		return NONE

	var/obj/item/clothing/gloves/removed = module
	module = null
	clear_module(removed)
	user.put_in_hands(removed)
	tool.play_tool_sound(src)
	balloon_alert(user, "module removed")
	return ITEM_INTERACT_SUCCESS

/// Takes on the fitted gloves' traits, insulation and colour.
/obj/item/clothing/gloves/quarian/proc/apply_module()
	siemens_coefficient = module.siemens_coefficient
	// These setters, not a plain assignment: they also reach a wearer who already has us on.
	if(length(module.clothing_traits))
		attach_clothing_traits(module.clothing_traits)
	if(icon_exists(icon, module.icon_state))
		icon_state = module.icon_state
	update_appearance()

/// Puts us back to a bare pair of quarian gloves.
/obj/item/clothing/gloves/quarian/proc/clear_module(obj/item/clothing/gloves/removed)
	siemens_coefficient = initial(siemens_coefficient)
	if(length(removed.clothing_traits))
		detach_clothing_traits(removed.clothing_traits)
	icon_state = base_icon_state
	update_appearance()
