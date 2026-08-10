/**
 * One kind of attacker a raid can buy.
 *
 * Cost is the only currency. Keeping composition on a budget is what lets the colony be told how much threat
 * is coming and lets that promise mean something.
 */
/datum/colony_raid_unit
	/// What actually spawns.
	var/mob_type
	/// Budget cost of one of these.
	var/point_cost = 10
	/// Bought before anything else, so a raid never arrives without its core shape.
	var/minimum_count = 0
	/// Ceiling regardless of remaining budget, so one cheap unit cannot become the whole raid.
	var/maximum_count = 5
	/// Flavour role, used by routing and telemetry.
	var/role = "grunt"
	/// Relative likelihood during the weighted fill.
	var/weight = 1

/datum/colony_raid_unit/New(mob_type, point_cost, minimum_count, maximum_count, role, weight)
	. = ..()
	if(!isnull(mob_type))
		src.mob_type = mob_type
	if(!isnull(point_cost))
		src.point_cost = point_cost
	if(!isnull(minimum_count))
		src.minimum_count = minimum_count
	if(!isnull(maximum_count))
		src.maximum_count = maximum_count
	if(!isnull(role))
		src.role = role
	if(!isnull(weight))
		src.weight = weight
