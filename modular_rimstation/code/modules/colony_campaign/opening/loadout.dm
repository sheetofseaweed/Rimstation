/**
 * What a colony is given to start with.
 *
 * The opening has to be survivable for two players and still not hand twenty players an industrial base, so
 * quantities are `base + ceil(colonists / per_colonist)` clamped to a cap. Shared supplies are granted once
 * for the settlement; personal supplies are granted per colonist.
 *
 * The contents are deliberately pre-industrial. Anything that removes the early production chain - a lathe,
 * an RCD, energy weapons - belongs to progression, not to the first ten minutes.
 */
/datum/colony_opening_package
	/// Assoc of item type to a scaling rule granted once for the whole colony.
	var/list/shared_supplies
	/// Assoc of item type to a flat quantity granted to each colonist.
	var/list/personal_supplies

/datum/colony_opening_package/New()
	. = ..()
	shared_supplies = list(
		// Fire: light, warmth and cooking, and the thing a new colony builds first.
		/obj/item/stack/sheet/mineral/wood = list("base" = 20, "per_colonist" = 2, "cap" = 60),
		/obj/item/match = list("base" = 6, "per_colonist" = 2, "cap" = 20),
		// Shelter and bedding.
		/obj/item/stack/sheet/cloth = list("base" = 10, "per_colonist" = 1, "cap" = 30),
		// The first renewable food, rather than a food stockpile.
		/obj/item/seeds/potato = list("base" = 2, "per_colonist" = 4, "cap" = 8),
		/obj/item/seeds/wheat = list("base" = 2, "per_colonist" = 4, "cap" = 8),
		// Digging soil and breaking rock are the two bottlenecks worth relieving up front.
		/obj/item/shovel = list("base" = 1, "per_colonist" = 3, "cap" = 5),
		/obj/item/pickaxe = list("base" = 1, "per_colonist" = 3, "cap" = 5),
	)
	personal_supplies = list(
		/obj/item/knife/combat/survival = 1,
		/obj/item/reagent_containers/cup/glass/waterbottle = 1,
	)

/**
 * Quantity of one shared supply for a given headcount.
 *
 * Rounds up so the first colonist past a threshold still gets the benefit, and never exceeds the cap.
 */
/datum/colony_opening_package/proc/get_shared_quantity(item_type, colonist_count)
	var/list/rule = shared_supplies[item_type]
	if(!islist(rule))
		return 0
	var/scaled = rule["base"]
	var/per_colonist = rule["per_colonist"]
	if(per_colonist > 0)
		scaled += CEILING(max(0, colonist_count) / per_colonist, 1)
	return min(scaled, rule["cap"])

/**
 * Everything the colony receives at this headcount, as an assoc of type to total quantity.
 *
 * Personal supplies are multiplied out here rather than handed out per mob so that the package can be
 * inspected and tested as one manifest.
 */
/datum/colony_opening_package/proc/get_manifest(colonist_count)
	RETURN_TYPE(/list)
	var/list/manifest = list()
	for(var/item_type in shared_supplies)
		manifest[item_type] = get_shared_quantity(item_type, colonist_count)
	for(var/item_type in personal_supplies)
		manifest[item_type] += personal_supplies[item_type] * max(0, colonist_count)
	return manifest
