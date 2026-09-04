/**
 * The shape every colony incident has, whatever it is about.
 *
 * A raid, a trader, a storm and a dispute have almost nothing in common as content and everything in common as
 * structure: each is announced before it lands, runs for a while, is decided, and leaves a record. Writing that
 * once means the storyteller and the pacing state deal with one contract rather than five.
 *
 * The incident is deliberately not a `/datum/round_event`. The event system owns *when* something happens and
 * is rebuilt every round; an incident owns *what* happens and is chosen by the campaign from what the colony
 * has been through. `/datum/round_event/colony_incident` is the join between them, so an incident stays
 * testable without scheduling one.
 *
 * Two rules the state machine exists to enforce:
 *
 * - **The warning cannot be skipped.** It is the colony's chance to prepare, and an incident that lands
 *   without one is a punishment rather than a story.
 * - **Resolution happens once.** Something that resolves twice would pay its rewards twice, so the first
 *   resolution wins and later ones are refused.
 */
/datum/colony_incident
	/// Set on types that exist to be inherited from. An abstract incident is never selected to run.
	var/abstract_incident = FALSE
	/// Stable identifier for this occurrence. Written into the ledger and the campaign's history.
	var/id
	/// Player-facing name.
	var/name = "colony incident"
	/// Which COLONY_INCIDENT_CATEGORY_* this belongs to. The storyteller buys by category.
	var/category = COLONY_INCIDENT_CATEGORY_NEUTRAL
	/// Shared tags, used to stop several incidents of the same flavour landing in a row.
	var/list/tags
	/// How long the colony gets between being told and the incident starting.
	var/warning_duration = 1 MINUTES
	/// How long the incident runs once it has begun, before its carrier gives up waiting and calls it ignored.
	var/active_duration = 1 MINUTES
	/// Current lifecycle state. Only ever changed through set_state().
	var/state = COLONY_INCIDENT_QUEUED
	/// Campaign clock at the moment it started and finished.
	var/started_at_clock = 0
	var/ended_at_clock = 0
	/// Anything held back that must be returned if the incident is cancelled.
	var/list/reservations
	/// What it ended up doing. Null until it resolves.
	var/datum/colony_incident_result/result
	/// Whatever the incident acts on, held weakly so it cannot keep a deleted thing alive.
	var/datum/weakref/target_ref
	/// Why it was cancelled, when it was.
	var/cancellation_reason
	/// Where this incident's question may be answered. Incidents that ask nothing ignore it.
	var/answer_sources = INCIDENT_ANSWER_CONSOLE | INCIDENT_ANSWER_COLONY_CORE
	/// The question currently before the colony, if any.
	var/datum/colony_decision/decision

/// Every incident type's tags, keyed by typepath text. Filled in on the first read.
GLOBAL_LIST_EMPTY(colony_incident_tags)

/**
 * Builds the tag index.
 *
 * Each type is instantiated once, because `initial()` returns nothing for a list variable - a list is
 * constructed at runtime, so there is no compile-time value to read. Reading tags off the type path directly
 * silently yields null, which is exactly the sort of nothing that makes a penalty quietly never apply.
 *
 * Built on first read rather than at global variable init, which is the one time a datum must not be
 * destroyed: the garbage collector stamps its queue entry with a `world.time` of almost zero, and that entry
 * then sits at the head of the queue for the whole round, holding back every drain check made after it.
 */
/proc/build_colony_incident_tag_index()
	RETURN_TYPE(/list)
	var/list/index = list()
	for(var/datum/colony_incident/incident_type as anything in subtypesof(/datum/colony_incident))
		var/datum/colony_incident/probe = new incident_type
		index["[incident_type]"] = probe.tags?.Copy() || list()
		qdel(probe)
	return index

/// The tags a given incident type carries.
/proc/get_colony_incident_tags(incident_type)
	RETURN_TYPE(/list)
	if(!length(GLOB.colony_incident_tags))
		GLOB.colony_incident_tags = build_colony_incident_tag_index()
	return GLOB.colony_incident_tags["[incident_type]"] || list()

/datum/colony_incident/New()
	. = ..()
	id = "incident-[world.time]-[rand(1000, 9999)]"
	tags = tags?.Copy() || list()
	reservations = list("credits" = 0, "resources" = list())

