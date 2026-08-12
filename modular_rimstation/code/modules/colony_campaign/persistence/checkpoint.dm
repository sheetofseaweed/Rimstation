/**
 * Staging a checkpoint, checking it is whole, and committing to it.
 *
 * A checkpoint becomes real in one step and one step only: the manifest that names it is written. Everything
 * before that happens in `working/`, where a failure costs nothing, because the previously committed
 * checkpoint is never touched during a commit.
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
	/// Directory it is staged in.
	var/working_path

/datum/campaign_checkpoint/New(campaign_id, generation_id, checkpoint_id)
	. = ..()
	src.campaign_id = campaign_id
	src.generation_id = generation_id
	src.checkpoint_id = checkpoint_id
	working_path = campaign_working_path(campaign_id, generation_id, checkpoint_id)

/**
 * Writes the world and campaign records into the working directory.
 *
 * Returns TRUE only if every artifact was written and the set validated. A partial stage is left on disk
 * deliberately - it is inert without its completion marker, and it is what an admin inspects to find out why
 * a commit failed.
 */
/datum/campaign_checkpoint/proc/stage(datum/campaign_manifest/manifest)
	if(!working_path)
		log_game("Campaign checkpoint staging refused: unsafe path for [campaign_id]/[generation_id]/[checkpoint_id].")
		return FALSE
	if(!istype(manifest) || !manifest.validate())
		log_game("Campaign checkpoint staging refused: the manifest being staged is not valid.")
		return FALSE

	// The map itself. save_world hands back where it landed so we are never guessing.
	var/saved_to = SSworld_save.save_world(silent = TRUE, destination_directory = working_path)
	if(!saved_to)
		log_game("Campaign checkpoint [checkpoint_id] failed: the world save did not complete.")
		return FALSE

	// Campaign-shaped state travels beside the map, not inside it.
	rustg_file_write(json_encode(manifest.serialize()), "[working_path]/campaign.json")

	if(!validate_artifacts())
		log_game("Campaign checkpoint [checkpoint_id] failed artifact validation; it will not be committed.")
		return FALSE

	// Written last, on purpose: this is what makes the set count as finished.
	rustg_file_write(json_encode(build_inventory()), "[working_path]/[CHECKPOINT_COMPLETION_MARKER]")
	return TRUE

/**
 * TRUE when every artifact this checkpoint claims is present and readable.
 *
 * Checks the world save's own completion marker as well as our campaign record: a map that stopped halfway
 * through writing is exactly the thing that must never be promoted.
 */
/datum/campaign_checkpoint/proc/validate_artifacts()
	if(!working_path)
		return FALSE

	if(!fexists("[working_path]/[SSworld_save.get_save_completion_marker()]"))
		log_game("Campaign checkpoint [checkpoint_id] has no world save completion marker.")
		return FALSE

	var/campaign_record = safely_decode_json(rustg_file_read("[working_path]/campaign.json"))
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
	if(!working_path || !fexists("[working_path]/[CHECKPOINT_COMPLETION_MARKER]"))
		return FALSE
	return islist(safely_decode_json(rustg_file_read("[working_path]/[CHECKPOINT_COMPLETION_MARKER]")))

/// What the checkpoint contains, recorded at completion time so drift can be detected later.
/datum/campaign_checkpoint/proc/build_inventory()
	RETURN_TYPE(/list)
	var/list/files = list()
	for(var/filename in flist("[working_path]/"))
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
