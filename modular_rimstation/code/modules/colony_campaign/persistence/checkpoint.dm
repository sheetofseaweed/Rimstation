/**
 * Staging a checkpoint, checking it is whole, and committing to it.
 *
 * A checkpoint becomes real in one step and one step only: the manifest that names it is written. Staging
 * writes into a directory of its own, so a failure costs nothing - the previously committed checkpoint is
 * never touched during a commit, and an unfinished directory is inert.
 *
 * The completion marker is written *last*. Its presence is the difference between "these files exist" and
 * "this checkpoint finished being written", which is the distinction a crashed commit turns on.
 */
/datum/campaign_checkpoint
	/// Which campaign and generation this belongs to.
	var/campaign_id
	var/generation_id
	/// Identity of the checkpoint itself.
	var/checkpoint_id
	/// Directory holding this checkpoint's artifacts.
	var/artifact_path

/datum/campaign_checkpoint/New(campaign_id, generation_id, checkpoint_id)
	. = ..()
	src.campaign_id = campaign_id
	src.generation_id = generation_id
	src.checkpoint_id = checkpoint_id
	artifact_path = campaign_checkpoint_path(campaign_id, generation_id, checkpoint_id)

/**
 * Writes the world and campaign records into this checkpoint's directory.
 *
 * Returns TRUE only if every artifact was written and the set validated. A partial stage is left on disk
 * deliberately - it is inert without its completion marker, and it is what an admin inspects to find out why
 * a commit failed.
 */
/datum/campaign_checkpoint/proc/stage(datum/campaign_manifest/manifest)
	if(!artifact_path)
		log_game("Campaign checkpoint staging refused: unsafe path for [campaign_id]/[generation_id]/[checkpoint_id].")
		return FALSE
	if(!istype(manifest) || !manifest.validate())
		log_game("Campaign checkpoint staging refused: the manifest being staged is not valid.")
		return FALSE

	if(!stage_world_artifacts())
		log_game("Campaign checkpoint [checkpoint_id] failed: the world save did not complete.")
		return FALSE

	// Campaign-shaped state travels beside the map, not inside it.
	rustg_file_write(json_encode(manifest.serialize()), "[artifact_path]/campaign.json")

	if(!validate_artifacts())
		log_game("Campaign checkpoint [checkpoint_id] failed artifact validation; it will not be committed.")
		return FALSE

	// Written last, on purpose: this is what makes the set count as finished.
	rustg_file_write(json_encode(build_inventory()), "[artifact_path]/[CHECKPOINT_COMPLETION_MARKER]")
	return TRUE

/**
 * Writes the map itself, returning where it landed.
 *
 * Its own proc because it is the one part of staging that cannot run during a test - world saving is blocked
 * outright under UNIT_TESTS - so the tests replace this and let the rest of staging run for real.
 */
/datum/campaign_checkpoint/proc/stage_world_artifacts()
	return SSworld_save.save_world(silent = TRUE, destination_directory = artifact_path)

/**
 * TRUE when every artifact this checkpoint claims is present and readable.
 *
 * Checks the world save's own completion marker as well as our campaign record: a map that stopped halfway
 * through writing is exactly the thing that must never be promoted.
 */
/datum/campaign_checkpoint/proc/validate_artifacts()
	if(!artifact_path)
		return FALSE

	if(!fexists("[artifact_path]/[SSworld_save.get_save_completion_marker()]"))
		log_game("Campaign checkpoint [checkpoint_id] has no world save completion marker.")
		return FALSE

	var/campaign_record = safely_decode_json(rustg_file_read("[artifact_path]/campaign.json"))
	if(!islist(campaign_record))
		log_game("Campaign checkpoint [checkpoint_id] has no readable campaign record.")
		return FALSE

	// Cross-reference: a checkpoint that describes a different generation would load the wrong town.
	if(campaign_record["generation_id"] != generation_id)
		log_game("Campaign checkpoint [checkpoint_id] belongs to generation [campaign_record["generation_id"]], not [generation_id].")
		return FALSE

	var/datum/campaign_manifest/staged = new
	var/record_is_valid = staged.deserialize(campaign_record)
	qdel(staged)
	if(!record_is_valid)
		log_game("Campaign checkpoint [checkpoint_id] contains a campaign record that does not validate.")
		return FALSE

	return TRUE

/// TRUE when this checkpoint finished being written and may be committed to.
/datum/campaign_checkpoint/proc/is_complete()
	if(!artifact_path || !fexists("[artifact_path]/[CHECKPOINT_COMPLETION_MARKER]"))
		return FALSE
	return islist(safely_decode_json(rustg_file_read("[artifact_path]/[CHECKPOINT_COMPLETION_MARKER]")))

/// What the checkpoint contains, recorded at completion time so drift can be detected later.
/datum/campaign_checkpoint/proc/build_inventory()
	RETURN_TYPE(/list)
	var/list/files = list()
	for(var/filename in flist("[artifact_path]/"))
		files += filename
	return list(
		"checkpoint_id" = checkpoint_id,
		"generation_id" = generation_id,
		"campaign_id" = campaign_id,
		"written_at" = "[world.realtime]",
		"files" = files,
	)

/**
 * Points the campaign at this checkpoint. This is the moment the commit happens.
 *
 * Refuses an incomplete checkpoint, and writes the manifest through the numbered-sequence scheme so that a
 * failure here leaves the previous manifest complete and untouched. Returns TRUE only once the new manifest
 * has been written and read back successfully.
 */
/datum/campaign_checkpoint/proc/commit(datum/campaign_manifest/manifest)
	if(!is_complete())
		log_game("Campaign refused to commit checkpoint [checkpoint_id]: it is not marked complete.")
		return FALSE
	if(!istype(manifest))
		return FALSE

	// Take a copy so a refused write cannot leave the live manifest pointing at an uncommitted checkpoint.
	var/datum/campaign_manifest/promoted = new
	if(!promoted.deserialize(manifest.serialize()))
		qdel(promoted)
		return FALSE
	promoted.active_checkpoint_id = checkpoint_id
	promoted.chapter = manifest.chapter + 1
	promoted.last_outcome = COLONY_OUTCOME_SUCCESS

	var/sequence = write_campaign_manifest(promoted)
	if(isnull(sequence))
		qdel(promoted)
		log_game("Campaign commit of checkpoint [checkpoint_id] failed while writing the manifest; the previous manifest still stands.")
		return FALSE

	// Only now does the live manifest change.
	manifest.active_checkpoint_id = promoted.active_checkpoint_id
	manifest.chapter = promoted.chapter
	manifest.last_outcome = promoted.last_outcome
	qdel(promoted)

	log_game("Campaign committed checkpoint [checkpoint_id] as manifest [sequence].")
	return TRUE
