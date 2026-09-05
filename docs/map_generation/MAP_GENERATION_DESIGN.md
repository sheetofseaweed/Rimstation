# Rimstation colony map generation

Status: the primary colony landscape and procedural resource-site scenes described below are implemented.
Hybrid procedural ruins and chosen overmap starting-cell selection remain future work.

## Accepted design decisions

- Use a deterministic, layered landscape plan instead of extending the original binary cave mask.
- Keep the initial visual identity a temperate frontier. Forests may be dense, grasslands stay open, and scrubland
  sits between them.
- Preserve the hand-authored landing clearing and its required access paths.
- Keep rivers primarily fordable, with occasional deep pools.
- Give mountains real walkable highlands, caves beneath the same footprint, and bounded ascent points.
- Keep Z1 available for a later deep-underground cave and resource pass.
- Plan from the planet profile now and specialize through an optional selected overmap cell later.
- Generation revisions may deliberately invalidate development campaigns; individual generation streams remain
  independent so unrelated content changes do not reshuffle the landscape.

## Implemented primary-map contract

The colony uses one deterministic, layered plan derived from the planet record and generation version:

1. Z1 is deep underground.
2. Z2 is the lowland surface plus mountain interiors and entrance-connected caves.
3. Z3 is open air except where the shared elevation plan materializes walkable mountain tops, cliffs, and a
   bounded set of ascent points. It also remains the level available to player-built roofs.
4. Z4 is transparent open sky.

The Z2 wilds generator owns the shared plan and materializes both Z2 and Z3 during mapping initialization.
Mountains on Z3 therefore physically roof the same footprint on Z2. The hand-authored landing area is never
replaced; mountains, rivers, and dense ecology are suppressed through a six-tile blend following its exact
shape rather than its bounding rectangle.

Mountain tops remain solid, walkable highland grass all the way to their perimeter. Directional rocky edge and
corner overlays project into neighboring open-air tiles, using the complete plateau footprint rather than
smoothing an isolated chain of cliff turfs. Stepping past the ledge uses ordinary openspace z-falling; the native
single-z cliff-sliding turf is not used for generated mountains. River pools do not suppress cliff visuals, and
ecology keeps the exposed rim and ascent landings clear. The imported edge artwork and its distinct license
notices are recorded in `modular_rimstation/icons/turf/CREDITS.md`.

The pass order is:

1. Create a generation context from the planet, generation version, local bounds, and optional overmap cell
   identity/profile.
2. Sample deterministic elevation, ridge, heat, moisture, ecology, and cave fields.
3. Reserve and blend the authored landing clearing.
4. Classify mountain footprints.
5. Trace a continuous river through nearby low terrain, producing damp banks, fordable shallows, and occasional
   deep pools.
6. Carve cave entrance paths and grow only cave cells connected to those paths.
7. Select temperate lowland biomes and biome-specific ecology density.
8. Materialize Z2 interiors and Z3 mountain tops/cliffs from the same arrays.
9. Place bounded deterministic ascents, flora, fauna, resource features, a caravan return point, and reachable
   raid insertion proposals.

Terrain, ecology, features, and ascent selection use independent seed streams and coordinate hashes rather than
the global RNG. Changing generation behavior intentionally advances `PLANET_GENERATION_VERSION`.

## Starting-cell extension point

The current boot supplies the planet profile only. `/datum/rimstation_colony_generation_context` already accepts
an optional stable cell identity and profile. The identity namespaces seed streams; the profile is retained for
future cell-specific climate/geology inputs. This keeps starting-cell selection additive rather than requiring a
replacement generator.

Starting-cell selection must use a two-boot preparation flow. A preparation boot creates the planet and preview,
stores a validated pending campaign manifest after selection, then requests a controlled restart. The next boot
loads that record before mapping initialization and promotes it only after successful colony-map validation. The
primary colony must not be regenerated after world initialization to avoid stale lighting, atom, area, atmosphere,
and pathing state.

The pending manifest must be complete and validated before changing the active campaign pointer. A failed boot
must leave it recoverable rather than consume it. Until cell selection exists, the same preparation flow can use
planet-wide climate, geology, and ecology with no cell identity.

## Runtime expedition maps

Expedition sites continue to use their existing reservation, asynchronous loading, arrival, and objective-binding
contract. Scene providers now allow the system to select one of:

- `premade`: load an authored DMM template; transit and ruins currently use this path;
- `procedural`: reserve a bounded block and generate from a site context; resource sites now use this path;
- `hybrid`: generate terrain, then stamp an authored ruin or objective; this remains the intended next ruin step.

The resource-site context contains the planet and generation streams, stable site id, overmap coordinates,
strategic terrain/topology/danger, reservation-local bounds, and site kind. Its seeds do not depend on
`world.maxx`, absolute reservation coordinates, load order, or the global RNG. A 47 by 47 scene translates the
strategic terrain into ground cover, topology into rock density, wet biomes into deterministic streams, and
danger into sparse fauna. It guarantees an open meandering trail between the caravan arrival and deposit.

Procedural sites are runtime generation. They use a fresh turf reservation, runtime-safe `ChangeTurf`, immediate
runtime atom initialization, bounded yielding, adjacency/static-lighting rebuilds, and revalidation of the party
and campaign after asynchronous work. The primary map's pre-initialization `new turf_type(old_turf)`
materialization path is not reused for them.

The strategic site record remains persistent authority. Reservations and scene atoms remain runtime objects until
a separate design deliberately adds physical per-site persistence.

Generation may begin during the outbound journey so a destination is ready before arrival. Future providers must
preserve the existing asynchronous loading and arrival contract.

## Content policy

Prove terrain composition with existing Rimstation content, then add donor artwork selectively. Reimplement
behavior against Rimstation's APIs rather than transplanting donor gameplay code. Review provenance and licensing
for each imported asset.

NTFvsAlien is a candidate for tall grass, river presentation, wet/jungle dressing, and rocky ledges. Civ13 is a
candidate for tree silhouettes, seasonal/dead variants, bamboo, berries, and harvest ideas. The imported flora and
cliff artwork retain their respective notices in the `modular_rimstation/icons` credit files.
