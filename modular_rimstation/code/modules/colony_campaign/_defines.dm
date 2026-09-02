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

/// Sent on a /datum/colony_raid when it finishes, whatever the outcome. (outcome, reason)
#define COMSIG_COLONY_RAID_RESOLVED "colony_raid_resolved"

// What a raid came for. The core is the settlement itself; theft is somebody who would rather rob you than
// live where you live, and leaves once their arms are full.
#define COLONY_RAID_GOAL_CORE "core"
#define COLONY_RAID_GOAL_THEFT "theft"

/// How many things one attacker can carry away. Bounded so a single raider cannot empty a settlement.
#define COLONY_RAID_LOOT_CAPACITY 3

/**
 * How often a raid that could rob the colony does that instead of coming for the core.
 *
 * Weighted towards theft on purpose. Losing the core ends the campaign, so a raid that can do it should be the
 * exception rather than the usual roll - otherwise the storyteller is repeatedly deciding whether the whole
 * thing continues. Being robbed costs something a colony can rebuild.
 */
#define COLONY_RAID_THEFT_CHANCE 65

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
 * 5: the colony remembers who lives in it.
 * 6: the colony has a region around it.
 */
#define CAMPAIGN_MANIFEST_SCHEMA_VERSION 6

/// Research record layout version. Migrated alongside the manifest that carries it.
#define COLONY_RESEARCH_SCHEMA_VERSION 1

/// Settlement ledger layout version. Migrated alongside the manifest that carries it.
#define COLONY_LEDGER_SCHEMA_VERSION 1

/// Colonist roster layout version. Migrated alongside the manifest that carries it.
#define COLONY_ROSTER_SCHEMA_VERSION 1

// ---------------------------------------------------------------------------------------------------------
// Planetary overworld.
//
// The region is never stored. It is rebuilt from the planet's seeds plus the three campaign options, so only
// the options, what play discovered, and what play changed are written down. Changing any generation rule
// below means bumping OVERWORLD_GENERATION_VERSION, or two builds will disagree about the same planet while
// both believing they are right.
// ---------------------------------------------------------------------------------------------------------

/// Overworld record layout version. Migrated alongside the manifest that carries it.
#define COLONY_OVERWORLD_SCHEMA_VERSION 1

/// Bump whenever any generation rule changes. Regions built by different versions are not comparable.
#define OVERWORLD_GENERATION_VERSION 1

/**
 * The six axial neighbours of any cell, as list(q offset, r offset).
 *
 * Lives here rather than beside the hex maths because every overworld file walks neighbours, and DM resolves
 * defines in include order - a constant declared in region.dm is invisible to anything that sorts before it.
 */
#define OVERWORLD_AXIAL_DIRECTIONS list( \
	list(1, 0), \
	list(1, -1), \
	list(0, -1), \
	list(-1, 0), \
	list(-1, 1), \
	list(0, 1), \
)

/**
 * How much of a derived hash is kept per cell.
 *
 * Six hex digits, because BYOND numbers are 32-bit floats and only represent integers exactly up to 2**24 -
 * which is exactly six hex digits. A longer slice would be converted approximately, and a modulo taken from an
 * approximate value is not reliably the same number twice.
 */
#define OVERWORLD_HASH_LENGTH 6

// How much of the planet the region covers. Radius is in hexes from the colony.
#define OVERWORLD_EXTENT_COMPACT "compact"
#define OVERWORLD_EXTENT_STANDARD "standard"
#define OVERWORLD_EXTENT_EXPANSIVE "expansive"

#define OVERWORLD_EXTENTS list( \
	OVERWORLD_EXTENT_COMPACT, \
	OVERWORLD_EXTENT_STANDARD, \
	OVERWORLD_EXTENT_EXPANSIVE, \
)

