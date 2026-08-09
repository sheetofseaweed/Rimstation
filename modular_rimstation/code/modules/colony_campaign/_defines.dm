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
