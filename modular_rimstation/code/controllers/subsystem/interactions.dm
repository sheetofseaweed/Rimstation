PROCESSING_SUBSYSTEM_DEF(interactions)
	name = "Interactions"
	flags = SS_BACKGROUND | SS_POST_FIRE_TIMING
	init_order = INIT_ORDER_INTERACTIONS
	wait = INTERACTION_SPEED_MIN
	stat_tag = "ACT"

	var/list/datum/interaction/interactions
	var/list/genital_fluids_paths

/datum/controller/subsystem/processing/interactions/Initialize()
	prepare_interactions()
	prepare_genital_fluids()
	log_config("Loaded [LAZYLEN(interactions)] interactions.")
	return SS_INIT_SUCCESS

/datum/controller/subsystem/processing/interactions/stat_entry(msg)
	msg += "|I:[LAZYLEN(interactions)]|"
	return ..()

/datum/controller/subsystem/processing/interactions/proc/prepare_interactions()
	QDEL_LIST_ASSOC_VAL(interactions)
	QDEL_NULL(interactions)
	interactions = list()
	populate_interaction_instances()

/datum/controller/subsystem/processing/interactions/proc/is_blacklisted(mob/living/creature)
	return FALSE

/datum/controller/subsystem/processing/interactions/proc/prepare_genital_fluids()
	var/list/blacklisted = list(
		/datum/reagent/consumable/ethanol,
		/datum/reagent/consumable/poisonberryjuice,
		/datum/reagent/consumable/banana,
		/datum/reagent/consumable/nothing,
		/datum/reagent/consumable/laughter,
		/datum/reagent/consumable/superlaughter,
		/datum/reagent/consumable/doctor_delight,
		/datum/reagent/consumable/red_queen,
		/datum/reagent/consumable/catnip_tea,
		/datum/reagent/consumable/aloejuice,
		/datum/reagent/consumable/nutriment/vitamin,
		/datum/reagent/consumable/sugar,
		/datum/reagent/consumable/capsaicin,
		/datum/reagent/consumable/frostoil,
		/datum/reagent/consumable/condensedcapsaicin,
		/datum/reagent/consumable/garlic,
		/datum/reagent/consumable/sprinkles,
		/datum/reagent/consumable/hot_ramen,
		/datum/reagent/consumable/hell_ramen,
		/datum/reagent/consumable/corn_syrup,
		/datum/reagent/consumable/honey,
		/datum/reagent/consumable/tearjuice,
		/datum/reagent/consumable/entpoly,
		/datum/reagent/consumable/vitfro,
		/datum/reagent/consumable/liquidelectricity,
		/datum/reagent/consumable/char,
		/datum/reagent/consumable/secretsauce,
		/datum/reagent/consumable/enzyme,
	)

	var/list/consumable_list = subtypesof(/datum/reagent/consumable)
	var/list/whitelist_list = list(
		/datum/reagent/water,
		/datum/reagent/drug/aphrodisiac/crocin,
		/datum/reagent/drug/aphrodisiac/crocin/hexacrocin,
		/datum/reagent/drug/aphrodisiac/dopamine,
		/datum/reagent/drug/aphrodisiac/incubus_draft,
		/datum/reagent/drug/aphrodisiac/succubus_milk,
		/datum/reagent/blood,
	)

	LAZYADD(consumable_list, whitelist_list)

	var/list/reagent_list_paths = list()
	for(var/reagent_path in consumable_list)
		if(reagent_path in blacklisted)
			continue
		reagent_list_paths += reagent_path

	var/list/fluid_paths = list()
	for(var/reagent_path in reagent_list_paths)
		var/datum/reagent/reagent = reagent_path
		fluid_paths[initial(reagent.name)] = reagent_path

	genital_fluids_paths = fluid_paths
