/**
 * The first playable technology curve.
 *
 * Every design the colony fabricator can build is placed in exactly one node, and every node unlocks something
 * concrete. There are no placeholder nodes: a node that unlocks nothing is a purchase with no capability
 * behind it, and the graph validator refuses one.
 *
 * The shape of the curve is the point. A colony starts able to dig, chop, cut and light a room, and has to
 * work through metalwork and power before it reaches the things that end the early game - rapid construction
 * devices and advanced stock parts sit behind the whole chain rather than being three clicks from arrival.
 */

// ---------------------------------------------------------------------------------------------------------
// Survival. What the colonists stepped off the shuttle already knowing. Roots: never bought.
// ---------------------------------------------------------------------------------------------------------

/datum/colony_tech_node/survival_toolkit
	id = "survival_toolkit"
	name = "Hand Tools"
	stage = COLONY_TECH_STAGE_SURVIVAL
	purpose = "Replace the hand tools, containers and small personal effects the colony landed with."
	design_types = list(
		/datum/design/shovel,
		/datum/design/pickaxe,
		/datum/design/hatchet,
		/datum/design/survival_knife,
		/datum/design/crowbar,
		/datum/design/flashlight,
		/datum/design/light_bulb,
		/datum/design/light_tube,
		/datum/design/bucket,
		/datum/design/mop,
		/datum/design/broom,
		/datum/design/plunger,
		/datum/design/tray,
		/datum/design/bowl,
		/datum/design/oven_tray,
		/datum/design/beaker,
		/datum/design/handlabeler,
		/datum/design/paperroll,
		/datum/design/spraycan,
		/datum/design/plastic_hair_tie,
	)

/datum/colony_tech_node/survival_shelter
	id = "survival_shelter"
	name = "Shelter"
	stage = COLONY_TECH_STAGE_SURVIVAL
	purpose = "Put a floor, a wall and a door between the colony and the weather."
	design_types = list(
		/datum/design/prefab_floor_tile,
		/datum/design/prefab_cat_floor_tile,
		/datum/design/prefab_manual_airlock_kit,
		/datum/design/colony_fab_plastic_wall_panel,
	)

/datum/colony_tech_node/survival_hazards
	id = "survival_hazards"
	name = "Field Safety"
	stage = COLONY_TECH_STAGE_SURVIVAL
	purpose = "Deal with fire, bad air and unmarked ground without losing anyone to them."
	design_types = list(
		/datum/design/extinguisher,
		/datum/design/emergency_oxygen_engi,
		/datum/design/generic_gas_tank,
		/datum/design/holosignatmos,
		/datum/design/holosignengi,
		/datum/design/mining_scanner,
		/datum/design/analyzer,
	)

// ---------------------------------------------------------------------------------------------------------
// Craft. Working metal and feeding people properly.
// ---------------------------------------------------------------------------------------------------------

/datum/colony_tech_node/craft_metalwork
	id = "craft_metalwork"
	name = "Metalworking"
	stage = COLONY_TECH_STAGE_CRAFT
	prerequisites = list("survival_toolkit")
	cost = 2
	purpose = "Cut, weld and drive fastenings, which everything built after this depends on."
	design_types = list(
		/datum/design/colony_arc_welder,
		/datum/design/colony_power_driver,
		/datum/design/colony_compact_drill,
		/datum/design/welding_goggles,
		/datum/design/welding_helmet,
		/datum/design/bolter_wrench,
		/datum/design/multitool,
		/datum/design/tscanner,
	)

/datum/colony_tech_node/craft_glassworking
	id = "craft_glassworking"
	name = "Glassworking"
	stage = COLONY_TECH_STAGE_CRAFT
	prerequisites = list("craft_metalwork")
	cost = 2
	purpose = "Make reinforced glass and cast rods, so the colony can build something it can see out of."
	design_types = list(
		/datum/design/rglass,
		/datum/design/lavarods,
	)

/datum/colony_tech_node/craft_fittings
	id = "craft_fittings"
	name = "Fittings"
	stage = COLONY_TECH_STAGE_CRAFT
	prerequisites = list("craft_metalwork")
	cost = 3
	purpose = "Fit powered doors, shutters and finishing to buildings that already stand."
	design_types = list(
		/datum/design/prefab_airlock_kit,
		/datum/design/prefab_shutters_kit,
		/datum/design/light_replacer,
		/datum/design/airlock_painter/decal,
		/datum/design/pipe_painter,
		/datum/design/polarizer,
	)

