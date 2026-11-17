/// What stops this mob eating or drinking, or null. Feeding checks use this instead of is_mouth_covered(),
/// which also gates disease, pepper spray and facehuggers, so a feeding port must not clear the cover flag.
/mob/living/proc/get_feeding_obstruction(check_flags = ALL)
	if(!HAS_TRAIT(src, TRAIT_FEEDING_PORT))
		return is_mouth_covered(check_flags)
	// The port runs past the headgear into a breathing mask's valve. A muzzle or a gag has no valve.
	var/obj/item/clothing/mask = is_mouth_covered(check_flags & ITEM_SLOT_MASK)
	if(istype(mask) && (mask.clothing_flags & MASKINTERNALS))
		return null
	return mask
