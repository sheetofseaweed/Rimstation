// Object persistence not fitting any other category.

/obj/vehicle/sealed/mecha
	/// Tracks whether we have already initialized once with our built-in parts populated.
	var/parts_changed_once = FALSE

/obj/vehicle/sealed/mecha/Initialize(mapload, built_manually)
	if(!parts_changed_once)
		parts_changed_once = TRUE
		return ..()

	for(var/key in equip_by_category)
		if(!islist(equip_by_category[key]))
			equip_by_category[key] = null
		else
			equip_by_category[key] = list()

	built_manually = TRUE
	return ..()

/obj/vehicle/sealed/mecha/PersistentInitialize()
	. = ..()
	for(var/obj/item/mecha_parts/mecha_equipment/equip in contents)
		if(equip.chassis == src)
			continue
		equip.attach(src, equip.was_right_attached)
	locate_parts()

/obj/vehicle/sealed/mecha/get_save_vars(save_flags=ALL)
	. = ..()
	. += NAMEOF(src, parts_changed_once)

/obj/vehicle/sealed/mecha/on_object_saved(map_string, turf/current_loc, list/obj_blacklist)
	save_stored_contents(map_string, current_loc, obj_blacklist)

/obj/item/mecha_parts/mecha_equipment
	var/was_right_attached = FALSE

/obj/item/mecha_parts/mecha_equipment/attach(obj/vehicle/sealed/mecha/new_mecha, attach_right = FALSE)
	was_right_attached = attach_right
	return ..()

/obj/item/mecha_parts/mecha_equipment/get_custom_save_vars(save_flags=ALL)
	. = ..()
	if(!was_right_attached)
		return
	.[NAMEOF(src, was_right_attached)] = TRUE
