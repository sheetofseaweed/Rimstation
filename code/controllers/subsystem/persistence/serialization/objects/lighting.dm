/obj/machinery/light/get_save_vars(save_flags=ALL)
	. = ..()
	. += NAMEOF(src, status)

/obj/structure/light_construct/get_save_vars(save_flags=ALL)
	. = ..()
	. += NAMEOF(src, stage)
	. += NAMEOF(src, fixture_type)

/obj/item/flashlight/get_custom_save_vars(save_flags=ALL)
	. = ..()
	if(light_on)
		.[NAMEOF(src, start_on)] = light_on

/obj/item/flashlight/flare/get_save_vars(save_flags=ALL)
	. = ..()
	. += NAMEOF(src, fuel)