/// Radius in hexes for each extent. Cell count is 1 + 3r(r + 1).
#define OVERWORLD_EXTENT_RADII list( \
	OVERWORLD_EXTENT_COMPACT = 7, \
	OVERWORLD_EXTENT_STANDARD = 9, \
	OVERWORLD_EXTENT_EXPANSIVE = 11, \
)

// How hard the ground is to cross.
#define OVERWORLD_ROUGHNESS_GENTLE "gentle"
#define OVERWORLD_ROUGHNESS_VARIED "varied"
#define OVERWORLD_ROUGHNESS_RUGGED "rugged"

#define OVERWORLD_ROUGHNESS_OPTIONS list( \
	OVERWORLD_ROUGHNESS_GENTLE, \
	OVERWORLD_ROUGHNESS_VARIED, \
	OVERWORLD_ROUGHNESS_RUGGED, \
)

// How much there is worth going out for.
#define OVERWORLD_ABUNDANCE_SPARSE "sparse"
#define OVERWORLD_ABUNDANCE_NORMAL "normal"
#define OVERWORLD_ABUNDANCE_RICH "rich"

#define OVERWORLD_ABUNDANCE_OPTIONS list( \
	OVERWORLD_ABUNDANCE_SPARSE, \
	OVERWORLD_ABUNDANCE_NORMAL, \
	OVERWORLD_ABUNDANCE_RICH, \
)

// How hard one cell is to cross. Impassable cells are terrain, not a route the planner may take.
#define OVERWORLD_TOPOLOGY_EASY "easy"
#define OVERWORLD_TOPOLOGY_NORMAL "normal"
#define OVERWORLD_TOPOLOGY_DIFFICULT "difficult"
#define OVERWORLD_TOPOLOGY_IMPASSABLE "impassable"

/// Seconds of campaign time to cross one cell before its topology multiplier.
#define OVERWORLD_BASE_TRAVERSAL_SECONDS 45

/// Traversal multiplier per topology. Impassable is absent on purpose: it has no crossing time.
#define OVERWORLD_TOPOLOGY_COSTS list( \
	OVERWORLD_TOPOLOGY_EASY = 1, \
	OVERWORLD_TOPOLOGY_NORMAL = 1.5, \
	OVERWORLD_TOPOLOGY_DIFFICULT = 2, \
)

/// Percentage split of easy/normal/difficult/impassable per roughness, in that order. Must total 100.
#define OVERWORLD_TOPOLOGY_WEIGHTS list( \
	OVERWORLD_ROUGHNESS_GENTLE = list(65, 28, 6, 1), \
	OVERWORLD_ROUGHNESS_VARIED = list(45, 35, 16, 4), \
	OVERWORLD_ROUGHNESS_RUGGED = list(30, 35, 25, 10), \
)

/// Danger bias added to the ecology percentile before it is banded, per roughness.
#define OVERWORLD_ROUGHNESS_DANGER_BIAS list( \
	OVERWORLD_ROUGHNESS_GENTLE = -10, \
	OVERWORLD_ROUGHNESS_VARIED = 0, \
	OVERWORLD_ROUGHNESS_RUGGED = 10, \
)

// What a site is. The kind decides its marker, its physical template and what resolving it pays.
#define OVERWORLD_SITE_RESOURCE "resource"
#define OVERWORLD_SITE_RUIN "ruin"

/// Resource sites per extent and abundance.
#define OVERWORLD_RESOURCE_SITE_COUNTS list( \
	OVERWORLD_EXTENT_COMPACT = list(OVERWORLD_ABUNDANCE_SPARSE = 2, OVERWORLD_ABUNDANCE_NORMAL = 4, OVERWORLD_ABUNDANCE_RICH = 6), \
	OVERWORLD_EXTENT_STANDARD = list(OVERWORLD_ABUNDANCE_SPARSE = 4, OVERWORLD_ABUNDANCE_NORMAL = 6, OVERWORLD_ABUNDANCE_RICH = 9), \
	OVERWORLD_EXTENT_EXPANSIVE = list(OVERWORLD_ABUNDANCE_SPARSE = 6, OVERWORLD_ABUNDANCE_NORMAL = 9, OVERWORLD_ABUNDANCE_RICH = 13), \
)

