/**
 * Independent generation streams derived from one planet root seed.
 *
 * Each stream gets its own derived seed so that adding content to one concern does not reshuffle the
 * others: new ruin themes must not move the terrain a colony was already built on.
 */
#define PLANET_STREAM_TERRAIN "terrain"
#define PLANET_STREAM_BIOME_HEAT "biome_heat"
#define PLANET_STREAM_BIOME_HUMIDITY "biome_humidity"
#define PLANET_STREAM_RESOURCES "resources"
#define PLANET_STREAM_RUINS "ruins"
#define PLANET_STREAM_ECOLOGY "ecology"

/// Every stream a planet definition will derive. Adding one here is safe; renaming one retires old worlds.
#define PLANET_GENERATION_STREAMS list( \
	PLANET_STREAM_TERRAIN, \
	PLANET_STREAM_BIOME_HEAT, \
	PLANET_STREAM_BIOME_HUMIDITY, \
	PLANET_STREAM_RESOURCES, \
	PLANET_STREAM_RUINS, \
	PLANET_STREAM_ECOLOGY, \
)

/// Record layout version. Bump when the serialized shape changes, and add a migration.
#define PLANET_DEFINITION_SCHEMA_VERSION 1

/**
 * Generation behaviour version, mixed into every derived seed.
 *
 * Bump this only when a generator change should deliberately produce different worlds from the same root
 * seed. Existing campaigns keep the version stored in their own record, so they stay reproducible.
 */
#define PLANET_GENERATION_VERSION 1

/// Length of a derived stream seed in hex characters.
#define PLANET_STREAM_SEED_LENGTH 16

/**
 * Axis selectors for biome sampling drift.
 *
 * These live here rather than beside BIOME_RANDOM_SQUARE_DRIFT in CaveGenerator.dm because that file undefines
 * its own macros at the bottom, which would put them out of reach of the colony generator and its tests.
 */
#define BIOME_DRIFT_AXIS_X "x"
#define BIOME_DRIFT_AXIS_Y "y"

/// Root seed for the development colony world, used until a campaign manifest chooses one.
#define RIMSTATION_DEVELOPMENT_PLANET_SEED "rimstation-development-world"

/// Faction shared by colonists and their animals. Anything outside it can contest the core.
#define RIMSTATION_COLONY_FACTION "rimstation_colony"


/// The colony core is held. Nothing hostile is standing on it.
#define COLONY_CORE_SECURE "secure"
/// Hostiles are on the core and capture progress is accumulating.
#define COLONY_CORE_CONTESTED "contested"
/// The core has been held long enough to fall. Terminal.
#define COLONY_CORE_CAPTURED "captured"

/// The chapter is still being played.
#define COLONY_OUTCOME_PENDING "pending"
/// The colony survived the chapter, damage included.
#define COLONY_OUTCOME_SUCCESS "success"
/// The colony lost the chapter through an explicit, legible condition.
#define COLONY_OUTCOME_FAILURE "failure"

/// Sent when the core starts being contested. Args: (obj/structure/colony_core/core)
#define COMSIG_COLONY_CORE_CONTESTED "colony_core_contested"
/// Sent when attackers are cleared and progress resets. Args: (obj/structure/colony_core/core)
#define COMSIG_COLONY_CORE_SECURED "colony_core_secured"
/// Sent when the core is held long enough to fall. Args: (obj/structure/colony_core/core)
#define COMSIG_COLONY_CORE_CAPTURED "colony_core_captured"
/// Sent when the core is destroyed outright rather than captured. Args: (obj/structure/colony_core/core)
#define COMSIG_COLONY_CORE_DESTROYED "colony_core_destroyed"

// Raid lifecycle. Strictly forward: the telegraph is the colony's preparation window and cannot be skipped.
#define COLONY_RAID_QUEUED "queued"
#define COLONY_RAID_WARNING "warning"
#define COLONY_RAID_ASSEMBLING "assembling"
#define COLONY_RAID_ARRIVING "arriving"
#define COLONY_RAID_ASSAULTING "assaulting"
#define COLONY_RAID_RETREATING "retreating"
#define COLONY_RAID_RESOLVED "resolved"

