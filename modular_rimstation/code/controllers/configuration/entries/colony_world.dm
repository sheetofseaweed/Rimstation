// The generated colony world.

/**
 * Pins the colony world a server with no campaign generates.
 *
 * Blank by default, which gives a new landscape every boot. A campaign records its own world and ignores this
 * entirely; this exists for the rounds played outside one, where nothing on disk says which world it was.
 *
 * Any text works, and the same text always rebuilds the same landscape, so this is how a report about
 * generated terrain is made reproducible on another boot or another machine.
 */
/datum/config_entry/string/colony_world_seed