/datum/colony_tech_node/craft_kitchen
	id = "craft_kitchen"
	name = "Cooking"
	stage = COLONY_TECH_STAGE_CRAFT
	prerequisites = list("survival_toolkit")
	cost = 2
	purpose = "Cook raw ingredients into meals worth eating, instead of eating them raw."
	design_types = list(
		/datum/design/macrowave,
		/datum/design/frontier_range,
		/datum/design/tabletop_griddle,
		/datum/design/foodricator,
		/datum/design/frontier_sustenance_dispenser,
	)

// ---------------------------------------------------------------------------------------------------------
// Agriculture. The food supply that does not run out.
// ---------------------------------------------------------------------------------------------------------

/datum/colony_tech_node/agri_tools
	id = "agri_tools"
	name = "Cultivation"
	stage = COLONY_TECH_STAGE_AGRICULTURE
	prerequisites = list("survival_toolkit")
	cost = 2
	purpose = "Work soil properly, so a plot can be planted more than once."
	design_types = list(
		/datum/design/cultivator,
		/datum/design/spade,
		/datum/design/secateurs,
		/datum/design/watering_can,
		/datum/design/plant_analyzer,
		/datum/design/portaseeder,
	)

/datum/colony_tech_node/agri_hydroponics
	id = "agri_hydroponics"
	name = "Hydroponics"
	stage = COLONY_TECH_STAGE_AGRICULTURE
	prerequisites = list("agri_tools", "craft_metalwork")
	cost = 4
	purpose = "Grow and water crops indoors, out of reach of the weather outside."
	design_types = list(
		/datum/design/board/hydroponics,
		/datum/design/hydro_synthesizer,
		/datum/design/water_synthesizer,
		/datum/design/water_recycler,
	)

// ---------------------------------------------------------------------------------------------------------
// Power. Everything past here needs something to run on.
// ---------------------------------------------------------------------------------------------------------

/datum/colony_tech_node/power_basics
	id = "power_basics"
	name = "Wiring and Cells"
	stage = COLONY_TECH_STAGE_POWER
	prerequisites = list("craft_metalwork")
	cost = 3
	purpose = "Run cable, store a charge and put a panel in the sun."
	design_types = list(
		/datum/design/cable_coil,
		/datum/design/apc_board,
		/datum/design/flatpack_solar_panel,
		/datum/design/flatpack_power_storage,
		/datum/design/inducer,
	)

/datum/colony_tech_node/power_generation
	id = "power_generation"
	name = "Generation"
	stage = COLONY_TECH_STAGE_POWER
	prerequisites = list("power_basics")
	cost = 5
	purpose = "Generate power through the night and through bad weather, not only at noon."
	design_types = list(
		/datum/design/flatpack_solar_tracker,
		/datum/design/flatpack_rtg,
		/datum/design/flatpack_solids_generator,
		/datum/design/flatpack_bootleg_teg,
		/datum/design/board/solarcontrol,
		/datum/design/board/powermonitor,
	)

/datum/colony_tech_node/power_distribution
	id = "power_distribution"
	name = "Distribution"
	stage = COLONY_TECH_STAGE_POWER
	prerequisites = list("power_basics")
	cost = 4
	purpose = "Hold a real reserve and charge equipment away from the generators."
	design_types = list(
		/datum/design/flatpack_power_storage_large,
		/datum/design/wall_mounted_multi_charger,
		/datum/design/board/cyborgrecharger,
	)

// ---------------------------------------------------------------------------------------------------------
// Industry. Turning the ground into materials, and materials into machines.
// ---------------------------------------------------------------------------------------------------------

/datum/colony_tech_node/industry_smelting
	id = "industry_smelting"
	name = "Smelting"
	stage = COLONY_TECH_STAGE_INDUSTRY
	prerequisites = list("power_basics", "craft_glassworking")
	cost = 5
	purpose = "Smelt ore into alloys and stop throwing away everything that breaks."
	design_types = list(
		/datum/design/flatpack_arc_furnace,
		/datum/design/flatpack_ore_silo,
		/datum/design/plasteel_alloy,
		/datum/design/plaglass_alloy,
		/datum/design/plasmarglass_alloy,
		/datum/design/portable_recycler,
	)

/datum/colony_tech_node/industry_fabrication
	id = "industry_fabrication"
	name = "Fabrication"
	stage = COLONY_TECH_STAGE_INDUSTRY
	prerequisites = list("industry_smelting")
	cost = 6
	purpose = "Build a second fabricator and the machine boards that let the colony specialise."
	design_types = list(
		/datum/design/flatpack_colony_fabricator,
		/datum/design/board/processor,
		/datum/design/board/reagentgrinder,
		/datum/design/board/suit_storage_unit,
	)

