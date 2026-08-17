/**
 * A question put to the colony, and the answer it gives back.
 *
 * The communications console already has everything this needs - `/datum/comm_message` carries a title, body
 * and a list of answers, and calls back when someone picks one. What it does not have is a second place to
 * answer from, and a colony that has not built a console yet still has to be able to say yes to a refugee.
 *
 * So a decision can be delivered to more than one place at once, and the first answer from any of them wins.
 * Which places are acceptable is the incident's business: a trader hailing the settlement belongs on a radio,
 * and answering that by touching the colony core would be silly.
 */
GLOBAL_LIST_EMPTY(rimstation_open_decisions)

/datum/colony_decision
	/// Short heading, used as the message title and the interaction prompt.
	var/title
	/// The question itself.
	var/content
	/// The answers on offer, in order. The index of the chosen one is what gets reported back.
	var/list/answers
	/// Which of them was chosen. Zero until someone decides.
	var/answered_index = 0
	/// Fired once, with the chosen index. Never fired for an expired decision.
	var/datum/callback/on_answered
	/// Bitfield of INCIDENT_ANSWER_* places this may be answered from.
	var/answer_sources = INCIDENT_ANSWER_CONSOLE
	/// Timer that closes the decision if nobody answers.
	var/expiry_timer_id

/datum/colony_decision/New(title, content, list/answers, answer_sources = INCIDENT_ANSWER_CONSOLE)
	. = ..()
	src.title = title
	src.content = content
	src.answers = answers?.Copy() || list()
	src.answer_sources = answer_sources

/datum/colony_decision/Destroy(force)
	close()
	on_answered = null
	return ..()

/// TRUE when this decision can still be answered.
/datum/colony_decision/proc/is_open()
	return !answered_index && (src in GLOB.rimstation_open_decisions)

/// TRUE when `source` is a place this decision accepts answers from.
/datum/colony_decision/proc/accepts_source(source)
	return (answer_sources & source)

/**
 * Puts the question to the colony everywhere it is allowed to be asked.
 *
 * Returns TRUE if it reached at least one place. A decision nobody can possibly answer is not opened, so the
 * incident can fall back rather than waiting out a timer for an audience that does not exist.
 */
/datum/colony_decision/proc/ask()
	if(!length(answers))
		return FALSE

	var/reached = FALSE
	GLOB.rimstation_open_decisions += src

	if(accepts_source(INCIDENT_ANSWER_CONSOLE) && length(GLOB.shuttle_caller_list))
		var/datum/comm_message/message = new(title, content, answers.Copy())
		message.answer_callback = CALLBACK(src, PROC_REF(on_console_answer), message)
		GLOB.communications_controller.send_message(message, print = FALSE, unique = TRUE)
		reached = TRUE

	// The core is a physical fallback: it always exists while the colony does, so a settlement with no console
	// can still be asked things it ought to be able to answer.
	if(accepts_source(INCIDENT_ANSWER_COLONY_CORE) && (locate(/obj/structure/colony_core) in world))
		reached = TRUE

	if(!reached)
		GLOB.rimstation_open_decisions -= src
		return FALSE

	expiry_timer_id = addtimer(CALLBACK(src, PROC_REF(expire)), COLONY_DECISION_TIMEOUT, TIMER_STOPPABLE)
	return TRUE

/// Reads the console's answer back out of the message it was given.
/datum/colony_decision/proc/on_console_answer(datum/comm_message/message)
	if(!message?.answered)
		return
	answer(message.answered, INCIDENT_ANSWER_CONSOLE)

/**
 * Records an answer. Returns TRUE only if this call is the one that decided it.
 *
 * First answer wins, from wherever it came. Two people answering the same question from two places is a race
 * the colony should survive, not a double payout.
 */
/datum/colony_decision/proc/answer(index, source)
	if(!is_open())
		return FALSE
	if(!accepts_source(source))
		return FALSE
	if(!isnum(index) || index < 1 || index > length(answers))
		return FALSE

	answered_index = index
	close()
	on_answered?.Invoke(index)
	return TRUE

/// Nobody answered in time. The incident hears nothing and resolves however it resolves without a decision.
/datum/colony_decision/proc/expire()
	if(!is_open())
		return FALSE
	close()
	return TRUE

/// Stops the decision being answerable, without deciding it.
/datum/colony_decision/proc/close()
	GLOB.rimstation_open_decisions -= src
	if(expiry_timer_id)
		deltimer(expiry_timer_id)
		expiry_timer_id = null
	return TRUE

/// Every decision currently answerable from `source`.
/proc/get_open_colony_decisions(source)
	RETURN_TYPE(/list)
	var/list/open = list()
	for(var/datum/colony_decision/decision as anything in GLOB.rimstation_open_decisions)
		if(decision.is_open() && decision.accepts_source(source))
			open += decision
	return open


/**
 * The colony core doubles as the settlement's noticeboard.
 *
 * Not because it is elegant, but because it is the one thing a colony always has: it is what the campaign is
 * about, it is placed before anything is built, and it cannot be lost without ending the chapter anyway.
 */
/obj/structure/colony_core/ui_interact(mob/user, datum/tgui/ui)
	var/list/open = get_open_colony_decisions(INCIDENT_ANSWER_COLONY_CORE)
	if(!length(open))
		return ..()

	var/datum/colony_decision/decision = open[1]
	var/list/options = decision.answers.Copy()
	var/chosen = tgui_alert(user, decision.content, decision.title, options, timeout = 30 SECONDS)
	if(isnull(chosen))
		return

	var/index = options.Find(chosen)
	if(!index)
		return
	if(decision.answer(index, INCIDENT_ANSWER_COLONY_CORE))
		to_chat(user, span_notice("You record the settlement's decision."))
