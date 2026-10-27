/datum/species
	/// Locks every member of this species to one physique, whatever the body type preference says.
	/// The body type picker hides itself when this is set.
	var/forced_physique = null
	/// Locks every member of this species to one gender, whatever the gender preference says.
	/// The gender picker stops accepting clicks when this is set.
	var/forced_gender = null

/// Pins the target to this species' fixed physique and gender, where it has them.
/// Must be called from apply_supplementary_body_changes() as well as on_species_gain(): the body type
/// and gender preferences apply after the species one, so setting these at species gain alone is undone.
/datum/species/proc/apply_forced_body(mob/living/carbon/human/target)
	. = FALSE
	if(!isnull(forced_physique))
		target.physique = forced_physique
		. = TRUE
	if(!isnull(forced_gender))
		target.gender = forced_gender
		. = TRUE

/// Upstream never defines this, so it is ours to add rather than an edit to gender.dm.
/// update_preference() refuses a change when this is FALSE, so the picker stops taking clicks.
/// It cannot be hidden from here: MainPage.tsx draws the gender buttons itself and never asks.
/datum/preference/choiced/gender/is_accessible(datum/preferences/preferences)
	if(!..(preferences))
		return FALSE

	var/datum/species/species = preferences.read_preference(/datum/preference/choiced/species)
	return isnull(initial(species.forced_gender))
