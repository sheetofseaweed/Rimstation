/**
 * How the storyteller schedules colony incidents.
 *
 * The storyteller already decides when something should happen and what it should cost, and it does that
 * through `/datum/round_event_control`. Rather than give the campaign a second scheduler, there is one control
 * per incident category: the storyteller buys "something environmental" on its usual tracks and budget, and
 * the campaign decides which environmental incident that turns out to be.
 *
 * Splitting it there is what lets pacing and content move independently. The storyteller weighs categories
 * against the round; the campaign weighs incidents against what this colony has already been through.
 */
/datum/round_event_control/colony_incident
	name = "Colony Incident"
	typepath = /datum/round_event/colony_incident
	track = EVENT_TRACK_MODERATE
	category = EVENT_CATEGORY_COLONY
	description = "Something happens to the colony."
	/// Which COLONY_INCIDENT_CATEGORY_* this control schedules.
	var/incident_category

/**
 * Never eligible outside a campaign, and never eligible if the campaign has nothing to offer.
 *
 * The second half matters as much as the first: an incident control that can be bought while no concrete
 * incident of its category exists would spend the storyteller's points on nothing at all.
 */
/datum/round_event_control/colony_incident/can_spawn_storyteller_event(players_amt, elapsed = STATION_TIME_PASSED())
	if(!SScampaign.is_campaign_active())
		return FALSE
	if(!SScampaign.can_mutate_world())
		return FALSE
	if(!length(SScampaign.get_eligible_incident_types(incident_category)))
		return FALSE

	// A colony that has just been through the worst of it is not handed another disaster. Only the destructive
	// categories are held back, so there is always something the storyteller can still buy.
	var/datum/colony_story_state/story = SScampaign.get_story_state()
	if(story?.is_recovering_hard() && (TAG_DESTRUCTIVE in tags))
		return FALSE

	return ..()

/**
 * Refuses before anything is spent when no incident can be built.
 *
 * `preRunEvent()` is the last point at which saying no is free. Returning EVENT_CANT_RUN here means the
 * storyteller retires the control rather than running an event that would do nothing, and a scheduled purchase
 * can still be refunded to its track.
 */
/datum/round_event_control/colony_incident/preRunEvent()
	if(!SScampaign.is_campaign_active() || !length(SScampaign.get_eligible_incident_types(incident_category)))
		return EVENT_CANT_RUN
	return ..()


/**
 * The event that carries one incident.
 *
 * Thin on purpose. It owns timing - the event system's `activeFor` clock drives the warning window and the
 * duration - and delegates everything about what happens to the incident it is carrying.
 */
/datum/round_event/colony_incident
	/// The incident this event is running.
	var/datum/colony_incident/incident

/datum/round_event/colony_incident/setup()
	var/datum/round_event_control/colony_incident/incident_control = control
	incident = SScampaign.create_incident(incident_control?.incident_category)
	if(!incident)
		// Nothing to run. Killing the event here means it never announces something that will not arrive.
		kill()
		return

	// The event's clock is in seconds of lifetime, and the incident states how long a colony gets to prepare.
	announce_when = 1
	start_when = max(2, round(incident.warning_duration / (1 SECONDS)))
	end_when = start_when + 60

/datum/round_event/colony_incident/announce(fake)
	incident?.begin_warning()

/datum/round_event/colony_incident/start()
	if(!incident?.begin_active())
		kill()

/datum/round_event/colony_incident/end()
	if(!incident)
		return
	incident.begin_resolving()
	// An incident nobody engaged with was ignored rather than failed; concrete incidents that know better
	// resolve themselves before the event's clock runs out.
	incident.resolve(COLONY_INCIDENT_OUTCOME_IGNORED)

/datum/round_event/colony_incident/kill()
	// An event torn down before its incident finished must not leave the colony's money reserved against it.
	if(incident && !incident.is_finished())
		incident.cancel("the event carrying it was stopped")
	return ..()

/datum/round_event/colony_incident/Destroy()
	if(incident && !incident.is_finished())
		incident.cancel("the event carrying it was destroyed")
	QDEL_NULL(incident)
	return ..()


// One control per category. They carry no content themselves; the campaign chooses what each one becomes.
//
// The tags are the storyteller's own vocabulary, not the campaign's: they feed the per-storyteller
// `tag_multipliers` and the repetition penalty that already exist, so a teller that dislikes destructive events
// dislikes colony storms too, without knowing what a colony is. Repetition *within* a category is the
// campaign's job, and is weighted against incident history rather than event occurrences.

/datum/round_event_control/colony_incident/positive
	name = "Colony Incident: Fortune"
	incident_category = COLONY_INCIDENT_CATEGORY_POSITIVE
	description = "Something goes the colony's way."
	track = EVENT_TRACK_MUNDANE
	weight = 15
	tags = list(TAG_POSITIVE, TAG_COMMUNAL)

/datum/round_event_control/colony_incident/neutral
	name = "Colony Incident: Visitors"
	incident_category = COLONY_INCIDENT_CATEGORY_NEUTRAL
	description = "Someone arrives with an offer."
	track = EVENT_TRACK_MUNDANE
	weight = 15
	tags = list(TAG_NEUTRAL, TAG_COMMUNAL)

/datum/round_event_control/colony_incident/environmental
	name = "Colony Incident: Weather"
	incident_category = COLONY_INCIDENT_CATEGORY_ENVIRONMENTAL
	description = "The planet does something the colony has to answer for."
	track = EVENT_TRACK_MODERATE
	weight = 10
	tags = list(TAG_DESTRUCTIVE, TAG_COMMUNAL)

/datum/round_event_control/colony_incident/social
	name = "Colony Incident: Dispute"
	incident_category = COLONY_INCIDENT_CATEGORY_SOCIAL
	description = "The settlement disagrees with itself."
	track = EVENT_TRACK_MUNDANE
	weight = 10
	tags = list(TAG_NEUTRAL, TAG_TARGETED)

/datum/round_event_control/colony_incident/resource
	name = "Colony Incident: Prospects"
	incident_category = COLONY_INCIDENT_CATEGORY_RESOURCE
	description = "What the colony can dig or grow changes."
	track = EVENT_TRACK_MODERATE
	weight = 10
	tags = list(TAG_NEUTRAL, TAG_DESTRUCTIVE)
