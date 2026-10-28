/// Only objects are obstacles. The parent loops over turf contents `as anything`, so mobs reached it and got hit:
/// allies in the way, and the attacker itself when its prey shared its tile.
/datum/bt_node/ai_behavior/attack_obstructions/can_smash_object(mob/living/basic/basic_mob, obj/object)
	if(!isobj(object))
		return FALSE
	return ..()