/// Ruins per extent. Abundance buys resources, not history.
#define OVERWORLD_RUIN_SITE_COUNTS list( \
	OVERWORLD_EXTENT_COMPACT = 2, \
	OVERWORLD_EXTENT_STANDARD = 3, \
	OVERWORLD_EXTENT_EXPANSIVE = 4, \
)

/// Inclusive ledger-unit yield band per abundance, as list(low, high).
#define OVERWORLD_RESOURCE_YIELDS list( \
	OVERWORLD_ABUNDANCE_SPARSE = list(20, 35), \
	OVERWORLD_ABUNDANCE_NORMAL = list(35, 55), \
	OVERWORLD_ABUNDANCE_RICH = list(50, 75), \
)

/// How far the colony can see without going anywhere.
#define OVERWORLD_INITIAL_REVEAL_RADIUS 2

// What play has done to a site. Absent means untouched, which is the overwhelmingly common case and is why
// only changed sites are ever written down.
#define OVERWORLD_SITE_STATE_AVAILABLE "available"
#define OVERWORLD_SITE_STATE_RESOLVED "resolved"
#define OVERWORLD_SITE_STATE_DEPLETED "depleted"

#define OVERWORLD_SITE_STATES list( \
	OVERWORLD_SITE_STATE_AVAILABLE, \
	OVERWORLD_SITE_STATE_RESOLVED, \
	OVERWORLD_SITE_STATE_DEPLETED, \
)

// The starter ruin sits here: far enough that it has to be travelled to, close enough to be an early trip.
#define OVERWORLD_STARTER_RUIN_MIN_DISTANCE 4
#define OVERWORLD_STARTER_RUIN_MAX_DISTANCE 6

// Strategic terrain labels. Palette and pattern ids for the map, never turf types.
#define OVERWORLD_TERRAIN_FROZEN_STEPPE "frozen_steppe"
#define OVERWORLD_TERRAIN_TUNDRA "tundra"
#define OVERWORLD_TERRAIN_TAIGA "taiga"
#define OVERWORLD_TERRAIN_SCRUBLAND "scrubland"
#define OVERWORLD_TERRAIN_GRASSLAND "grassland"
#define OVERWORLD_TERRAIN_FOREST "forest"
#define OVERWORLD_TERRAIN_DESERT "desert"
#define OVERWORLD_TERRAIN_SAVANNA "savanna"
#define OVERWORLD_TERRAIN_MARSH "marsh"

/// Heat band (cold/temperate/hot) by humidity band (dry/moderate/wet). Split at 33 and 67.
#define OVERWORLD_TERRAIN_TABLE list( \
	list(OVERWORLD_TERRAIN_FROZEN_STEPPE, OVERWORLD_TERRAIN_TUNDRA, OVERWORLD_TERRAIN_TAIGA), \
	list(OVERWORLD_TERRAIN_SCRUBLAND, OVERWORLD_TERRAIN_GRASSLAND, OVERWORLD_TERRAIN_FOREST), \
	list(OVERWORLD_TERRAIN_DESERT, OVERWORLD_TERRAIN_SAVANNA, OVERWORLD_TERRAIN_MARSH), \
)

/// The only job a colony offers. A settlement has no departments and no chain of command to staff.
#define JOB_COLONIST "Colonist"

