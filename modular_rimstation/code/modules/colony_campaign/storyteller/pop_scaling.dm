/**
 * Population scaling for storyteller event frequency.
 *
 * Upstream shipped this as dead code - the vars and config entries existed, nothing read them - and has since
 * deleted it. We read it: `get_population_frequency_multiplier()` is part of how `add_points()` paces a track,
 * so the storage it needs lives here rather than back in the upstream file that dropped it.
 *
 * A colony round is small, so the penalty is what keeps a three-person settlement from being paced like a
 * full station. Turn it off with ALLOW_STORYTELLER_POP_SCALING in config/bubbers/storyteller.txt.
 */

/// Pop at which a track stops being penalised. Below it the penalty eases in towards the full amount.
#define MUNDANE_POP_SCALE_THRESHOLD 25
#define MODERATE_POP_SCALE_THRESHOLD 32
#define MAJOR_POP_SCALE_THRESHOLD 45
#define CREWSET_POP_SCALE_THRESHOLD 45
#define GHOSTSET_POP_SCALE_THRESHOLD 45

/// Largest penalty pop scaling applies, as a percentage, reached at minimum population.
#define MUNDANE_POP_SCALE_PENALTY 35
#define MODERATE_POP_SCALE_PENALTY 35
#define MAJOR_POP_SCALE_PENALTY 35
#define CREWSET_POP_SCALE_PENALTY 35
#define GHOSTSET_POP_SCALE_PENALTY 35

/datum/controller/subsystem/gamemode
	/// Whether we allow pop scaling. Set by config, or the storyteller UI.
	var/allow_pop_scaling = TRUE

	/// Associative list of pop scale thresholds.
	var/list/pop_scale_thresholds = list(
		EVENT_TRACK_MUNDANE = MUNDANE_POP_SCALE_THRESHOLD,
		EVENT_TRACK_MODERATE = MODERATE_POP_SCALE_THRESHOLD,
		EVENT_TRACK_MAJOR = MAJOR_POP_SCALE_THRESHOLD,
		EVENT_TRACK_CREWSET = CREWSET_POP_SCALE_THRESHOLD,
		EVENT_TRACK_GHOSTSET = GHOSTSET_POP_SCALE_THRESHOLD,
	)

	/// Associative list of pop scale penalties.
	var/list/pop_scale_penalties = list(
		EVENT_TRACK_MUNDANE = MUNDANE_POP_SCALE_PENALTY,
		EVENT_TRACK_MODERATE = MODERATE_POP_SCALE_PENALTY,
		EVENT_TRACK_MAJOR = MAJOR_POP_SCALE_PENALTY,
		EVENT_TRACK_CREWSET = CREWSET_POP_SCALE_PENALTY,
		EVENT_TRACK_GHOSTSET = GHOSTSET_POP_SCALE_PENALTY,
	)

/datum/config_entry/flag/allow_storyteller_pop_scaling

/datum/config_entry/number/mundane_pop_scale_threshold
	default = MUNDANE_POP_SCALE_THRESHOLD
	integer = TRUE
	min_val = 0

/datum/config_entry/number/moderate_pop_scale_threshold
	default = MODERATE_POP_SCALE_THRESHOLD
	integer = TRUE
	min_val = 0

/datum/config_entry/number/major_pop_scale_threshold
	default = MAJOR_POP_SCALE_THRESHOLD
	integer = TRUE
	min_val = 0

/datum/config_entry/number/crewset_pop_scale_threshold
	default = CREWSET_POP_SCALE_THRESHOLD
	integer = TRUE
	min_val = 0

/datum/config_entry/number/ghostset_pop_scale_threshold
	default = GHOSTSET_POP_SCALE_THRESHOLD
	integer = TRUE
	min_val = 0

/datum/config_entry/number/mundane_pop_scale_penalty
	default = MUNDANE_POP_SCALE_PENALTY
	integer = TRUE
	min_val = 0

/datum/config_entry/number/moderate_pop_scale_penalty
	default = MODERATE_POP_SCALE_PENALTY
	integer = TRUE
	min_val = 0

/datum/config_entry/number/major_pop_scale_penalty
	default = MAJOR_POP_SCALE_PENALTY
	integer = TRUE
	min_val = 0

/datum/config_entry/number/crewset_pop_scale_penalty
	default = CREWSET_POP_SCALE_PENALTY
	integer = TRUE
	min_val = 0

/datum/config_entry/number/ghostset_pop_scale_penalty
	default = GHOSTSET_POP_SCALE_PENALTY
	integer = TRUE
	min_val = 0
