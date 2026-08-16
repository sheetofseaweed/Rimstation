/**
 * The colony's technology curve, and what a given colony has unlocked of it.
 *
 * Deliberately separate from the station techweb. A colony is not a research station: it is not discovering
 * anything, it is remembering how to make things with what it has. So this is a small hand-authored graph of
 * capabilities rather than a points economy over hundreds of nodes, and it *filters* the fabrication designs
 * that already exist rather than duplicating them.
 *
 * The graph is an allowlist. A design no node claims cannot be built at all, which is the safe direction to
 * fail in - a design nobody placed appearing at campaign start would hand a fresh colony the station catalog -
 * and `rimstation_colony_tech_covers_designs` makes an unplaced design a failing test rather than a surprise.
 */
/datum/colony_tech_node
	/// Stable id, written into saved campaigns. Renaming one retires it for every existing colony.
	var/id
	/// Player-facing name.
	var/name
	/// Which of the six stages this reads as. Presentation; prerequisites are what actually gate it.
	var/stage
	/// Node ids that must be unlocked first. Empty means the colony starts with this one.
	var/list/prerequisites
	/// Insight this costs to unlock.
	var/cost = 0
	/// Designs this makes buildable. Typepaths rather than ids, so a mistyped design fails to compile.
	var/list/design_types
	/// One sentence, player-facing: what this lets the colony actually do.
	var/purpose

/// The design ids this node unlocks, resolved from its typepaths.
/datum/colony_tech_node/proc/get_design_ids()
	RETURN_TYPE(/list)
	var/list/design_ids = list()
	for(var/datum/design/design_type as anything in design_types)
		var/design_id = initial(design_type.id)
		if(design_id)
			design_ids += design_id
	return design_ids

/// TRUE when this node is available to a colony with nothing unlocked yet.
/datum/colony_tech_node/proc/is_root()
	return !length(prerequisites)


GLOBAL_LIST_INIT(colony_tech_nodes, build_colony_tech_graph())
GLOBAL_LIST_INIT(colony_tech_node_by_design_id, build_colony_design_index())

/// Every node, keyed by id.
/proc/build_colony_tech_graph()
	RETURN_TYPE(/list)
	var/list/nodes = list()
	for(var/datum/colony_tech_node/node_type as anything in subtypesof(/datum/colony_tech_node))
		var/datum/colony_tech_node/node = new node_type
		if(!node.id)
			stack_trace("Colony tech node [node_type] has no id.")
			continue
		if(nodes[node.id])
			stack_trace("Two colony tech nodes share the id '[node.id]'.")
			continue
		nodes[node.id] = node
	return nodes

/// Design id to the node that unlocks it. A design appearing twice is a graph error, not a merge of both.
/proc/build_colony_design_index()
	RETURN_TYPE(/list)
	var/list/index = list()
	for(var/node_id in GLOB.colony_tech_nodes)
		var/datum/colony_tech_node/node = GLOB.colony_tech_nodes[node_id]
		for(var/design_id in node.get_design_ids())
			if(index[design_id])
				stack_trace("Design '[design_id]' is claimed by both '[index[design_id]]' and '[node_id]'.")
				continue
			index[design_id] = node_id
	return index

/**
 * Everything structurally wrong with the graph, as readable sentences. Empty when it is sound.
 *
 * Written as a report rather than assertions so one test run names every problem at once; a graph with four
 * mistakes should not take four runs to fix.
 */
/proc/validate_colony_tech_graph()
	RETURN_TYPE(/list)
	var/list/problems = list()
	var/list/stages = COLONY_TECH_STAGES

	for(var/node_id in GLOB.colony_tech_nodes)
		var/datum/colony_tech_node/node = GLOB.colony_tech_nodes[node_id]

		if(!node.name || !node.purpose)
			problems += "Node '[node_id]' has no name or no stated purpose."
		if(!(node.stage in stages))
			problems += "Node '[node_id]' is in stage '[node.stage]', which is not one of the six."
		if(!length(node.design_types))
			problems += "Node '[node_id]' unlocks nothing, so unlocking it would be a purchase with no capability behind it."
		if(node.cost < 0)
			problems += "Node '[node_id]' has a negative cost."
		if(!node.is_root() && !node.cost)
			problems += "Node '[node_id]' has prerequisites but costs nothing, so it unlocks itself for free."

		for(var/prerequisite_id in node.prerequisites)
			if(!GLOB.colony_tech_nodes[prerequisite_id])
				problems += "Node '[node_id]' requires '[prerequisite_id]', which does not exist."
			if(prerequisite_id == node_id)
				problems += "Node '[node_id]' requires itself."

	problems += find_colony_tech_cycles()
	return problems

/**
 * Any node that cannot be reached from the roots, which is what a cycle looks like from outside.
 *
 * Resolved by repeatedly taking every node whose prerequisites are already satisfied. Whatever is left over
 * when that stops making progress is either in a cycle or behind one, and both are unreachable in play.
 */
/proc/find_colony_tech_cycles()
	RETURN_TYPE(/list)
	var/list/reachable = list()
	var/list/pending = GLOB.colony_tech_nodes.Copy()

	var/progressed = TRUE
	while(progressed)
		progressed = FALSE
		for(var/node_id in pending)
			var/datum/colony_tech_node/node = pending[node_id]
			var/satisfied = TRUE
			for(var/prerequisite_id in node.prerequisites)
				if(!reachable[prerequisite_id])
					satisfied = FALSE
					break
			if(!satisfied)
				continue
			reachable[node_id] = TRUE
			pending -= node_id
			progressed = TRUE

	var/list/problems = list()
	for(var/node_id in pending)
		problems += "Node '[node_id]' can never be unlocked; its prerequisites form a cycle or lead into one."
	return problems


