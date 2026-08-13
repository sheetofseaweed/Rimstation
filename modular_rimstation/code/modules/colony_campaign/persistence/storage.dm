/**
 * Where campaign data lives on disk, and how the live manifest is chosen.
 *
 * Everything here is server-local, under a gitignored `data/` directory. A campaign holds the only copy of
 * its town, so the layout is built to survive being interrupted at any point rather than to be tidy.
 *
 * ## Why manifests are numbered rather than replaced
 *
 * The obvious design is one `manifest.json`, replaced atomically on commit. BYOND and rust-g between them
 * offer no rename or move - only read, write, append, exists and delete - so "replace" would mean deleting
 * the old file and writing a new one, with a window where a crash leaves no manifest at all.
 *
 * Instead each commit writes a *new* file, `manifest.<sequence>.json`, and nothing ever modifies an existing
 * one. Boot takes the highest sequence that validates. A commit interrupted mid-write leaves a truncated
 * newest file that fails to parse, and the previous manifest - complete and untouched - is still there.
 * Atomicity comes from never mutating what is already committed.
 */

/// How many superseded manifests to keep for recovery.
#define CAMPAIGN_MANIFEST_HISTORY 5

/// Where the server records which campaign it runs.
/proc/active_campaign_pointer_path()
	return "[CAMPAIGN_STORAGE_ROOT][CAMPAIGN_ACTIVE_POINTER]"

/**
 * The campaign this server runs, or null if it runs none.
 *
 * A server is told this rather than working it out. Several campaigns can sit in storage at once, and choosing
 * between them by scanning would mean which colony you get depends on the order a directory listing comes back
 * in - the same class of accident as loading the newest save on disk.
 */
/proc/read_active_campaign_id()
	var/path = active_campaign_pointer_path()
	if(!fexists(path))
		return null

	var/list/record = safely_decode_json(rustg_file_read(path))
	if(!islist(record))
		log_world("Campaign pointer at [path] is unreadable; this server will run no campaign this round.")
		return null

	var/campaign_id = record["campaign_id"]
	if(!is_safe_campaign_id(campaign_id))
		log_world("Campaign pointer names '[campaign_id]', which cannot be a campaign id; this server will run no campaign this round.")
		return null
	return campaign_id

/// Records which campaign this server runs from the next boot onwards. Verified by reading it back.
/proc/write_active_campaign_id(campaign_id)
	if(!is_safe_campaign_id(campaign_id))
		return FALSE

	rustg_file_write(json_encode(list(
		"campaign_id" = campaign_id,
		"recorded_at" = "[world.realtime]",
	)), active_campaign_pointer_path())
	return read_active_campaign_id() == campaign_id

/// Every campaign in storage that has a manifest to load. Offered to an admin, never chosen automatically.
/proc/list_campaign_ids()
	RETURN_TYPE(/list)
	var/list/campaign_ids = list()
	for(var/entry in flist(CAMPAIGN_STORAGE_ROOT))
		var/campaign_id = trim_trailing_slashes("[entry]")
		if(is_safe_campaign_id(campaign_id) && read_latest_manifest_sequence(campaign_id))
			campaign_ids += campaign_id
	return campaign_ids

/// Root directory for one campaign. Returns null if the id could build a path outside the storage root.
/proc/campaign_path(campaign_id)
	if(!is_safe_campaign_id(campaign_id))
		return null
	return "[CAMPAIGN_STORAGE_ROOT][campaign_id]"

/// Root directory for one generation of a campaign.
/proc/campaign_generation_path(campaign_id, generation_id)
	var/campaign_root = campaign_path(campaign_id)
	if(!campaign_root || !is_safe_campaign_id(generation_id))
		return null
	return "[campaign_root]/generations/[generation_id]"

/**
 * Where one checkpoint's artifacts live, staged and committed alike.
 *
 * There is deliberately no separate staging directory. With no rename available, moving a finished checkpoint
 * somewhere else would mean copying every byte of the map and opening a second failure window for no gain -
 * so a checkpoint is written once, in place, and promotion is the manifest naming it. An uncommitted directory
 * sitting beside a committed one is exactly what an admin recovery selection browses.
 */
/proc/campaign_checkpoint_path(campaign_id, generation_id, checkpoint_id)
	var/generation_root = campaign_generation_path(campaign_id, generation_id)
	if(!generation_root || !is_safe_campaign_id(checkpoint_id))
		return null
	return "[generation_root]/checkpoints/[checkpoint_id]"

/// Every checkpoint directory a generation has on disk, committed or not.
/proc/list_campaign_checkpoint_ids(campaign_id, generation_id)
	RETURN_TYPE(/list)
	var/list/checkpoint_ids = list()
	var/generation_root = campaign_generation_path(campaign_id, generation_id)
	if(!generation_root)
		return checkpoint_ids

	for(var/entry in flist("[generation_root]/checkpoints/"))
		var/checkpoint_id = trim_trailing_slashes("[entry]")
		if(is_safe_campaign_id(checkpoint_id))
			checkpoint_ids += checkpoint_id
	return checkpoint_ids

