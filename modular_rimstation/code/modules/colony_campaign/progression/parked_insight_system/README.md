# Parked: the insight progression system

**None of the files in this directory are compiled.** They are not in `tgstation.dme` and the tests are not in
`_unit_tests.dm`. They are kept here because they may be wanted again, not because they are in use.

## What this was

A colony technology curve independent of the station techweb: 20 hand-authored nodes across six stages
(`survival`, `craft`, `agriculture`, `power`, `industry`, `advanced`), covering all 138 designs the colony
fabricator can build, bought with a currency called *insight*.

- `tech.dm` — `/datum/colony_tech_node`, `/datum/colony_progression`, graph validation and cycle detection.
- `nodes.dm` — the 20 nodes and their design assignments.
- `tests_progression.dm` — graph soundness, design coverage in both directions, unlock atomicity, persistence.

## Why it was parked

It reimplemented the techweb. A pool of points spent to unlock nodes that reveal designs is structurally the
same system the game already has, with a second currency bolted on, and it gave players no say in how they
earned it. The decision was to persist the *real* techweb across chapters instead and raise research costs, so
that progress comes from research work players already understand and choose.

The hole that surfaced it: `insight` was named once in the phase plan and no plan step ever said how it was
earned. The implementation had a spend path and no source, so a colony could never unlock anything.

## What is worth keeping if this comes back

The design-coverage test is the valuable part. It asserts in both directions that every colony-fabricator
design belongs to exactly one node and that no node claims a design that does not exist. It caught three
things that reading the source did not: that the rations printer designs are `BIOGENERATOR` rather than
`COLONY_FABRICATOR`, that five designs are flagged from unrelated modules, and that eight flag additions in
the colony fabricator module target design types that were never defined.

## When to reach for it

If persisted techweb turns out to be too easy to cheese — a colony that reaches the full station catalog in
one or two chapters, or research points that can be farmed faster than the curve is meant to move. This graph
is an allowlist and does not care how points were obtained, so it is immune to that failure in a way the
techweb is not.
