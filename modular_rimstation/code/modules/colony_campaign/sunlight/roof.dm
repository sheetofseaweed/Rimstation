/**
 * A roof.
 *
 * An ordinary floor on the level above, which is all a roof needs to be: it is not transparent, so the tile
 * beneath stops seeing sky. Walkable, because a roof you can stand on is worth more than one you cannot.
 */
/turf/open/floor/rimstation_roof
	name = "roof"
	desc = "Planks and sealant laid over a frame. Keeps the sky out."
	icon_state = "wood"
	initial_gas_mix = OPENTURF_DEFAULT_ATMOS
	baseturfs = /turf/open/openspace/rimstation

/**
 * Puts a roof over this turf.
 *
 * Returns TRUE if it worked. Prefers a real turf on the level above, because that is visible and can be
 * taken apart; falls back to the override only where there is no level to build on.
 */
/turf/proc/add_roof()
	if(!is_sky_visible())
		return TRUE // Already roofed. Nothing to do, and not a failure.

	var/turf/ceiling = GET_TURF_ABOVE(src)
	if(ceiling)
		if(!istransparentturf(ceiling))
			return TRUE // Something solid is already up there.
		ceiling.place_on_top(/turf/open/floor/rimstation_roof)
		return TRUE

	roofed_override = TRUE
	reassess_sky_column()
	return TRUE

/// Takes the roof off this turf, whichever kind it is.
/turf/proc/remove_roof()
	if(roofed_override)
		roofed_override = FALSE
		reassess_sky_column()
		return

	var/turf/ceiling = GET_TURF_ABOVE(src)
	if(istype(ceiling, /turf/open/floor/rimstation_roof))
		ceiling.ScrapeAway()

/**
 * Roofs or unroofs one tile at a time.
 *
 * The manual half of roofing. Works on both kinds of map: where there is a level above it lays a real turf,
 * and where there is not it sets the per-turf override instead.
 */
/obj/item/roofing_tool
	name = "roofing tool"
	desc = "A hooked bar and a sealant gun. Roofs a tile, or takes one down."
	icon = 'icons/obj/tools.dmi'
	icon_state = "crowbar"
	inhand_icon_state = "crowbar"
	lefthand_file = 'icons/mob/inhands/equipment/tools_lefthand.dmi'
	righthand_file = 'icons/mob/inhands/equipment/tools_righthand.dmi'
	w_class = WEIGHT_CLASS_SMALL
	/// How long one tile takes.
	var/work_time = 3 SECONDS

/obj/item/roofing_tool/afterattack(atom/target, mob/user, list/modifiers, list/attack_modifiers)
	. = ..()
	var/turf/subject = get_turf(target)
	if(!subject)
		return

	var/roofing = subject.is_sky_visible()
	balloon_alert(user, roofing ? "roofing..." : "stripping roof...")
	if(!do_after(user, work_time, subject))
		return

	if(roofing)
		subject.add_roof()
		balloon_alert(user, "roofed")
	else
		subject.remove_roof()
		balloon_alert(user, "roof stripped")

/**
 * Roofs a whole enclosed room in one use.
 *
 * Uses the same room detection the blueprints do, so what counts as a room is one rule rather than two.
 * Refuses an unsealed space rather than roofing an arbitrary blob, because a kit that roofed open ground
 * would be a far better tool than the roofing tool and would retire it.
 */
/obj/item/roof_kit
	name = "roofing kit"
	desc = "Enough beams, planks and sealant to cover a small room. Stand inside and use it."
	icon = 'icons/obj/storage/toolbox.dmi'
	icon_state = "toolbox_default"
	inhand_icon_state = "toolbox_default"
	lefthand_file = 'icons/mob/inhands/equipment/toolbox_lefthand.dmi'
	righthand_file = 'icons/mob/inhands/equipment/toolbox_righthand.dmi'
	w_class = WEIGHT_CLASS_BULKY
	/// The largest room this covers.
	var/max_tiles = 100
	/// How long the whole job takes.
	var/work_time = 10 SECONDS
	/// How many rooms are left in this kit.
	var/uses = 3

/obj/item/roof_kit/attack_self(mob/user, modifiers)
	. = ..()
	if(!uses)
		balloon_alert(user, "kit is empty!")
		return

	var/turf/standing = get_turf(user)
	var/list/room = detect_room(standing, list(), max_tiles + 1)

	if(!length(room))
		balloon_alert(user, "not sealed!")
		return
	if(length(room) > max_tiles)
		balloon_alert(user, "room too big!")
		return

	balloon_alert(user, "roofing room...")
	if(!do_after(user, work_time, standing))
		return

	for(var/turf/covered as anything in room)
		covered.add_roof()
		CHECK_TICK

	uses--
	balloon_alert(user, uses ? "roofed, [uses] left" : "roofed, kit empty")
	if(!uses)
		desc = "Empty. The beams are gone and the sealant tube is dry."
