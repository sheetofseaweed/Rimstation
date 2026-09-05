/**
 * Temperate wilderness content for generated Rimstation landscapes.
 *
 * The sprites are unmodified Civ13 assets; see modular_rimstation/icons/obj/flora/CREDITS.md. Their original
 * behavior is deliberately not ported. These types use Rimstation's current flora harvesting and lifecycle.
 */

/obj/structure/flora/tree/rimstation_deciduous
	name = "broadleaf tree"
	desc = "A mature deciduous tree with a wide green crown."
	icon = 'modular_rimstation/icons/obj/flora/civ13_bigtrees.dmi'
	icon_state = "tree_1"

/obj/structure/flora/tree/rimstation_deciduous/style_2
	icon_state = "tree_2"

/obj/structure/flora/tree/rimstation_deciduous/style_3
	icon_state = "tree_3"

/obj/structure/flora/tree/rimstation_deciduous/style_4
	icon_state = "tree_4"

/obj/structure/flora/tree/rimstation_deciduous/style_5
	icon_state = "tree_5"

/obj/structure/flora/tree/pine/rimstation
	desc = "A tall evergreen pine, well adapted to the colony's uplands."
	icon = 'modular_rimstation/icons/obj/flora/civ13_pinetrees.dmi'
	icon_state = "pine_1"

/obj/structure/flora/tree/pine/rimstation/style_2
	icon_state = "pine_2"

/obj/structure/flora/tree/pine/rimstation/style_3
	icon_state = "pine_3"

/obj/structure/flora/grass/rimstation_tall
	name = "tall meadow grass"
	desc = "A waist-high stand of hardy meadow grass."
	icon = 'modular_rimstation/icons/obj/flora/civ13_wild.dmi'
	icon_state = "tall_grass_1"

/obj/structure/flora/grass/rimstation_tall/style_2
	icon_state = "tall_grass_2"

/obj/structure/flora/grass/rimstation_tall/style_3
	icon_state = "tall_grass_3"

/obj/structure/flora/grass/rimstation_tall/style_4
	icon_state = "tall_grass_6"

/obj/structure/flora/grass/rimstation_tall/style_5
	icon_state = "tall_grass_8"

/obj/structure/flora/bush/rimstation_berry
	name = "wild berry shrub"
	desc = "A low shrub heavy with small edible berries."
	icon = 'modular_rimstation/icons/obj/flora/civ13_berries.dmi'
	icon_state = "tintobush_1"
	harvest_with_hands = TRUE
	harvest_amount_low = 1
	harvest_amount_high = 3
	harvested_name = "picked wild berry shrub"
	harvested_desc = "A low berry shrub. New fruit has not ripened yet."
	regrowth_time_low = 10 MINUTES
	regrowth_time_high = 18 MINUTES
	var/harvested_icon_state = "tintobush_2"

/obj/structure/flora/bush/rimstation_berry/style_2
	icon_state = "marronbush_1"
	harvested_icon_state = "marronbush_2"

/obj/structure/flora/bush/rimstation_berry/style_3
	icon_state = "zelenyybush_1"
	harvested_icon_state = "zelenyybush_2"

/obj/structure/flora/bush/rimstation_berry/get_potential_products()
	return list(/obj/item/food/grown/berries = 1)

/obj/structure/flora/bush/rimstation_berry/after_harvest(user)
	icon_state = harvested_icon_state
	update_appearance()
	return ..()

/obj/structure/flora/bush/rimstation_berry/regrow()
	. = ..()
	icon_state = initial(icon_state)
	update_appearance()
	return .

/obj/structure/flora/rimstation_fallen_log
	name = "fallen log"
	desc = "A weathered tree trunk slowly returning to the soil."
	icon = 'modular_rimstation/icons/obj/flora/civ13_wild.dmi'
	icon_state = "tree_log"
	max_integrity = 80
	can_uproot = FALSE
	harvest_amount_low = 2
	harvest_amount_high = 4
	harvest_message_low = "You salvage a little sound wood from the fallen trunk."
	harvest_message_med = "You cut several useful logs from the fallen trunk."
	harvest_message_high = "You recover most of the sound wood from the fallen trunk."
	harvest_verb = "saw"
	harvest_verb_suffix = "s apart"
	delete_on_harvest = TRUE
	flora_flags = FLORA_WOODEN

/obj/structure/flora/rimstation_fallen_log/get_potential_products()
	return list(/obj/item/grown/log/tree = 1)