/**
 * What one colony has unlocked, and what it has left to spend.
 *
 * Insight is earned by surviving chapters and resolving incidents, not by grinding a machine - the currency
 * exists so that progress is paced by the story rather than by how long someone stands at a lathe.
 */
/datum/colony_progression
	var/schema_version = COLONY_PROGRESSION_SCHEMA_VERSION
	/// Node ids unlocked, roots included.
	var/list/unlocked_node_ids
	/// Unspent insight.
	var/insight = 0
	/// Append-only record of every unlock. Superseded by the settlement ledger once that exists.
	var/list/unlock_log

/datum/colony_progression/New()
	. = ..()
	unlocked_node_ids = list()
	unlock_log = list()
	grant_root_nodes()

/// Roots are what a colony knows on arrival, so they are never bought.
/datum/colony_progression/proc/grant_root_nodes()
	for(var/node_id in GLOB.colony_tech_nodes)
		var/datum/colony_tech_node/node = GLOB.colony_tech_nodes[node_id]
		if(node.is_root() && !(node_id in unlocked_node_ids))
			unlocked_node_ids += node_id

/datum/colony_progression/proc/is_unlocked(node_id)
	return (node_id in unlocked_node_ids)

/// TRUE when every prerequisite of `node_id` is already unlocked.
/datum/colony_progression/proc/prerequisites_met(node_id)
	var/datum/colony_tech_node/node = GLOB.colony_tech_nodes[node_id]
	if(!node)
		return FALSE
	for(var/prerequisite_id in node.prerequisites)
		if(!is_unlocked(prerequisite_id))
			return FALSE
	return TRUE

/// Why this node cannot be unlocked right now, or null when it can.
/datum/colony_progression/proc/why_locked(node_id)
	var/datum/colony_tech_node/node = GLOB.colony_tech_nodes[node_id]
	if(!node)
		return "there is no such technology"
	if(is_unlocked(node_id))
		return "it is already known"
	if(!prerequisites_met(node_id))
		return "the colony does not know what it builds on yet"
	if(insight < node.cost)
		return "the colony has [insight] insight and needs [node.cost]"
	return null

/**
 * Unlocks a node. Returns TRUE only if this call is what unlocked it.
 *
 * Every reason to refuse is checked before anything changes, so a refused unlock cannot leave insight spent on
 * a node the colony did not get.
 */
/datum/colony_progression/proc/unlock(node_id, unlocked_by)
	if(why_locked(node_id))
		return FALSE

	var/datum/colony_tech_node/node = GLOB.colony_tech_nodes[node_id]
	insight -= node.cost
	unlocked_node_ids += node_id
	unlock_log += list(list(
		"node_id" = node_id,
		"cost" = node.cost,
		"unlocked_by" = unlocked_by,
		"at" = "[world.realtime]",
	))
	log_game("Colony unlocked technology '[node_id]' for [node.cost] insight ([unlocked_by || "unattributed"]).")
	return TRUE

/// Adds insight. Refuses negatives so that spending only ever happens through unlock().
/datum/colony_progression/proc/award_insight(amount, reason)
	if(!isnum(amount) || amount <= 0)
		return FALSE
	insight += amount
	log_game("Colony gained [amount] insight ([reason || "no reason given"]).")
	return TRUE

/// TRUE when a design may be built. Unclaimed designs are refused; see the note on the allowlist above.
/datum/colony_progression/proc/is_design_unlocked(design_id)
	var/node_id = GLOB.colony_tech_node_by_design_id[design_id]
	if(!node_id)
		return FALSE
	return is_unlocked(node_id)

/// Nodes that could be unlocked right now, cheapest first, for anything offering a choice.
/datum/colony_progression/proc/get_available_nodes()
	RETURN_TYPE(/list)
	var/list/available = list()
	for(var/node_id in GLOB.colony_tech_nodes)
		if(!is_unlocked(node_id) && prerequisites_met(node_id))
			available += node_id
	return available

/datum/colony_progression/proc/serialize()
	RETURN_TYPE(/list)
	return list(
		"schema_version" = schema_version,
		"unlocked_node_ids" = unlocked_node_ids.Copy(),
		"insight" = insight,
		"unlock_log" = unlock_log.Copy(),
	)

/**
 * Loads a progression record. Returns TRUE on success.
 *
 * Node ids that no longer exist are dropped rather than refused: retiring a node should cost a colony that
 * capability, not the whole campaign. Roots are re-granted afterwards, so a colony can never end up unable to
 * build the things it arrived knowing.
 */
/datum/colony_progression/proc/deserialize(list/data)
	if(!islist(data))
		return FALSE

	var/incoming_version = data["schema_version"]
	if(!isnum(incoming_version) || incoming_version != COLONY_PROGRESSION_SCHEMA_VERSION)
		log_game("Colony progression rejected: unsupported schema version '[incoming_version]'.")
		return FALSE

	var/incoming_insight = data["insight"]
	if(!isnum(incoming_insight) || incoming_insight < 0)
		log_game("Colony progression rejected: invalid insight '[incoming_insight]'.")
		return FALSE

	var/list/incoming_nodes = list()
	if(islist(data["unlocked_node_ids"]))
		for(var/node_id in data["unlocked_node_ids"])
			if(GLOB.colony_tech_nodes[node_id])
				incoming_nodes += node_id
			else
				log_game("Colony progression dropped retired technology '[node_id]'.")

	unlocked_node_ids = incoming_nodes
	insight = incoming_insight
	unlock_log = islist(data["unlock_log"]) ? data["unlock_log"] : list()
	grant_root_nodes()
	return TRUE