/// Ordered lifecycle. Position in this list is what makes a transition forward or backward.
#define COLONY_RAID_STATE_ORDER list( \
	COLONY_RAID_QUEUED, \
	COLONY_RAID_WARNING, \
	COLONY_RAID_ASSEMBLING, \
	COLONY_RAID_ARRIVING, \
	COLONY_RAID_ASSAULTING, \
	COLONY_RAID_RETREATING, \
	COLONY_RAID_RESOLVED, \
)

/// The raid never deployed, usually because no validated insertion point existed.
#define COLONY_RAID_OUTCOME_CANCELLED "cancelled"
/// The colony killed or drove off the attackers.
#define COLONY_RAID_OUTCOME_REPELLED "repelled"
/// The attackers took the core.
#define COLONY_RAID_OUTCOME_SUCCEEDED "succeeded"

// Campaign lifecycle. SScampaign is the only thing allowed to move between these.
/// No campaign exists yet.
#define CAMPAIGN_STATE_NONE "none"
/// Selecting and loading a committed checkpoint.
#define CAMPAIGN_STATE_LOADING "loading"
/// A chapter is being played.
#define CAMPAIGN_STATE_ACTIVE "active"
/// Staging and promoting a new checkpoint. Mutation is quiesced.
#define CAMPAIGN_STATE_COMMITTING "committing"
/// Between chapters, with a committed checkpoint to return to.
#define CAMPAIGN_STATE_INTERMISSION "intermission"
/// The generation lost. Its checkpoint pointer is cleared and never promoted.
#define CAMPAIGN_STATE_DEFEATED "defeated"
/// Waiting to build a fresh generation on next boot.
#define CAMPAIGN_STATE_RESET_PENDING "reset_pending"
/// Something ended abnormally. Explicitly not defeat.
#define CAMPAIGN_STATE_RECOVERY "recovery"

/**
 * Legal lifecycle transitions.
 *
 * Written out rather than inferred so that "can a lost campaign quietly become an active one" has a single,
 * readable answer. Note defeat leads only to reset_pending: there is no path from defeated back to active.
 */
#define CAMPAIGN_STATE_TRANSITIONS list( \
	CAMPAIGN_STATE_NONE = list(CAMPAIGN_STATE_LOADING, CAMPAIGN_STATE_RECOVERY), \
	CAMPAIGN_STATE_LOADING = list(CAMPAIGN_STATE_ACTIVE, CAMPAIGN_STATE_RECOVERY), \
	CAMPAIGN_STATE_ACTIVE = list(CAMPAIGN_STATE_COMMITTING, CAMPAIGN_STATE_DEFEATED, CAMPAIGN_STATE_RECOVERY), \
	CAMPAIGN_STATE_COMMITTING = list(CAMPAIGN_STATE_INTERMISSION, CAMPAIGN_STATE_RECOVERY), \
	CAMPAIGN_STATE_INTERMISSION = list(CAMPAIGN_STATE_LOADING, CAMPAIGN_STATE_ACTIVE, CAMPAIGN_STATE_RECOVERY), \
	CAMPAIGN_STATE_DEFEATED = list(CAMPAIGN_STATE_RESET_PENDING), \
	CAMPAIGN_STATE_RESET_PENDING = list(CAMPAIGN_STATE_LOADING), \
	CAMPAIGN_STATE_RECOVERY = list(CAMPAIGN_STATE_LOADING, CAMPAIGN_STATE_ACTIVE), \
)

/**
 * Manifest layout version. Bump with a migration, never in place.
 *
 * 1: original layout.
 * 2: generations are counted, so the next one can be named without reading the previous ones.
 * 3: the colony carries its research between chapters.
 * 4: the settlement carries its ledger between chapters.
 */
#define CAMPAIGN_MANIFEST_SCHEMA_VERSION 4

/// Research record layout version. Migrated alongside the manifest that carries it.
#define COLONY_RESEARCH_SCHEMA_VERSION 1

/// Settlement ledger layout version. Migrated alongside the manifest that carries it.
#define COLONY_LEDGER_SCHEMA_VERSION 1

/**
 * Which bank account holds the settlement's money.
 *
 * The cargo budget, because it is the account order consoles and payment components already spend from - a
 * separate colony purse would be money the rest of the game could not see.
 */
#define CAMPAIGN_LEDGER_ACCOUNT ACCOUNT_CAR

