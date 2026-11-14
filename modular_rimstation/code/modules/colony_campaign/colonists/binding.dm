/**
 * Marks a body as the one playing a particular colonist this chapter.
 *
 * A component rather than a var on the mob, for two reasons. It cleans itself up when the body is deleted,
 * which matters because a colonist's body can be gibbed, dusted or otherwise removed mid-chapter and the
 * campaign must not be left holding a reference to it. And it keeps the hook out of inherited types entirely -
 * nothing upstream has to know that colonists exist.
 *
 * The binding is deliberately one-directional in importance: losing it costs the colony knowledge of which
 * body was whose, never the colonist record itself. People outlive their bodies here.
 */
/datum/component/colonist_binding
	dupe_mode = COMPONENT_DUPE_UNIQUE
	/// Which colonist this body is playing.
	var/colonist_id
	/// Weakref to our own parent, kept so the registry can tell our body from a later replacement.
	var/datum/weakref/body_ref
	/// The expedition map button this body carries.
	var/datum/action/colony_expedition_map/map_action
	/// TRUE while the body stands where a caravan can leave from.
	var/at_caravan_exit = FALSE

/datum/component/colonist_binding/Initialize(colonist_id)
	. = ..()
	if(!isliving(parent))
		return COMPONENT_INCOMPATIBLE
	if(!istext(colonist_id) || !length(colonist_id))
		return COMPONENT_INCOMPATIBLE

	src.colonist_id = colonist_id
	body_ref = WEAKREF(parent)
	// Death is recorded as it happens rather than counted at the end of the chapter: a body that is gone by
	// commit time cannot be asked whether it died, and those are exactly the deaths worth remembering.
	RegisterSignal(parent, COMSIG_LIVING_DEATH, PROC_REF(on_colonist_death))
	// Cards off a checkpoint carry a dead account reference. Watched here rather than on the card, because a
	// colonist is one registration and every ID card in the colony is hundreds.
	RegisterSignal(parent, COMSIG_MOB_EQUIPPED_ITEM, PROC_REF(on_colonist_equipped_item))
	// Binding can land either side of the job dressing the body, so what is already carried is swept once. The
	// signal above covers everything picked up afterwards.
	relink_all_carried_ids(parent)

	map_action = new(parent)
	map_action.Grant(parent)
	RegisterSignal(parent, COMSIG_MOVABLE_MOVED, PROC_REF(on_colonist_moved))

/datum/component/colonist_binding/Destroy(force)
	// Written down on the way out, because commit can only read bodies that are still standing. A colonist who
	// logged off or was gibbed would otherwise donate a chapter of learning to nobody.
	var/mob/living/body = parent
	if(istype(body))
		SScampaign.capture_skills_for(colonist_id, body.mind)
		UnregisterSignal(body, list(COMSIG_LIVING_DEATH, COMSIG_MOB_EQUIPPED_ITEM, COMSIG_MOVABLE_MOVED))
		body.clear_alert(ALERT_CARAVAN_EXIT)

	QDEL_NULL(map_action)
	SScampaign.forget_colonist_body(colonist_id, body_ref)
	body_ref = null
	return ..()

/datum/component/colonist_binding/proc/on_colonist_death(mob/living/source, gibbed)
	SIGNAL_HANDLER
	SScampaign.note_colonist_death(colonist_id)

/// Shows the way out while a colonist who is at home stands where a caravan can leave from.
/datum/component/colonist_binding/proc/on_colonist_moved(mob/living/source, atom/old_loc)
	SIGNAL_HANDLER
	var/at_exit = is_caravan_exit_turf(get_turf(source)) && !is_travelling_member(colonist_id)
	if(at_exit == at_caravan_exit)
		return
	at_caravan_exit = at_exit
	if(at_exit)
		source.throw_alert(ALERT_CARAVAN_EXIT, /atom/movable/screen/alert/caravan_exit)
	else
		source.clear_alert(ALERT_CARAVAN_EXIT)

/datum/component/colonist_binding/proc/on_colonist_equipped_item(mob/living/source, obj/item/equipped, slot)
	SIGNAL_HANDLER
	relink_ids_carried_in(equipped, source)