// How a caravan moves through its journey. Forward only: a party that has finished, or been lost, is a closed
// record. Reopening one would let a journey pay out twice.
/// Being assembled at home. The only state membership and route can change in.
#define OVERWORLD_PARTY_FORMING "forming"
/// Committed and paid for, with the leaving scene being brought up.
#define OVERWORLD_PARTY_DEPARTING "departing"
/// On the road, between cells.
#define OVERWORLD_PARTY_OUTBOUND "outbound"
/// Halted at a boundary, waiting for somebody to answer for the party.
#define OVERWORLD_PARTY_DECISION "decision"
/// Arrived, and working the site.
#define OVERWORLD_PARTY_AT_SITE "at_site"
/// On the way back.
#define OVERWORLD_PARTY_RETURNING "returning"
/// Home, paid out. Terminal.
#define OVERWORLD_PARTY_COMPLETE "complete"
/// Gone. Terminal.
#define OVERWORLD_PARTY_LOST "lost"

/// Every state a party can be in, for validation on load.
#define OVERWORLD_PARTY_STATES list( \
	OVERWORLD_PARTY_FORMING, \
	OVERWORLD_PARTY_DEPARTING, \
	OVERWORLD_PARTY_OUTBOUND, \
	OVERWORLD_PARTY_DECISION, \
	OVERWORLD_PARTY_AT_SITE, \
	OVERWORLD_PARTY_RETURNING, \
	OVERWORLD_PARTY_COMPLETE, \
	OVERWORLD_PARTY_LOST, \
)

/// States a party can no longer leave. Checked before any transition rather than listed at each call site.
#define OVERWORLD_PARTY_TERMINAL_STATES list( \
	OVERWORLD_PARTY_COMPLETE, \
	OVERWORLD_PARTY_LOST, \
)

/// A party still at home, where its membership and plan can still be edited.
#define OVERWORLD_PARTY_IS_PLANNING(state) ((state) == OVERWORLD_PARTY_FORMING)

// The two routes the planner offers. Both are real paths through the region; they differ in what they treat
// as expensive, so a player picks between hours and hazard rather than between a good route and a bad one.
/// Least travel time, ignoring what lives out there.
#define OVERWORLD_ROUTE_FASTEST "fastest"
/// Least travel time once danger is priced in.
#define OVERWORLD_ROUTE_SAFER "safer"

/// Route kinds a party may be carrying.
#define OVERWORLD_ROUTE_KINDS list( \
	OVERWORLD_ROUTE_FASTEST, \
	OVERWORLD_ROUTE_SAFER, \
)

/**
 * What one danger pip is worth to the safer route, in seconds of detour it would accept to avoid it.
 *
 * This is the whole difference between the two routes. Too low and the safer route is the fast one with extra
 * steps; too high and it walks the region's rim to dodge a single pip.
 */
#define OVERWORLD_DANGER_TIME_PENALTY 30

/// Nobody may sign on to a party alone-and-endless. A cap keeps the colony from being emptied into one caravan.
#define OVERWORLD_PARTY_MAX_MEMBERS 6

/// Food eaten per member per crossed boundary, plus a reserve for the way back.
#define OVERWORLD_SUPPLY_PER_EDGE 2
/// Extra rations per member, held against waits and detours on the road.
#define OVERWORLD_SUPPLY_RESERVE 2

/// The ledger resource a caravan eats. The same pile the refugee incident feeds from - there is one larder.
#define OVERWORLD_SUPPLY_RESOURCE "food"

/// The one food figure in the campaign. The larder is what makes it non-zero; see economy/larder.dm.
#define COLONY_FOOD_RESOURCE "food"

/**
 * How much nutriment makes one unit of stored food.
 *
 * Calibrated against real items rather than picked: a loaf of bread is ten nutriment and a slice of it is two,
 * so a loaf stocks five units and a slice stocks one. Feeding a refugee costs fifteen, which is three loaves.
 */
#define COLONY_FOOD_UNIT_NUTRIMENT 2

/// What one unit of food costs bought in. The rate the refugee incident already charges: 15 food for 300cr.
#define COLONY_FOOD_CREDIT_PRICE 20

/// Journeys, as the settlement's books see them.
#define LEDGER_CATEGORY_EXPEDITION "expedition"

