/**
 * The colony's research, carried from one chapter to the next.
 *
 * Progression uses the techweb the game already has rather than a second economy beside it. A colony that
 * spent a chapter researching something keeps it, which is the only part the inherited system does not do on
 * its own - a techweb is built fresh every round because an ordinary shift has no memory.
 *
 * Only what a colony earned is stored: which nodes it researched and what points it has left. Everything
 * derived from those - available nodes, unlocked designs, visible nodes - is rebuilt by replaying the nodes
 * into a fresh techweb, so this record cannot drift out of step with what the nodes actually say.
 */
/datum/colony_research_record
	var/schema_version = COLONY_RESEARCH_SCHEMA_VERSION
	/// Ids of every node the colony has researched.
	var/list/researched_node_ids
	/// Unspent points, keyed by point type.
	var/list/research_points
	/// Experiment types the colony has completed, so a chapter does not repeat the same fieldwork.
	var/list/completed_experiments

/datum/colony_research_record/New()
	. = ..()
	researched_node_ids = list()
	research_points = list()
	completed_experiments = list()

/// Reads the colony's research out of a live techweb.
/datum/colony_research_record/proc/capture_from(datum/techweb/web)
	if(!istype(web))
		return FALSE

	researched_node_ids = list()
	for(var/node_id in web.researched_nodes)
		researched_node_ids += node_id

	research_points = web.research_points?.Copy() || list()
	completed_experiments = web.completed_experiments?.Copy() || list()
	return TRUE

/**
 * Replays this record into a techweb. Returns how many nodes were restored.
 *
 * Nodes are researched with `force`, because the colony already paid for them - charging again would empty a
 * returning colony's account, and requiring prerequisites in stored order would drop anything replayed early.
 * Points are set afterwards for the same reason: restoring must not be a transaction.
 *
 * A node id that no longer exists is skipped rather than refused. An upstream techweb change should cost a
 * colony that node, not its whole campaign.
 */
/datum/colony_research_record/proc/restore_into(datum/techweb/web)
	if(!istype(web))
		return 0

	var/restored = 0
	for(var/node_id in researched_node_ids)
		var/datum/techweb_node/node = SSresearch.techweb_node_by_id(node_id)
		if(!node)
			log_game("Colony research skipped node '[node_id]', which this build no longer has.")
			continue
		if(web.researched_nodes[node_id])
			continue
		if(web.research_node(node, force = TRUE, auto_adjust_cost = FALSE, get_that_dosh = FALSE))
			restored++

	for(var/experiment_type in completed_experiments)
		web.completed_experiments[experiment_type] = completed_experiments[experiment_type]

	// Set rather than add: the techweb starts a round with a standard allowance, and a colony's balance is
	// what it actually had left, not that allowance plus its savings.
	web.research_points = research_points.Copy()
	return restored

/datum/colony_research_record/proc/serialize()
	RETURN_TYPE(/list)
	return list(
		"schema_version" = schema_version,
		"researched_node_ids" = researched_node_ids.Copy(),
		"research_points" = research_points.Copy(),
		"completed_experiments" = completed_experiments.Copy(),
	)

/datum/colony_research_record/proc/deserialize(list/data)
	if(!islist(data))
		return FALSE

	var/incoming_version = data["schema_version"]
	if(!isnum(incoming_version) || incoming_version != COLONY_RESEARCH_SCHEMA_VERSION)
		log_game("Colony research record rejected: unsupported schema version '[incoming_version]'.")
		return FALSE

	var/list/incoming_nodes = list()
	if(islist(data["researched_node_ids"]))
		for(var/node_id in data["researched_node_ids"])
			if(istext(node_id))
				incoming_nodes += node_id

	// Points come off disk, so a corrupted or edited record must not hand a colony a fortune or a debt.
	var/list/incoming_points = list()
	if(islist(data["research_points"]))
		for(var/point_type in data["research_points"])
			var/amount = data["research_points"][point_type]
			if(isnum(amount) && amount >= 0)
				incoming_points[point_type] = amount

	researched_node_ids = incoming_nodes
	research_points = incoming_points
	completed_experiments = islist(data["completed_experiments"]) ? data["completed_experiments"] : list()
	return TRUE

/// TRUE when this record describes a colony that has researched nothing and banked nothing.
/datum/colony_research_record/proc/is_empty()
	return !length(researched_node_ids) && !length(research_points)


/**
 * Cuts a techweb back to what a colony arrives knowing.
 *
 * A techweb researches every starting node in New() - two dozen of them - which hands a new settlement most of
 * the curve for free. This removes everything outside the campaign's starting set and rebuilds the derived
 * lists, so the colony begins where the curve begins.
 *
 * Nodes are removed rather than the set being built up, because New() has already run by the time anything can
 * intervene. Returns how many were taken away.
 */
/proc/restrict_techweb_to_campaign_start(datum/techweb/web)
	if(!istype(web))
		return 0

	var/list/allowed = CAMPAIGN_STARTING_RESEARCH_NODES
	var/removed = 0
	for(var/node_id in web.researched_nodes.Copy())
		if(node_id in allowed)
			continue
		web.researched_nodes -= node_id
		removed++

	// The colony still has to actually know its starting set, even if the techweb never granted it.
	for(var/node_id in allowed)
		var/datum/techweb_node/node = SSresearch.techweb_node_by_id(node_id)
		if(node && !web.researched_nodes[node_id])
			web.research_node(node, force = TRUE, auto_adjust_cost = FALSE, get_that_dosh = FALSE)

	// Designs and availability are derived from researched nodes, so they are rebuilt rather than edited.
	web.recalculate_nodes(recalculate_designs = TRUE)
	return removed

/// The techweb a colony's research is kept in. The station web, because it is the one everything already uses.
/proc/get_colony_techweb()
	RETURN_TYPE(/datum/techweb)
	return locate(/datum/techweb/science) in SSresearch.techwebs
