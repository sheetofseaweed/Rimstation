/**
 * Roof-based sunlight.
 *
 * A tile is dark because something is above it, not because of a flag on its area. These defines carry the
 * plane the sunlight mask draws on, the three states a tile can be in, and the tuning for how far daylight
 * reaches past a roof edge.
 */

/// Grayscale sunlight masks draw here. Relayed onto the turf lighting plate with BLEND_ADD.
/// 13 is the only free plane between RENDER_PLANE_TURF_LIGHTING and RENDER_PLANE_EMISSIVE.
#define SUNLIGHTING_PLANE 13

/// Something above us blocks the sky. No sunlight of our own.
#define SKY_BLOCKED 0
/// Nothing above us, and no roofed neighbour. Fully lit, casts nothing.
#define SKY_VISIBLE 1
/// Nothing above us, but a neighbour is roofed. Fully lit, and casts light inward.
#define SKY_VISIBLE_BORDER 2

/// Set while a turf is sitting in the corner queue, so it is only queued once.
#define TURF_SUNLIGHT_QUEUED (1<<9)

/// Set while a turf is sitting in the sky-state queue. A flag, not a list search: these queues reach six
/// figures at init, and `|=` on a list that size is quadratic.
#define TURF_SKY_STATE_QUEUED (1<<10)

/// How many tiles daylight reaches past a roof edge.
#define SUNLIGHT_SPREAD_RANGE 3

/// Softens the falloff cone so tiles just inside a doorway are not instantly dark.
#define SUNLIGHT_FALLOFF_SOFTENING 0.5

/**
 * Distance-based strength of one sunlit tile on one corner. Corner and turf are the two arguments.
 *
 * The radicand is clamped because the softening term makes it negative at short range, and sqrt of a negative
 * is a runtime. The nearest real corner sits exactly on the boundary, so this is not a theoretical case.
 */
#define SUNLIGHT_FALLOFF(corner, source) (1 - CLAMP01(sqrt(max(0, (corner.x - source.x) ** 2 + (corner.y - source.y) ** 2 - SUNLIGHT_FALLOFF_SOFTENING)) / SUNLIGHT_SPREAD_RANGE))

/// Colour matrix for a tile in full daylight. Rimstation has no LIGHTING_BASE_MATRIX to borrow.
#define SUNLIGHT_FULL_MATRIX list( \
	1, 1, 1, 0, \
	1, 1, 1, 0, \
	1, 1, 1, 0, \
	1, 1, 1, 0, \
	0, 0, 0, 1  \
)

/// One full day, in deciseconds, when no config value is set. Two real hours, about one shift.
#define SUNLIGHT_DEFAULT_DAY_LENGTH (2 HOURS)

/// Safety bound on the startup drain. Settling takes a handful of passes; anything near this is a bug.
#define SUNLIGHT_MAX_INIT_PASSES 100

/// Name of the colour filter that carries the time of day on each client's sunlight plane.
#define SUNLIGHT_TINT_FILTER "sunlight_tint"

/// How far past a step's start to land when setting the clock to it, as a fraction of a day.
/// Landing exactly on the boundary rounds a hair short and falls through to the previous step.
/// About 43 seconds of game time, which is under three real seconds at the default day length.
#define SUNLIGHT_STEP_NUDGE 0.0005