/datum/colony_incident/Destroy(force)
	// Nothing may outlive the incident holding a callback into it. Concrete incidents that register signals
	// unregister them here through the parent call.
	// Resolving and cancelling both drop the incident from the campaign already. This covers the third way out:
	// being destroyed outright, which neither of them sees.
	SScampaign?.forget_incident(src)
	target_ref = null
	result = null
	reservations = null
	QDEL_NULL(decision)
	return ..()

/**
 * Moves to `new_state` if that is a legal step. Returns TRUE when it happened.
 *
 * Legal means the next step forward, or a jump to cancelled from anywhere that has not finished. Skipping
 * ahead is refused rather than runtimed, because two systems racing to advance an incident should end with the
 * first one winning, not with a stack trace.
 */
/datum/colony_incident/proc/set_state(new_state)
	if(new_state == state)
		return FALSE

	if(new_state == COLONY_INCIDENT_CANCELLED)
		if(state == COLONY_INCIDENT_RESOLVED || state == COLONY_INCIDENT_CANCELLED)
			return FALSE
		state = new_state
		return TRUE

	var/list/order = COLONY_INCIDENT_STATE_ORDER
	var/current_position = order.Find(state)
	var/new_position = order.Find(new_state)
	if(!current_position || !new_position || new_position != current_position + 1)
		return FALSE

	state = new_state
	return TRUE

/// TRUE once the incident has stopped, either way.
/datum/colony_incident/proc/is_finished()
	return state == COLONY_INCIDENT_RESOLVED || state == COLONY_INCIDENT_CANCELLED

/**
 * TRUE when this incident could run right now.
 *
 * Overridden by concrete incidents to state their own requirements - a trader needs somewhere to land, a
 * dispute needs two colonists to argue. The base rule is that the world has to be still enough to change.
 */
/datum/colony_incident/proc/can_begin()
	if(!SScampaign.is_campaign_active())
		return FALSE
	return SScampaign.can_mutate_world()

/// Announces the incident and starts the preparation window.
/datum/colony_incident/proc/begin_warning()
	if(!can_begin() || !set_state(COLONY_INCIDENT_WARNING))
		return FALSE

	select_target()
	announce_warning()
	return TRUE

/// The incident actually arrives.
/datum/colony_incident/proc/begin_active()
	if(!set_state(COLONY_INCIDENT_ACTIVE))
		return FALSE

	started_at_clock = SScampaign.get_campaign_time()
	execute()
	return TRUE

/// The incident stops acting and its outcome is worked out.
/datum/colony_incident/proc/begin_resolving()
	return set_state(COLONY_INCIDENT_RESOLVING)

/**
 * Records what the incident did. Returns TRUE only if this call is the one that decided it.
 *
 * Idempotent by refusal rather than by overwriting: a second resolution is a bug somewhere upstream, and
 * paying its rewards again would be a worse outcome than ignoring it.
 */
/datum/colony_incident/proc/resolve(outcome, pressure_change = 0)
	if(state == COLONY_INCIDENT_RESOLVED || state == COLONY_INCIDENT_CANCELLED)
		return FALSE
	if(!(outcome in list(COLONY_INCIDENT_OUTCOME_SUCCEEDED, COLONY_INCIDENT_OUTCOME_FAILED, COLONY_INCIDENT_OUTCOME_IGNORED)))
		return FALSE

	// Anything that skipped straight here still has to pass through resolving, so the states stay ordered.
	if(state != COLONY_INCIDENT_RESOLVING)
		if(state == COLONY_INCIDENT_QUEUED && !set_state(COLONY_INCIDENT_WARNING))
			return FALSE
		if(state == COLONY_INCIDENT_WARNING && !set_state(COLONY_INCIDENT_ACTIVE))
			return FALSE
		if(!set_state(COLONY_INCIDENT_RESOLVING))
			return FALSE

	if(!set_state(COLONY_INCIDENT_RESOLVED))
		return FALSE

	ended_at_clock = SScampaign.get_campaign_time()
	result = new(id)
	result.incident_type = "[type]"
	result.tags = tags?.Copy() || list()
	result.outcome = outcome
	result.pressure_change = pressure_change
	result.resolved_at_clock = ended_at_clock

	// Reservations belong to a running incident. Once it is over, anything still held is returned rather than
	// quietly kept, so a resolved incident cannot leave the colony poorer than its result says.
	release_reservations("[id] resolved")

	build_result(result)
	SScampaign.record_incident_result(result)
	SScampaign.forget_incident(src)
	log_game("Colony incident [id] ([category]) resolved as [outcome].")
	return TRUE