/// Admin event-panel heading for colony incidents. Its own so the five controls group together rather than
/// scattering across station categories none of them really belong to.
#define EVENT_CATEGORY_COLONY "Colony"

// Colony incident lifecycle. Strictly forward, like a raid's: the warning is the colony's chance to prepare
// and cannot be skipped. Cancellation is the one jump out, and it is available until the incident resolves.
#define COLONY_INCIDENT_QUEUED "queued"
#define COLONY_INCIDENT_WARNING "warning"
#define COLONY_INCIDENT_ACTIVE "active"
#define COLONY_INCIDENT_RESOLVING "resolving"
#define COLONY_INCIDENT_RESOLVED "resolved"
#define COLONY_INCIDENT_CANCELLED "cancelled"

/// Ordered lifecycle. Position in this list is what makes a transition forward or backward.
#define COLONY_INCIDENT_STATE_ORDER list( \
	COLONY_INCIDENT_QUEUED, \
	COLONY_INCIDENT_WARNING, \
	COLONY_INCIDENT_ACTIVE, \
	COLONY_INCIDENT_RESOLVING, \
	COLONY_INCIDENT_RESOLVED, \
)

// What kind of story an incident tells. The storyteller buys a category; the campaign picks which incident
// within it, so pacing and content stay separable.
#define COLONY_INCIDENT_CATEGORY_POSITIVE "positive"
#define COLONY_INCIDENT_CATEGORY_NEUTRAL "neutral"
#define COLONY_INCIDENT_CATEGORY_ENVIRONMENTAL "environmental"
#define COLONY_INCIDENT_CATEGORY_SOCIAL "social"
#define COLONY_INCIDENT_CATEGORY_RESOURCE "resource"

#define COLONY_INCIDENT_CATEGORIES list( \
	COLONY_INCIDENT_CATEGORY_POSITIVE, \
	COLONY_INCIDENT_CATEGORY_NEUTRAL, \
	COLONY_INCIDENT_CATEGORY_ENVIRONMENTAL, \
	COLONY_INCIDENT_CATEGORY_SOCIAL, \
	COLONY_INCIDENT_CATEGORY_RESOURCE, \
)

/**
 * Where a colony decision can be answered.
 *
 * Per incident rather than global. A trader hailing the settlement belongs on a communications console and
 * would be absurd answered by touching the colony core; a dispute between colonists is the opposite. A colony
 * with no console has an in-game problem to solve, not a broken incident.
 */
#define INCIDENT_ANSWER_CONSOLE (1<<0)
#define INCIDENT_ANSWER_COLONY_CORE (1<<1)

/// How long the colony gets to answer before a decision expires unanswered.
#define COLONY_DECISION_TIMEOUT (3 MINUTES)

/// How many recent incidents count against repeating one. Short: a colony should not remember forever.
#define COLONY_INCIDENT_HISTORY_WINDOW 4

/// Story state layout version. Lives inside the manifest's storyteller_state, which needs no schema of its own.
#define COLONY_STORY_SCHEMA_VERSION 1
/// How many incident results the pacing state keeps.
#define COLONY_STORY_INCIDENT_WINDOW 8
/**
 * Bounds on how far pacing may bend an event's weight.
 *
 * Never zero at the bottom: a multiplier that reaches zero retires an event silently, which is indistinguishable
 * from a bug. Never unbounded at the top: one favoured event crowding out every other is its own kind of bad
 * pacing.
 */
#define COLONY_STORY_MIN_MULTIPLIER 0.25
#define COLONY_STORY_MAX_MULTIPLIER 2
/// Recovery at or above which the colony is too battered to be handed another disaster.
#define COLONY_STORY_HARD_RECOVERY 80
/// Selection weight an incident starts from before recency is taken off it.
#define COLONY_INCIDENT_BASE_WEIGHT 100
/**
 * The least an incident's weight can fall to.
 *
 * Never zero. Recency should make the same story less likely, never impossible - otherwise a category whose
 * incidents have all run recently becomes unbuyable, and the storyteller quietly loses a whole kind of event
 * at exactly the moment the colony has been through the most.
 */
#define COLONY_INCIDENT_MINIMUM_WEIGHT 5