// Lazy-loaded scenes an expedition can be standing in. Keyed rather than pathed because that is what
// GLOB.lazy_templates is indexed by; the datums themselves live in overworld/destinations.dm.
/// The camp the party travels in.
#define LAZY_TEMPLATE_KEY_RIMSTATION_TRANSIT "LT_RIMSTATION_TRANSIT"
/// A mineral deposit worth walking to.
#define LAZY_TEMPLATE_KEY_RIMSTATION_RESOURCE_SITE "LT_RIMSTATION_RESOURCE_SITE"
/// Somebody else's survey post, long abandoned.
#define LAZY_TEMPLATE_KEY_RIMSTATION_RUIN_SITE "LT_RIMSTATION_RUIN_SITE"

/**
 * What recovering a ruin's archive is worth to the settlement, in credits.
 *
 * Paid in the money the colony already spends rather than a second currency. A ruin is worth roughly what a
 * deposit is, bought differently: ore is carried home and can be lost on the road, where an archive is a
 * transfer that either happened or did not.
 */
#define OVERWORLD_RUIN_ARCHIVE_CREDITS 500

/// What a resource site pays out in, until there is more than one kind of deposit.
#define OVERWORLD_SITE_RESOURCE_ID "iron"

/**
 * How long a party stands at a site before the deposit is worked out.
 *
 * Short on purpose. The interesting part of an expedition is deciding to go and getting back, not standing
 * still watching a bar - and a chapter is one round, which is not long to spend on one trip.
 */
#define OVERWORLD_SITE_WORK_SECONDS 60

/// How long a funded wait at a boundary holds the party for before the original leg is scheduled anyway.
#define OVERWORLD_DECISION_WAIT_SECONDS 90

/// What forcing through costs a body that is present to feel it.
#define OVERWORLD_DECISION_FORCE_STAMINA 20
#define OVERWORLD_DECISION_FORCE_BRUTE 5

/// What shouting an animal down takes out of everybody who does the shouting.
#define OVERWORLD_DECISION_SCARE_STAMINA 10

/// A short delay: looking at something without going to it.
#define OVERWORLD_DECISION_LOOK_SECONDS 45

// The three kinds of problem a road can present. Each is a datum in overworld/decisions.dm; these are the
// ids those datums are filed and answered under.
#define OVERWORLD_DECISION_WEATHER "weather_front"
#define OVERWORLD_DECISION_SPOOR "predator_spoor"
#define OVERWORLD_DECISION_SMOKE "distant_smoke"

// Weather: take the damage, take the time, or take the long road.
#define OVERWORLD_CHOICE_PRESS_ON "press_on"
#define OVERWORLD_CHOICE_SHELTER "shelter"
#define OVERWORLD_CHOICE_SKIRT "skirt"

// Spoor: how much noise to make about it.
#define OVERWORLD_CHOICE_KEEP_QUIET "keep_quiet"
#define OVERWORLD_CHOICE_SCARE_OFF "scare_off"
#define OVERWORLD_CHOICE_HUNT "hunt"

// Smoke: how much of the map it is worth buying.
#define OVERWORLD_CHOICE_IGNORE "ignore"
#define OVERWORLD_CHOICE_OBSERVE "observe"
#define OVERWORLD_CHOICE_INVESTIGATE "investigate"

/**
 * How often each kind of problem comes up, by how rough the country is.
 *
 * Frequency only. A rugged region meets more weather and more animals than a gentle one, but a weather
 * front costs exactly the same on both - the world decides what you run into, never what it charges.
 */
#define OVERWORLD_DECISION_ECOLOGY_WEIGHTS list( \
	OVERWORLD_ROUGHNESS_GENTLE = list(OVERWORLD_DECISION_WEATHER = 2, OVERWORLD_DECISION_SPOOR = 2, OVERWORLD_DECISION_SMOKE = 3), \
	OVERWORLD_ROUGHNESS_VARIED = list(OVERWORLD_DECISION_WEATHER = 3, OVERWORLD_DECISION_SPOOR = 3, OVERWORLD_DECISION_SMOKE = 2), \
	OVERWORLD_ROUGHNESS_RUGGED = list(OVERWORLD_DECISION_WEATHER = 4, OVERWORLD_DECISION_SPOOR = 4, OVERWORLD_DECISION_SMOKE = 1), \
)