/datum/colony_tech_node/industry_atmospherics
	id = "industry_atmospherics"
	name = "Atmospherics"
	stage = COLONY_TECH_STAGE_INDUSTRY
	prerequisites = list("power_basics", "craft_fittings")
	cost = 6
	purpose = "Move, filter and heat air, so the colony can hold a sealed room against the planet."
	design_types = list(
		/datum/design/portable_gas_pump,
		/datum/design/portable_gas_scrubber,
		/datum/design/ducts,
		/datum/design/gas_filter,
		/datum/design/plasma_tank,
		/datum/design/plasmaman_gas_filter,
		/datum/design/vox_gas_filter,
		/datum/design/plasmaman_tank_belt,
		/datum/design/plasmarefiller,
		/datum/design/flatpack_thermomachine,
		/datum/design/co2_cracker,
		/datum/design/wall_mounted_space_heater,
		/datum/design/board/atmosalerts,
		/datum/design/airalarm_electronics,
		/datum/design/firealarm_electronics,
		/datum/design/firelock_board,
		/datum/design/airlock_board,
	)

/datum/colony_tech_node/industry_automation
	id = "industry_automation"
	name = "Automation"
	stage = COLONY_TECH_STAGE_INDUSTRY
	prerequisites = list("power_basics")
	cost = 5
	// Cameras, intercoms, newscasters, request consoles and sparkers would belong here too, but the inherited
	// module flags them onto design types that were never defined, so they do not exist to be unlocked.
	purpose = "Move goods and trigger machinery across the settlement without a colonist doing the walking."
	design_types = list(
		/datum/design/conveyor_belt,
		/datum/design/conveyor_switch,
		/datum/design/prox_sensor,
		/datum/design/signaler,
		/datum/design/timer,
		/datum/design/infrared_emitter,
		/datum/design/ignition_control,
		/datum/design/control,
		/datum/design/radio_navigation_beacon,
	)

// ---------------------------------------------------------------------------------------------------------
// Advanced. The end of the early game, and deliberately a long way from the start of it.
// ---------------------------------------------------------------------------------------------------------

/datum/colony_tech_node/advanced_components
	id = "advanced_components"
	name = "Precision Components"
	stage = COLONY_TECH_STAGE_ADVANCED
	prerequisites = list("industry_fabrication")
	cost = 8
	purpose = "Build the high-grade parts every late machine is assembled from."
	design_types = list(
		/datum/design/super_cell,
		/datum/design/adv_capacitor,
		/datum/design/adv_scanning,
		/datum/design/nano_servo,
		/datum/design/high_micro_laser,
		/datum/design/adv_matter_bin,
		/datum/design/rped,
	)

/datum/colony_tech_node/advanced_rapid_construction
	id = "advanced_rapid_construction"
	name = "Rapid Construction"
	stage = COLONY_TECH_STAGE_ADVANCED
	prerequisites = list("advanced_components")
	cost = 10
	// The most expensive node in the graph, and the last one, because it retires the building game the rest of
	// the curve is about. A colony reaching this has earned the right to stop laying floors by hand.
	purpose = "Build and demolish at speed, retiring hand construction entirely."
	design_types = list(
		/datum/design/rcd_ammo,
		/datum/design/rld_mini,
		/datum/design/rtd_loaded,
		/datum/design/rwd,
		/datum/design/rpd,
		/datum/design/rpd_upgrade/unwrench,
		/datum/design/pneumatic_seal,
	)

/datum/colony_tech_node/advanced_turbines
	id = "advanced_turbines"
	name = "Turbines"
	stage = COLONY_TECH_STAGE_ADVANCED
	prerequisites = list("advanced_components", "industry_atmospherics")
	cost = 9
	purpose = "Run a real generating plant, with the plumbing and instrumentation it needs."
	design_types = list(
		/datum/design/flatpack_turbine_team_fortress_two,
		/datum/design/turbine_part_compressor,
		/datum/design/turbine_part_rotor,
		/datum/design/turbine_part_stator,
		/datum/design/board/turbine_computer,
		/datum/design/board/turbine_compressor,
		/datum/design/board/turbine_rotor,
		/datum/design/board/turbine_stator,
	)

/datum/colony_tech_node/advanced_fieldwork
	id = "advanced_fieldwork"
	name = "Field Equipment"
	stage = COLONY_TECH_STAGE_ADVANCED
	prerequisites = list("advanced_components")
	cost = 6
	purpose = "Equip the people who work furthest from the settlement."
	design_types = list(
		/datum/design/diagnostic_hud,
		/datum/design/engine_goggles,
		/datum/design/engine_goggles_prescription,
		/datum/design/miningsatchel_holding,
	)