/// Record that a chapter was started. Its absence at boot means the chapter was never reached.
/proc/campaign_chapter_open_path(campaign_id, generation_id, chapter)
	var/generation_root = campaign_generation_path(campaign_id, generation_id)
	if(!generation_root || !isnum(chapter) || chapter < 1)
		return null
	return "[generation_root]/[CAMPAIGN_CHAPTER_OPEN_PREFIX][chapter].json"

/// Record that a chapter finished for a legible reason. An open chapter with no end record was interrupted.
/proc/campaign_chapter_end_path(campaign_id, generation_id, chapter)
	var/generation_root = campaign_generation_path(campaign_id, generation_id)
	if(!generation_root || !isnum(chapter) || chapter < 1)
		return null
	return "[generation_root]/[CAMPAIGN_CHAPTER_END_PREFIX][chapter].json"

/// Where a generation records that it was closed for good.
/proc/campaign_closure_path(campaign_id, generation_id)
	var/generation_root = campaign_generation_path(campaign_id, generation_id)
	if(!generation_root)
		return null
	return "[generation_root]/[CAMPAIGN_CLOSURE_RECORD]"

/// Path of one numbered manifest.
/proc/campaign_manifest_path(campaign_id, sequence)
	var/campaign_root = campaign_path(campaign_id)
	if(!campaign_root || !isnum(sequence) || sequence < 1)
		return null
	return "[campaign_root]/manifest.[sequence].json"

/**
 * Writes the next manifest in sequence. Returns the sequence number written, or null on failure.
 *
 * Never overwrites: if the computed filename somehow exists, that is treated as a failure rather than
 * clobbering a committed manifest.
 */
/proc/write_campaign_manifest(datum/campaign_manifest/manifest)
	if(!istype(manifest) || !manifest.validate())
		return null

	var/next_sequence = (read_latest_manifest_sequence(manifest.campaign_id) || 0) + 1
	var/path = campaign_manifest_path(manifest.campaign_id, next_sequence)
	if(!path || fexists(path))
		log_game("Campaign manifest write refused: [path || "unsafe path"] already exists or is invalid.")
		return null

	rustg_file_write(json_encode(manifest.serialize()), path)

	// Read it back before believing it. A manifest that cannot be reloaded is not a commit.
	var/datum/campaign_manifest/verification = new
	if(!verification.deserialize(safely_decode_json(rustg_file_read(path))))
		log_game("Campaign manifest at [path] did not survive being written; discarding it.")
		fdel(path)
		qdel(verification)
		return null

	qdel(verification)
	prune_old_manifests(manifest.campaign_id, next_sequence)
	return next_sequence

/// json_decode throws on malformed input, which a half-written file very much is.
/proc/safely_decode_json(text)
	if(!istext(text) || !length(text))
		return null
	if(!rustg_json_is_valid(text))
		return null
	return json_decode(text)

/// Highest manifest sequence present on disk, valid or not. Null when the campaign has none.
/proc/read_latest_manifest_sequence(campaign_id)
	var/campaign_root = campaign_path(campaign_id)
	if(!campaign_root)
		return null

	var/highest = null
	for(var/filename in flist("[campaign_root]/"))
		var/sequence = extract_manifest_sequence(filename)
		if(isnull(sequence))
			continue
		if(isnull(highest) || sequence > highest)
			highest = sequence
	return highest

/// Pulls the number out of "manifest.<n>.json", or null if the filename is not one.
/proc/extract_manifest_sequence(filename)
	if(findtext(filename, "manifest.") != 1)
		return null
	if(findtext(filename, ".json") != (length(filename) - 4))
		return null
	var/sequence_text = copytext(filename, length("manifest.") + 1, length(filename) - 4)
	var/sequence = text2num(sequence_text)
	if(!isnum(sequence) || sequence < 1 || sequence != round(sequence))
		return null
	return sequence

/**
 * Loads the newest manifest that actually validates.
 *
 * Walking down from the highest sequence is what makes an interrupted commit survivable: the truncated file
 * fails to parse and the previous, complete manifest is used instead.
 */
/proc/load_active_campaign_manifest(campaign_id)
	RETURN_TYPE(/datum/campaign_manifest)
	var/highest = read_latest_manifest_sequence(campaign_id)
	if(isnull(highest))
		return null

	for(var/sequence = highest; sequence >= 1; sequence--)
		var/path = campaign_manifest_path(campaign_id, sequence)
		if(!path || !fexists(path))
			continue
		var/datum/campaign_manifest/candidate = new
		if(candidate.deserialize(safely_decode_json(rustg_file_read(path))))
			if(sequence != highest)
				log_game("Campaign fell back to manifest [sequence]; newer manifests failed validation.")
			return candidate
		log_game("Campaign manifest [sequence] failed validation; trying the one before it.")
		qdel(candidate)

	return null

/// Deletes manifests older than the history window. Never touches the newest.
/proc/prune_old_manifests(campaign_id, newest_sequence)
	var/oldest_to_keep = newest_sequence - CAMPAIGN_MANIFEST_HISTORY
	if(oldest_to_keep < 1)
		return
	for(var/sequence = oldest_to_keep; sequence >= 1; sequence--)
		var/path = campaign_manifest_path(campaign_id, sequence)
		if(path && fexists(path))
			fdel(path)

#undef CAMPAIGN_MANIFEST_HISTORY
