/datum/reagent/medicine/quarian_antibodies
	name = "Quarian Antibodies"
	description = "Artificial antibodies that stand in for an immune system a quarian does not have. \
		While they last, an open suit is far less likely to make you ill. Useless to anyone else."
	color = "#9692BE"
	ph = 4
	chemical_flags = REAGENT_CAN_BE_SYNTHESIZED

/datum/chemical_reaction/quarian_antibodies
	results = list(/datum/reagent/medicine/quarian_antibodies = 3)
	required_reagents = list(
		/datum/reagent/medicine/leporazine = 1,
		/datum/reagent/medicine/modafinil = 1,
		/datum/reagent/medicine/spaceacillin = 1,
	)
	optimal_temp = 500
	reaction_tags = REACTION_TAG_OTHER

/obj/item/reagent_containers/hypospray/medipen/quarian_antibodies
	name = "quarian antibodies medipen"
	desc = "A medipen of artificial antibodies. Buys a suitless quarian time, and does nothing at all for \
		anyone else."
	volume = 50
	amount_per_transfer_from_this = 50
	list_reagents = list(/datum/reagent/medicine/quarian_antibodies = 50)