/**
 * How close to the hitching post everyone has to be before a caravan will leave.
 *
 * Three rather than one on purpose: a departure that fails because somebody is standing one tile off is a
 * departure nobody can diagnose. Three is close enough to read as "gathered here" and loose enough to forgive.
 */
#define OVERWORLD_GATHER_RADIUS 3

// What a colonist is to the campaign right now. A record is never deleted, only moved between these.
/// Played this chapter.
#define COLONIST_STATUS_ACTIVE "active"
/// On the roster, but nobody played them this chapter. They have no body and are owed nothing.
#define COLONIST_STATUS_AWAY "away"
/// Died in the colony. Kept on the roster so the colony remembers them.
#define COLONIST_STATUS_DEAD "dead"

/// Every status a stored record is allowed to claim. Anything else is a corrupted or hand-edited record.
#define COLONIST_STATUSES list( \
	COLONIST_STATUS_ACTIVE, \
	COLONIST_STATUS_AWAY, \
	COLONIST_STATUS_DEAD, \
)

/**
 * Every key a serialized colonist record is allowed to carry.
 *
 * Declared here rather than left implicit in serialize() so that adding a field is a deliberate act with a test
 * behind it. The campaign must never grow a habit of storing whatever happens to be on a player.
 */
#define COLONIST_RECORD_FIELDS list( \
	"colonist_id", \
	"display_name", \
	"owner_ckey", \
	"generation_joined", \
	"chapter_joined", \
	"chapters_attended", \
	"status", \
	"skills", \
	"home_point", \
)

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
/// Somebody comes to take what the colony has. The category raids are scheduled through.
#define COLONY_INCIDENT_CATEGORY_THREAT "threat"

#define COLONY_INCIDENT_CATEGORIES list( \
	COLONY_INCIDENT_CATEGORY_POSITIVE, \
	COLONY_INCIDENT_CATEGORY_NEUTRAL, \
	COLONY_INCIDENT_CATEGORY_ENVIRONMENTAL, \
	COLONY_INCIDENT_CATEGORY_SOCIAL, \
	COLONY_INCIDENT_CATEGORY_RESOURCE, \
	COLONY_INCIDENT_CATEGORY_THREAT, \
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
#define INCIDENT_TAG_RAIDERS "raiders"

// How hard a scheduled raid hits. A full threat model belongs with the rest of the raid work; this is the
// honest minimum - a raid that grows with the colony and backs off after it has been hurt.
/// Threat points a first-chapter raid is worth.
#define COLONY_RAID_BASE_BUDGET 60
/// Extra threat points per chapter the campaign has survived.
#define COLONY_RAID_BUDGET_PER_CHAPTER 12
/// The most a raid can ever be worth, however old the colony gets.
#define COLONY_RAID_MAX_BUDGET 260

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
/// Goods carried off the map by a raid. A loss the colony can read back, rather than things quietly missing.
#define LEDGER_CATEGORY_THEFT "theft"

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

/**
 * What a colony arrives already knowing.
 *
 * A station techweb researches two dozen starting nodes in New(), which hands a new settlement most of the
 * curve for free. A colony gets the four that a landing party would plausibly bring: how to build, how to make
 * parts, how to do science at all, and how to work raw material.
 */
#define CAMPAIGN_STARTING_RESEARCH_NODES list( \
	TECHWEB_NODE_CONSTRUCTION, \
	TECHWEB_NODE_PARTS, \
	TECHWEB_NODE_FUNDIMENTAL_SCI, \
	TECHWEB_NODE_MATERIAL_PROC, \
)