// Incident tags. Shared flavour, used to stop the same kind of thing landing twice in a row.
#define INCIDENT_TAG_ARRIVAL "arrival"
#define INCIDENT_TAG_WEATHER "weather"
#define INCIDENT_TAG_TRADE "trade"
#define INCIDENT_TAG_UNREST "unrest"
#define INCIDENT_TAG_HARVEST "harvest"
#define INCIDENT_TAG_MINING "mining"

/// The colony came out ahead, or did what the incident asked.
#define COLONY_INCIDENT_OUTCOME_SUCCEEDED "succeeded"
/// The colony came out behind.
#define COLONY_INCIDENT_OUTCOME_FAILED "failed"
/// Nobody engaged with it, which is a legitimate answer and not a failure.
#define COLONY_INCIDENT_OUTCOME_IGNORED "ignored"

// Ledger categories. Broad on purpose: an entry says which kind of activity moved the money, and the reason
// code says what specifically happened.
#define LEDGER_CATEGORY_TRADE "trade"
#define LEDGER_CATEGORY_INCIDENT "incident"
#define LEDGER_CATEGORY_RESEARCH "research"
#define LEDGER_CATEGORY_SALVAGE "salvage"
#define LEDGER_CATEGORY_UPKEEP "upkeep"
#define LEDGER_CATEGORY_ADMIN "admin"

/**
 * How much more research costs during a campaign.
 *
 * A station researches for one round and is scrapped; a colony keeps what it learns for good. At station
 * prices a campaign would own the whole techweb within a couple of sessions, so the same research is stretched
 * across the campaign rather than replaced with a second currency.
 */
#define CAMPAIGN_RESEARCH_COST_MULTIPLIER 5

/**
 * Root of all campaign-owned storage.
 *
 * Under `_maps/` rather than `data/` because a map config resolves its DMM as `_maps/<map_path>/<map_file>`,
 * with the prefix hardcoded - a checkpoint stored anywhere else can be written but never loaded again. It is
 * still kept out of `_maps/persistence/`, so the autosave scanning and pruning code never sees a campaign
 * checkpoint: being invisible to `get_last_save()` is what stops a lost town from being picked up again.
 */
#define CAMPAIGN_STORAGE_ROOT "_maps/colony_campaign/"

/// Name offered when starting a campaign, if the admin has no preference.
#define CAMPAIGN_DEFAULT_ID "colony"

/// Names which campaign this server runs. Without it a server has no way to know, since several campaigns can
/// sit side by side in storage and picking by scan would make the colony depend on directory order.
#define CAMPAIGN_ACTIVE_POINTER "active_campaign.json"

/// Filename written last inside a staged checkpoint, marking the whole set as finished.
/// Lives here rather than beside the checkpoint code because storage.dm is included after checkpoint.dm.
#define CHECKPOINT_COMPLETION_MARKER "checkpoint_complete.json"

/// Written when a chapter starts and matched by an end record when it finishes. An open record with no end
/// is the signature of a crash, and is what keeps an interrupted round from being read as a defeat.
#define CAMPAIGN_CHAPTER_OPEN_PREFIX "chapter_open."
/// Written when a chapter ends for any legible reason, win or loss.
#define CAMPAIGN_CHAPTER_END_PREFIX "chapter_end."
/// Immutable record of why a generation was closed. Written once and never rewritten.
#define CAMPAIGN_CLOSURE_RECORD "closure.json"

/// How far in from the map edge a raid may arrive.
#define COLONY_RAID_EDGE_BAND 6
/// How close to the settlement centre a raid may never arrive.
#define COLONY_RAID_EXCLUSION_RADIUS 24
/// Ceiling on the walkable-region flood fill, so a pathological map cannot stall a raid indefinitely.
#define COLONY_RAID_REACHABILITY_LIMIT 70000
/**
 * Tiles between waypoints on a raid's approach route.
 *
 * Must stay comfortably below AI_MAX_PATH_LENGTH (30): basic-mob JPS refuses to path further than that, so a
 * raid crossing a 255-tile map has to be handed the journey one short hop at a time.
 */
#define COLONY_RAID_WAYPOINT_SPACING 15
/// How close an attacker must get to a waypoint before it is handed the next one.
#define COLONY_RAID_WAYPOINT_ARRIVAL_DISTANCE 3
