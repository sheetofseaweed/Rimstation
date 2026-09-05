/**
 * A generator that burns what a colony can cut down.
 *
 * Everything here is P.A.C.M.A.N. - the chassis, the sprite, the fuel hopper, the anchoring, the heat - except
 * what goes in it. Plasma sheets are not something a settlement has on the day it lands. Wood is.
 *
 * The sprite is inherited on purpose. Do not give it an icon of its own without drawing one; the parent's
 * `portgen0` states are what this is meant to look like.
 */
/obj/machinery/power/port_gen/pacman/firebox
	name = "\improper firebox generator"
	desc = "A cast iron firebox bolted onto a P.A.C.M.A.N. chassis. It burns wooden planks for a modest trickle \
		of power and asks for a great many of them. Must be <b>wrenched to the floor</b> and <b>sat on a wire</b> \
		before it will power anything."
	circuit = /obj/item/circuitboard/machine/firebox
	power_gen = 4 KILO JOULES
	max_sheets = 50
	// Wood is a poor fuel. Less power than plasma, and a sheet goes three times as fast.
	time_per_sheet = 60
	sheet_path = /obj/item/stack/sheet/mineral/wood

/// The parent reads a P.A.C.M.A.N. board to pick between plasma and uranium. A firebox has neither mode.
/obj/machinery/power/port_gen/pacman/firebox/on_construction(mob/user)
	return

/**
 * A firebox bursts and scatters its fire rather than detonating.
 *
 * The inherited overheat is a devastating explosion, which is right for a plasma reactor and wrong for a stove.
 * The machine is still destroyed - UseFuel() deletes it either way - but what it leaves is a fire a colony can
 * fight rather than a crater it has to rebuild around.
 */
/obj/machinery/power/port_gen/pacman/firebox/overheat()
	visible_message(span_danger("[src] splits along its seams and spills its fire across the floor!"))
	explosion(src, light_impact_range = 1, flame_range = 3, flash_range = 2)

/// The same firebox fed something that burns hotter and lasts longer.
/obj/machinery/power/port_gen/pacman/firebox/coal
	name = "\improper coal firebox generator"
	desc = "A cast iron firebox bolted onto a P.A.C.M.A.N. chassis, with the grate set for coal. It burns hotter \
		and far longer than the wood-fired pattern. Must be <b>wrenched to the floor</b> and <b>sat on a wire</b> \
		before it will power anything."
	circuit = /obj/item/circuitboard/machine/firebox/coal
	power_gen = 8 KILO JOULES
	time_per_sheet = 150
	sheet_path = /obj/item/stack/sheet/mineral/coal


/obj/item/circuitboard/machine/firebox
	name = "Firebox Generator"
	greyscale_colors = CIRCUIT_COLOR_ENGINEERING
	build_path = /obj/machinery/power/port_gen/pacman/firebox
	req_components = list(
		/obj/item/stack/cable_coil = 5,
		/obj/item/stack/sheet/iron = 5,
	)
	needs_anchored = FALSE

/obj/item/circuitboard/machine/firebox/coal
	name = "Coal Firebox Generator"
	build_path = /obj/machinery/power/port_gen/pacman/firebox/coal


/**
 * Both boards carry COLONY_FABRICATOR deliberately.
 *
 * The colony tech graph is an allowlist over exactly that flag, so a design without it cannot be placed in a
 * node - and one placed in a node without it fails rimstation_colony_tech_covers_designs.
 */
/datum/design/board/firebox
	name = "Firebox Generator Board"
	desc = "The circuit board for a generator that burns wooden planks."
	id = "firebox_generator"
	build_type = IMPRINTER | AWAY_IMPRINTER | COLONY_FABRICATOR
	build_path = /obj/item/circuitboard/machine/firebox
	category = list(
		RND_CATEGORY_MACHINE + RND_SUBCATEGORY_MACHINE_ENGINEERING,
	)
	departmental_flags = DEPARTMENT_BITFLAG_ENGINEERING

/datum/design/board/firebox/coal
	name = "Coal Firebox Generator Board"
	desc = "The circuit board for a generator that burns coal."
	id = "firebox_generator_coal"
	build_path = /obj/item/circuitboard/machine/firebox/coal
