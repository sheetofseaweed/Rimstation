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

/// How far in from the map edge a raid may arrive.
#define COLONY_RAID_EDGE_BAND 6
/// How close to the settlement centre a raid may never arrive.
#define COLONY_RAID_EXCLUSION_RADIUS 24
