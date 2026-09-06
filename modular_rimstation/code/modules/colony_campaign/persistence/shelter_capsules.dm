/**
 * Shelter capsules do not deploy during a campaign.
 *
 * A capsule loads a shelter template, and a template brings an area with it. The map reader gives every tile
 * naming one area type the same instance, so a colony that popped four shelters had one "Emergency Shelter"
 * spanning all four of them - one APC's worth of power for four rooms, and one atmosphere.
 *
 * Areas made by a player are put back properly by area_identity.dm. A template's area is not: it is a mapped
 * area that the shelter system deploys more than one copy of, which is a different problem in the same place
 * and is not fixed here. Until it is, the capsule refuses rather than quietly costing the colony a room.
 *
 * The refusal is at attack_self() rather than in interact(), so an ordinary station round is untouched.
 */
/obj/item/survivalcapsule/attack_self(mob/user, modifiers)
	if(!SScampaign.is_campaign_active())
		return ..()

	balloon_alert(user, "won't arm")
	to_chat(user, span_warning("[src] refuses to arm. Nothing this far out will hold a bluespace anchor steady \
		enough to unpack it."))
	return TRUE