/**
 * Stops the incident before it finished, returning anything it was holding.
 *
 * Cancellation is not a failure and does not produce a result: nothing happened, so there is nothing for the
 * pacing state to learn from.
 */
/datum/colony_incident/proc/cancel(reason)
	if(!set_state(COLONY_INCIDENT_CANCELLED))
		return FALSE

	cancellation_reason = reason
	release_reservations("[id] cancelled: [reason || "no reason given"]")
	SScampaign.forget_incident(src)
	log_game("Colony incident [id] ([category]) cancelled: [reason || "no reason given"].")
	return TRUE

/**
 * Holds credits against this incident, taking them out of the settlement's account.
 *
 * Reserved rather than spent, so that an incident interrupted halfway does not cost the colony money for
 * something it never received. Every movement is a ledger entry either way.
 */
/datum/colony_incident/proc/reserve_credits(amount, reason_code)
	if(!isnum(amount) || amount <= 0)
		return FALSE
	if(!SScampaign.try_debit(amount, LEDGER_CATEGORY_INCIDENT, reason_code || "[id] reserved funds", null, id))
		return FALSE

	reservations["credits"] += amount
	return TRUE

/// Holds a resource quantity against this incident, on the same terms as credits.
/datum/colony_incident/proc/reserve_resource(resource_id, amount, reason_code)
	if(!resource_id || !isnum(amount) || amount <= 0)
		return FALSE
	if(!SScampaign.adjust_resource(resource_id, -amount, LEDGER_CATEGORY_INCIDENT, reason_code || "[id] reserved materials", null, id))
		return FALSE

	var/list/held = reservations["resources"]
	held[resource_id] = (held[resource_id] || 0) + amount
	return TRUE

/// Gives back everything still held. Safe to call more than once; the second call has nothing to return.
/datum/colony_incident/proc/release_reservations(reason_code)
	if(!islist(reservations))
		return FALSE

	if(reservations["credits"] > 0)
		SScampaign.credit(reservations["credits"], LEDGER_CATEGORY_INCIDENT, reason_code, null, id)
		reservations["credits"] = 0

	var/list/held = reservations["resources"]
	for(var/resource_id in held)
		if(held[resource_id] > 0)
			SScampaign.adjust_resource(resource_id, held[resource_id], LEDGER_CATEGORY_INCIDENT, reason_code, null, id)
	reservations["resources"] = list()
	return TRUE

/**
 * Puts a question to the colony, wherever this incident allows it to be answered.
 *
 * Returns TRUE if it reached somebody. A question nobody can be asked is worth knowing about immediately, so
 * the incident can decide what happens in the absence of an answer rather than waiting out a timer.
 */
/datum/colony_incident/proc/ask_colony(title, content, list/answers, callback_proc)
	QDEL_NULL(decision)
	decision = new(title, content, answers, answer_sources)
	decision.on_answered = CALLBACK(src, callback_proc)
	if(decision.ask())
		return TRUE

	QDEL_NULL(decision)
	return FALSE

/// Chooses whatever this incident acts on. Concrete incidents override; the base acts on nothing in particular.
/datum/colony_incident/proc/select_target()
	return TRUE

/// Tells the colony it is coming. Overridden to say something specific.
/datum/colony_incident/proc/announce_warning()
	priority_announce("[name] is expected within [DisplayTimeText(warning_duration)].", "Colony Advisory")
	return TRUE

/// Does whatever the incident does. The base incident is a contract, so it does nothing.
/datum/colony_incident/proc/execute()
	return TRUE

/// Fills in the consequences, rewards and telemetry the result carries. Overridden by concrete incidents.
/datum/colony_incident/proc/build_result(datum/colony_incident_result/building)
	return TRUE
