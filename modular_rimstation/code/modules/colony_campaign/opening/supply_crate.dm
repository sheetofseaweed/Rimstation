/**
 * The crate the colony wakes up next to.
 *
 * Fills itself from /datum/colony_opening_package at roundstart, scaled to how many people actually turned
 * up. It exists as a mapped-in object rather than a spawn hook so a mapper can see and move the colony's
 * starting supplies, and so the opening is visible on the map instead of appearing by magic.
 */
/obj/structure/closet/crate/colony_supplies
	name = "colony supply crate"
	desc = "Everything the expedition could spare. It is not very much."

/obj/structure/closet/crate/colony_supplies/Initialize(mapload)
	. = ..()
	return INITIALIZE_HINT_LATELOAD

/obj/structure/closet/crate/colony_supplies/LateInitialize()
	. = ..()
	fill_from_package()

/// Populates the crate from the opening package at the current colonist count.
/obj/structure/closet/crate/colony_supplies/proc/fill_from_package()
	var/datum/colony_opening_package/package = new
	// Readied players is the honest count at roundstart; GLOB.clients would include observers and admins.
	var/colonist_count = max(1, length(GLOB.joined_player_list))
	var/list/manifest = package.get_manifest(colonist_count)
	for(var/item_type in manifest)
		var/amount = manifest[item_type]
		if(amount <= 0)
			continue
		if(ispath(item_type, /obj/item/stack))
			// Stacks carry their own count rather than spawning one object per unit.
			var/obj/item/stack/spawned = new item_type(src)
			spawned.amount = min(amount, spawned.max_amount)
			continue
		for(var/i in 1 to amount)
			new item_type(src)
	qdel(package)
