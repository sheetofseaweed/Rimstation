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

/datum/component/colonist_binding/Destroy(force)
	// Written down on the way out, because commit can only read bodies that are still standing. A colonist who
	// logged off or was gibbed would otherwise donate a chapter of learning to nobody.
	var/mob/living/body = parent
	if(istype(body))
		SScampaign.capture_skills_for(colonist_id, body.mind)
		UnregisterSignal(body, list(COMSIG_LIVING_DEATH, COMSIG_MOB_EQUIPPED_ITEM))

	SScampaign.forget_colonist_body(colonist_id, body_ref)
	body_ref = null
	return ..()

/datum/component/colonist_binding/proc/on_colonist_death(mob/living/source, gibbed)
	SIGNAL_HANDLER
	SScampaign.note_colonist_death(colonist_id)

/datum/component/colonist_binding/proc/on_colonist_equipped_item(mob/living/source, obj/item/equipped, slot)
	SIGNAL_HANDLER
	relink_ids_carried_in(equipped, source)
