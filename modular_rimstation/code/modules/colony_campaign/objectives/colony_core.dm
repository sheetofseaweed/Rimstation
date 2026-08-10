/**
 * The colony's legible objective.
 *
 * Everything about losing a chapter runs through this object, on purpose. A settlement that can be lost by
 * an ordinary round ending, or by everyone happening to be dead at once, produces stories nobody can argue
 * with. Capture instead costs attackers uninterrupted time standing on a thing the defenders can see.
 */
/obj/structure/colony_core
	name = "colony core"
	desc = "The heart of the settlement. Whoever holds this holds the colony."
	icon = 'icons/obj/fluff/general.dmi'
	icon_state = "signpost"
	anchored = TRUE
	density = TRUE
	max_integrity = 1000
	resistance_flags = FIRE_PROOF | UNACIDABLE | ACID_PROOF

	/// How long hostiles must hold the core, uninterrupted, before it falls.
	var/capture_duration = 3 MINUTES
	/// How far from the core a hostile counts as standing on it.
	var/capture_radius = 4
	/// One of COLONY_CORE_SECURE, COLONY_CORE_CONTESTED or COLONY_CORE_CAPTURED.
	var/state = COLONY_CORE_SECURE
	/// Uninterrupted hostile control accumulated so far, in deciseconds.
	var/capture_progress = 0
	/// The chapter result this core reports into. Set by whatever runs the chapter.
	var/datum/colony_chapter_outcome/chapter_outcome
	/// Repeating alert timer, live only while contested. Stoppable so Destroy() can cancel it.
	var/alert_timer_id

/obj/structure/colony_core/Initialize(mapload)
	. = ..()
	register_context()

/obj/structure/colony_core/Destroy()
	stop_progress_alerts()
	// Destroyed is not captured: an attacker who blows the core up has still taken the colony off the map,
	// but the distinction matters to whatever is recording why the chapter ended.
	if(state != COLONY_CORE_CAPTURED)
		SEND_SIGNAL(src, COMSIG_COLONY_CORE_DESTROYED, src)
		chapter_outcome?.resolve(COLONY_OUTCOME_FAILURE, "the colony core was destroyed")
	chapter_outcome = null
	return ..()

/obj/structure/colony_core/examine(mob/user)
	. = ..()
	switch(state)
		if(COLONY_CORE_SECURE)
			. += span_notice("It is secure.")
		if(COLONY_CORE_CONTESTED)
			var/percent = round((capture_progress / capture_duration) * 100)
			. += span_userdanger("It is being taken - [percent]% lost.")
		if(COLONY_CORE_CAPTURED)
			. += span_userdanger("It has fallen.")

/**
 * Advances the capture clock by an explicit amount of time.
 *
 * Time is passed in rather than read from the world so that the state machine can be tested without waiting
 * out a real capture, and so a lagging server cannot accidentally hand attackers extra progress.
 *
 * Returns the resulting state.
 */
/obj/structure/colony_core/proc/advance_contest(hostiles_present, elapsed)
	if(state == COLONY_CORE_CAPTURED)
		return state

	if(!hostiles_present)
		if(capture_progress > 0)
			capture_progress = 0
			state = COLONY_CORE_SECURE
			stop_progress_alerts()
			SEND_SIGNAL(src, COMSIG_COLONY_CORE_SECURED, src)
			announce_secured()
		return state

	if(state != COLONY_CORE_CONTESTED)
		state = COLONY_CORE_CONTESTED
		start_progress_alerts()
		SEND_SIGNAL(src, COMSIG_COLONY_CORE_CONTESTED, src)
		announce_contested()

	capture_progress += max(0, elapsed)
	if(capture_progress >= capture_duration)
		capture_progress = capture_duration
		state = COLONY_CORE_CAPTURED
		stop_progress_alerts()
		SEND_SIGNAL(src, COMSIG_COLONY_CORE_CAPTURED, src)
		chapter_outcome?.resolve(COLONY_OUTCOME_FAILURE, "the colony core was captured")
		announce_captured()

	return state

/// TRUE when something hostile to the colony is close enough to be taking the core.
/obj/structure/colony_core/proc/has_hostiles_present()
	for(var/mob/living/nearby in range(capture_radius, src))
		if(nearby.stat == DEAD)
			continue
		if(faction_check(nearby.faction, list(RIMSTATION_COLONY_FACTION)))
			continue
		return TRUE
	return FALSE

/obj/structure/colony_core/proc/start_progress_alerts()
	stop_progress_alerts()
	alert_timer_id = addtimer(CALLBACK(src, PROC_REF(announce_progress)), 30 SECONDS, TIMER_STOPPABLE | TIMER_LOOP)

/obj/structure/colony_core/proc/stop_progress_alerts()
	if(!alert_timer_id)
		return
	deltimer(alert_timer_id)
	alert_timer_id = null

/obj/structure/colony_core/proc/announce_contested()
	visible_message(span_userdanger("[src] is being taken!"))

/obj/structure/colony_core/proc/announce_secured()
	visible_message(span_notice("[src] is secure again."))

/obj/structure/colony_core/proc/announce_captured()
	visible_message(span_userdanger("[src] has fallen."))

/obj/structure/colony_core/proc/announce_progress()
	if(state != COLONY_CORE_CONTESTED)
		return
	var/percent = round((capture_progress / capture_duration) * 100)
	visible_message(span_userdanger("[src] is [percent]% taken!"))
