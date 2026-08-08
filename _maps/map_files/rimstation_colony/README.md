# Rimstation Colony map seed

`rimstation_colony.dmm` is a deliberately minimal **10 × 10 × 3** editor seed.
The intended finished map size is **255 × 255 × 3**; expand and design the map
in StrongDMM or FastDMM2 before it is used for normal rounds.

Layer order is fixed:

1. **Z1 — underground:** mineable Rimstation rock. Mining exposes breathable
   subterranean stone, but cave air is finite rather than an infinite planetary
   atmosphere source.
2. **Z2 — surface:** the main colony layer, filled with Earthlike planetary soil
   and outdoor daylight.
3. **Z3 — open air:** transparent, breathable open sky. It is not a roof over Z2;
   it supports falling, future cliffs, elevated terrain, and structures.

Z2 daylight is supplied by its outdoor area lighting; it is not propagated down
from Z3. Solid terrain added to Z3 therefore does not automatically cast roof
shadows onto Z2 and will need explicit lighting/area treatment where desired.

The explicit `Up` and `Down` traits in `_maps/rimstation_colony.json` connect the
three layers. `height_autosetup` is disabled so later map edits cannot silently
change that topology.

Keep Rimstation-specific map paths in
`modular_rimstation/code/modules/colony_campaign/mapping/rimstation_colony.dm`.
Run the repository MapMerge workflow after editing the DMM; TGM format is
required.
